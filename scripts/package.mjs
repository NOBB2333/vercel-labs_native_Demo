/**
 * 集中处理三平台发布产物的清理、portable 复制、Windows loader 与结构校验。
 * shell/PowerShell 只负责宿主入口；文件规则统一放在此处避免两套实现漂移。
 */
import {
  accessSync,
  chmodSync,
  closeSync,
  constants,
  copyFileSync,
  existsSync,
  mkdirSync,
  openSync,
  readSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { basename, dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const supportedTargets = new Set(["windows", "macos", "linux"]);
const supportedModes = new Set(["Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall"]);
const updateFeedAsset = "native-update.json";
const peMachines = new Map([
  [0x8664, "x86_64"],
  [0xaa64, "aarch64"],
]);

function readManifest() {
  return JSON.parse(readFileSync(resolve(root, "app.json"), "utf8"));
}

function validateRepository(repository) {
  if (!/^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\/[A-Za-z0-9_.-]+$/.test(repository)) {
    throw new Error("GitHub 仓库必须使用 owner/repository 格式。");
  }
  return repository;
}

function validateUpdatePublicKey(publicKey) {
  if (!/^[A-Za-z0-9+/]{43}=$/.test(publicKey)) {
    throw new Error("更新公钥必须是 Native SDK 生成的 Base64 Ed25519 公钥。");
  }
  const decoded = Buffer.from(publicKey, "base64");
  if (decoded.length !== 32 || decoded.toString("base64") !== publicKey) {
    throw new Error("更新公钥不是有效的 Base64 Ed25519 公钥。");
  }
}

function expectedUpdateFeedUrl(repository) {
  return `https://github.com/${validateRepository(repository)}/releases/latest/download/${updateFeedAsset}`;
}

function packageInfo(target, optimize = "ReleaseFast") {
  if (!supportedTargets.has(target) || !supportedModes.has(optimize)) {
    throw new Error("目标或优化模式无效；目标使用 windows|macos|linux。");
  }
  const manifest = readManifest();
  const version = manifest.version;
  const baseName = `${manifest.name}-${version}-${target}-${optimize}`;
  const outputRoot = resolve(root, "zig-out", "package");
  const packageDir = resolve(outputRoot, `${baseName}${target === "macos" ? ".app" : ""}`);
  const archiveSuffix = target === "macos" ? ".dmg" : target === "windows" ? ".zip" : ".tar.gz";
  const archivePath = resolve(outputRoot, `${baseName}${archiveSuffix}`);
  const portablePath = resolve(
    outputRoot,
    `${baseName}-portable${target === "windows" ? ".exe" : ""}`,
  );
  const updateArchivePath = resolve(outputRoot, `${baseName}-update.zip`);
  const updateFeedPath = resolve(outputRoot, updateFeedAsset);
  return {
    manifest,
    baseName,
    outputRoot,
    packageDir,
    archiveSuffix,
    archivePath,
    portablePath,
    updateArchivePath,
    updateFeedPath,
  };
}

function assertReadableFile(path) {
  accessSync(path, constants.R_OK);
  const stat = statSync(path);
  if (!stat.isFile() || stat.size === 0) throw new Error(`打包文件无效：${path}`);
}

/** 读取 PE/COFF machine 字段，用于防止 Windows exe 与 loader 架构混装。 */
function peMachine(path) {
  assertReadableFile(path);
  const bytes = readFileSync(path);
  if (bytes.length < 0x40 || bytes[0] !== 0x4d || bytes[1] !== 0x5a) {
    throw new Error(`不是有效的 Windows PE 文件：${path}`);
  }
  const peOffset = bytes.readUInt32LE(0x3c);
  if (
    peOffset + 6 > bytes.length ||
    bytes[peOffset] !== 0x50 ||
    bytes[peOffset + 1] !== 0x45 ||
    bytes[peOffset + 2] !== 0 ||
    bytes[peOffset + 3] !== 0
  ) {
    throw new Error(`Windows PE 文件头损坏：${path}`);
  }
  const machine = bytes.readUInt16LE(peOffset + 4);
  if (!peMachines.has(machine)) {
    throw new Error(`不支持的 Windows PE 架构 0x${machine.toString(16)}：${path}`);
  }
  return machine;
}

function assertPeArchitecture(path, expectedMachine) {
  const actualMachine = peMachine(path);
  if (actualMachine !== expectedMachine) {
    throw new Error(
      `Windows 架构不匹配：${path} 是 ${peMachines.get(actualMachine)}，应为 ${peMachines.get(expectedMachine)}`,
    );
  }
}

function nativeSdkRoot() {
  const nativeConfig = JSON.parse(readFileSync(resolve(root, "config/native.json"), "utf8"));
  return resolve(root, nativeConfig.build.nativeSdkPath);
}

function windowsSdkLoaderPath(machine) {
  const arch = machine === 0xaa64 ? "arm64" : machine === 0x8664 ? "x64" : undefined;
  if (!arch) throw new Error(`没有对应 Windows loader 的 PE 架构：0x${machine.toString(16)}`);
  return resolve(nativeSdkRoot(), "third_party", "webview2", arch, "WebView2Loader.dll");
}

function assertSameBytes(actualPath, expectedPath, message) {
  assertReadableFile(actualPath);
  assertReadableFile(expectedPath);
  if (!readFileSync(actualPath).equals(readFileSync(expectedPath))) {
    throw new Error(`${message}：${actualPath}`);
  }
}

/**
 * 校验仓库保留的 x64 基准 loader，以及锁定 Native SDK 提供的双架构打包输入。
 * 基准文件用于模板审计和恢复；正式产物仍使用 SDK 中与目标架构匹配的文件。
 */
function checkWindowsLoaders() {
  const loaders = [
    [resolve(root, "assets", "WebView2Loader.dll"), 0x8664, "仓库 x64 基准 loader"],
    [windowsSdkLoaderPath(0x8664), 0x8664, "Native SDK x64 loader"],
    [windowsSdkLoaderPath(0xaa64), 0xaa64, "Native SDK arm64 loader"],
  ];
  for (const [path, machine, label] of loaders) {
    assertPeArchitecture(path, machine);
    console.log(`${label} 有效：${relative(root, path)}（${peMachines.get(machine)}）`);
  }
}

/** 删除当前目标的标准目录和归档，不触碰其他平台产物。 */
function prepare(target, optimize) {
  const info = packageInfo(target, optimize);
  for (const path of [
    info.packageDir,
    info.archivePath,
    info.updateArchivePath,
    info.updateFeedPath,
  ]) {
    if (dirname(path) !== info.outputRoot) throw new Error(`拒绝清理非打包目录：${path}`);
    rmSync(path, { force: true, recursive: true });
  }
}

/** 校验 Native SDK 标准包中的可执行文件、前端和平台运行库。 */
function verify(target, optimize) {
  const info = packageInfo(target, optimize);
  const executablePath =
    target === "macos"
      ? resolve(info.packageDir, "Contents", "MacOS", info.manifest.name)
      : resolve(
          info.packageDir,
          "bin",
          `${info.manifest.name}${target === "windows" ? ".exe" : ""}`,
        );
  const frontendPath =
    target === "macos"
      ? resolve(info.packageDir, "Contents", "Resources", "src_web", "dist", "index.html")
      : resolve(info.packageDir, "resources", "src_web", "dist", "index.html");
  const legacyFrontendPath =
    target === "macos"
      ? resolve(info.packageDir, "Contents", "Resources", "frontend")
      : resolve(info.packageDir, "resources", "frontend");

  for (const path of [executablePath, frontendPath, info.archivePath]) assertReadableFile(path);
  if (target === "macos" && info.manifest.updates) assertReadableFile(info.updateArchivePath);
  if (target === "windows") {
    const loaderPath = resolve(info.packageDir, "bin", "WebView2Loader.dll");
    const executableMachine = peMachine(executablePath);
    assertPeArchitecture(loaderPath, executableMachine);
    assertSameBytes(
      loaderPath,
      windowsSdkLoaderPath(executableMachine),
      "Windows 标准包没有携带 Native SDK 的目标架构 loader",
    );
  }
  if (existsSync(legacyFrontendPath)) {
    throw new Error(`发现迁移前的残留资源目录：${legacyFrontendPath}`);
  }
  console.log(`标准包校验通过：${info.baseName}${info.archiveSuffix}`);
}

/** 将已嵌入资源的二进制复制成命名稳定的 portable 发布文件。 */
function createPortable(target, optimize, sourcePath) {
  if (!sourcePath) throw new Error("portable 子命令缺少 Zig 输出文件路径。");
  const info = packageInfo(target, optimize);
  mkdirSync(info.outputRoot, { recursive: true });
  rmSync(info.portablePath, { force: true });
  copyFileSync(resolve(sourcePath), info.portablePath);
  if (target !== "windows") chmodSync(info.portablePath, 0o755);

  if (target === "macos") {
    const signed = spawnSync("codesign", ["--force", "--sign", "-", info.portablePath], {
      encoding: "utf8",
    });
    if (signed.status !== 0) {
      throw new Error(`portable 二进制签名失败：${signed.stderr || signed.stdout}`);
    }
  }
  console.log(`portable 产物已生成：${info.portablePath}`);
}

function verifyPortable(target, optimize) {
  const info = packageInfo(target, optimize);
  assertReadableFile(info.portablePath);
  if (target !== "windows") accessSync(info.portablePath, constants.X_OK);
  const executable = readFileSync(info.portablePath);
  const dist = resolve(root, "src_web", "dist");
  assertReadableFile(resolve(dist, "index.html"));
  function verifyAssets(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = resolve(directory, entry.name);
      if (entry.isDirectory()) verifyAssets(path);
      else if (entry.isFile()) {
        const name = relative(dist, path).replaceAll("\\", "/");
        if (!executable.includes(Buffer.from(name)) || !executable.includes(readFileSync(path))) {
          throw new Error(`portable 未嵌入当前前端资源：${name}；请重新运行 zig build portable。`);
        }
      }
    }
  }
  verifyAssets(dist);
  if (target === "windows") {
    const loaderPath = windowsSdkLoaderPath(peMachine(info.portablePath));
    const loader = readFileSync(loaderPath);
    if (executable.indexOf(loader) === -1) {
      throw new Error(`Windows portable EXE 未嵌入目标架构 loader：${loaderPath}`);
    }
  }
  console.log(`portable 产物校验通过：${info.portablePath}`);
}

function sha256File(path) {
  const hash = createHash("sha256");
  const descriptor = openSync(path, "r");
  const buffer = Buffer.allocUnsafe(64 * 1024);
  try {
    for (;;) {
      const count = readSync(descriptor, buffer, 0, buffer.length, null);
      if (count === 0) break;
      hash.update(buffer.subarray(0, count));
    }
  } finally {
    closeSync(descriptor);
  }
  return hash.digest("hex");
}

/** 只收集经过校验、应公开下载的文件，避免把中间目录上传到 Release。 */
function stageRelease(target, optimize, requireUpdateFeed = false) {
  verify(target, optimize);
  verifyPortable(target, optimize);
  const info = packageInfo(target, optimize);
  const releaseRoot = resolve(root, "zig-out", "release");
  const releaseDir = resolve(releaseRoot, target);
  if (dirname(releaseDir) !== releaseRoot) throw new Error(`拒绝清理非发布目录：${releaseDir}`);
  rmSync(releaseDir, { force: true, recursive: true });
  mkdirSync(releaseDir, { recursive: true });

  const artifacts = [
    { kind: "standard-archive", path: info.archivePath },
    { kind: "portable", path: info.portablePath },
  ];
  if (target === "macos" && info.manifest.updates) {
    artifacts.push({ kind: "update-archive", path: info.updateArchivePath });
    if (existsSync(info.updateFeedPath)) {
      artifacts.push({ kind: "update-feed", path: info.updateFeedPath });
    } else if (requireUpdateFeed) {
      throw new Error("已启用 macOS 更新，但未找到签名后的 native-update.json。");
    }
  }

  const records = artifacts.map((artifact) => {
    assertReadableFile(artifact.path);
    const destination = resolve(releaseDir, basename(artifact.path));
    copyFileSync(artifact.path, destination);
    return {
      kind: artifact.kind,
      file: basename(destination),
      bytes: statSync(destination).size,
      sha256: sha256File(destination),
    };
  });
  const checksums = records.map((record) => `${record.sha256}  ${record.file}`).join("\n");
  writeFileSync(resolve(releaseDir, `${info.baseName}-SHA256SUMS.txt`), `${checksums}\n`, "utf8");
  writeFileSync(
    resolve(releaseDir, `${info.baseName}-manifest.json`),
    `${JSON.stringify(
      {
        schema_version: 1,
        application: {
          id: info.manifest.id,
          name: info.manifest.name,
          version: info.manifest.version,
        },
        target,
        optimize,
        artifacts: records,
      },
      null,
      2,
    )}\n`,
    "utf8",
  );
  console.log(`发布文件已整理到：${relative(root, releaseDir)}`);
}

function formatManifest() {
  const formatted = spawnSync("pnpm", ["exec", "oxfmt", "app.json"], {
    cwd: root,
    encoding: "utf8",
  });
  if (formatted.status !== 0) {
    throw new Error(`app.json 格式化失败：${formatted.stderr || formatted.stdout}`);
  }
}

/** 将 GitHub Release 更新源显式写入应用；模板默认不包含此配置。 */
function configureUpdates(repository, publicKey, checkOnStart = "false") {
  validateRepository(repository);
  validateUpdatePublicKey(publicKey);
  if (!new Set(["true", "false"]).has(checkOnStart)) {
    throw new Error("check-on-start 必须是 true 或 false。");
  }
  const manifestPath = resolve(root, "app.json");
  const manifest = readManifest();
  manifest.updates = {
    feed_url: expectedUpdateFeedUrl(repository),
    public_key: publicKey,
    check_on_start: checkOnStart === "true",
  };
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
  formatManifest();
  console.log(`已启用 macOS GitHub Release 更新：${repository}`);
}

function disableUpdates() {
  const manifestPath = resolve(root, "app.json");
  const manifest = readManifest();
  delete manifest.updates;
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
  formatManifest();
  console.log("已关闭自动更新；模板不再关联更新仓库。");
}

/** 输出 GitHub Actions step output，同时校验 feed 是否属于当前仓库。 */
function printUpdateStatus(repository) {
  const manifest = readManifest();
  if (!manifest.updates) {
    console.log("updates_enabled=false");
    return;
  }
  validateUpdatePublicKey(manifest.updates.public_key);
  if (repository && manifest.updates.feed_url !== expectedUpdateFeedUrl(repository)) {
    throw new Error(`app.json 更新源不属于当前仓库；应为 ${expectedUpdateFeedUrl(repository)}`);
  }
  const info = packageInfo("macos", "ReleaseFast");
  console.log("updates_enabled=true");
  console.log(`update_archive=${relative(root, info.updateArchivePath)}`);
  console.log(`update_feed=${relative(root, info.updateFeedPath)}`);
}

function hostTarget() {
  const target = { win32: "windows", darwin: "macos", linux: "linux" }[process.platform];
  if (!target) throw new Error(`不支持当前宿主平台：${process.platform}`);
  return target;
}

const [command, ...rawArgs] = process.argv.slice(2);
const args = rawArgs[0] === "--" ? rawArgs.slice(1) : rawArgs;
const targetArg = () => args[0] ?? hostTarget();

try {
  if (command === "prepare") prepare(targetArg(), args[1] ?? "ReleaseFast");
  else if (command === "verify") verify(targetArg(), args[1] ?? "ReleaseFast");
  else if (command === "portable") createPortable(targetArg(), args[1] ?? "ReleaseFast", args[2]);
  else if (command === "verify-portable") verifyPortable(targetArg(), args[1] ?? "ReleaseFast");
  else if (command === "stage-release")
    stageRelease(targetArg(), args[1] ?? "ReleaseFast", args.includes("--require-update-feed"));
  else if (command === "configure-updates") configureUpdates(args[0], args[1], args[2]);
  else if (command === "disable-updates") disableUpdates();
  else if (command === "update-status") printUpdateStatus(args[0]);
  else if (command === "check-windows-loaders") checkWindowsLoaders();
  else {
    throw new Error(
      "用法：node scripts/package.mjs <prepare|verify|portable|verify-portable|stage-release|configure-updates|disable-updates|update-status|check-windows-loaders> [...]",
    );
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
