/** 以 app.json.version 为唯一来源，同步或校验所有发布版本字段。 */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { format } from "oxfmt";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifestPath = resolve(root, "app.json");
const semverPattern =
  /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/;
const jsonTargets = ["package.json", "src_web/package.json"];
const formatOptions = JSON.parse(readFileSync(resolve(root, ".oxfmtrc.json"), "utf8"));

function readVersion() {
  const { version } = JSON.parse(readFileSync(manifestPath, "utf8"));
  if (typeof version !== "string" || !semverPattern.test(version)) {
    throw new Error("app.json 中的 version 必须是有效的 SemVer，例如 1.2.3。");
  }
  return version;
}

async function sync(version, updateSource = false) {
  // 先完成全部解析和格式化，避免输入损坏时只改了一半版本。
  const updates = new Map();
  for (const relativePath of updateSource ? [...jsonTargets, "app.json"] : jsonTargets) {
    const current = JSON.parse(readFileSync(resolve(root, relativePath), "utf8"));
    if (typeof current.version !== "string") throw new Error(`${relativePath} 缺少版本字段。`);
    current.version = version;
    const result = await format(relativePath, JSON.stringify(current), formatOptions);
    if (result.errors.length) throw new Error(`${relativePath} 格式化失败。`);
    updates.set(relativePath, result.code);
  }
  const zon = readFileSync(resolve(root, "build.zig.zon"), "utf8");
  const pattern = /^([ \t]*)\.version\s*=\s*"[^"]+",/m;
  if (!pattern.test(zon)) throw new Error("无法在 build.zig.zon 中定位版本字段。");
  updates.set(
    "build.zig.zon",
    zon.replace(pattern, (_, indent) => `${indent}.version = "${version}",`),
  );
  for (const [relativePath, content] of updates) {
    writeFileSync(resolve(root, relativePath), content, "utf8");
  }
}

function collectVersions() {
  return [
    ["app.json", readVersion()],
    ["package.json", JSON.parse(readFileSync(resolve(root, "package.json"), "utf8")).version],
    [
      "src_web/package.json",
      JSON.parse(readFileSync(resolve(root, "src_web/package.json"), "utf8")).version,
    ],
    [
      "build.zig.zon",
      readFileSync(resolve(root, "build.zig.zon"), "utf8").match(/\.version = "([^"]+)",/)?.[1],
    ],
  ];
}

function check() {
  const expected = readVersion();
  const mismatches = collectVersions().filter(([, value]) => value !== expected);
  if (mismatches.length > 0) {
    for (const [file, value] of mismatches) {
      console.error(`${file}: ${value ?? "未找到"}（应为 ${expected}）`);
    }
    process.exit(1);
  }
  console.log(`版本一致：${expected}`);
}

const [command, ...rawArgs] = process.argv.slice(2);
const [requestedVersion] = rawArgs[0] === "--" ? rawArgs.slice(1) : rawArgs;

try {
  switch (command) {
    case "set": {
      if (!requestedVersion || !semverPattern.test(requestedVersion)) {
        throw new Error("用法：pnpm version:set <SemVer>，例如 pnpm version:set 1.2.3");
      }
      await sync(requestedVersion, true);
      console.log(`版本已更新为 ${requestedVersion}`);
      break;
    }
    case "sync": {
      const version = readVersion();
      await sync(version);
      console.log(`已从 app.json 同步版本 ${version}`);
      break;
    }
    case "check":
      check();
      break;
    default:
      throw new Error("用法：node scripts/version.mjs <set|sync|check> [version]");
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
