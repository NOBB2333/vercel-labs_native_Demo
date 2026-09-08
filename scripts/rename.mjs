/** 按字段修改模板标识，不对源码或文档做全局名称替换。 */
import { readFileSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { format } from "oxfmt";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const rawArgs = process.argv.slice(2);
const [displayName, bundleId, requestedMachineName] =
  rawArgs[0] === "--" ? rawArgs.slice(1) : rawArgs;

function slugify(value) {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/([a-z0-9])([A-Z])/g, "$1-$2")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function crc32(value) {
  let crc = 0xffffffff;
  for (const byte of new TextEncoder().encode(value)) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

try {
  if (!displayName?.trim() || /[\p{Cc}]/u.test(displayName)) {
    throw new Error(
      '用法：pnpm rename -- "显示名称" "com.example.id" [machine-name]；显示名不能为空或包含控制字符。',
    );
  }
  const machineName = requestedMachineName ?? slugify(displayName);
  if (
    !/^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/.test(machineName) ||
    machineName.length > 64 ||
    /^(con|prn|aux|nul|com[0-9]|lpt[0-9])$/.test(machineName)
  ) {
    throw new Error(
      "机器名须以小写字母开头，最多 64 字符，仅含小写字母、数字和单个连字符，且不能是 Windows 保留文件名；中文显示名请提供第三个参数。",
    );
  }
  if (!bundleId || !/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+){2,}$/.test(bundleId)) {
    throw new Error("应用 ID 必须使用反向域名格式，例如 com.example.my-app，不能含下划线。");
  }

  const updates = new Map();
  const formatOptions = JSON.parse(readFileSync(resolve(root, ".oxfmtrc.json"), "utf8"));
  const manifest = JSON.parse(readFileSync(resolve(root, "app.json"), "utf8"));
  const oldDisplayName = manifest.display_name;
  manifest.name = machineName;
  manifest.display_name = displayName;
  manifest.id = bundleId;
  for (const window of manifest.windows ?? []) {
    if (window.title === oldDisplayName) window.title = displayName;
  }
  for (const [path, data] of [
    ["app.json", manifest],
    [
      "package.json",
      { ...JSON.parse(readFileSync(resolve(root, "package.json"), "utf8")), name: machineName },
    ],
    [
      "src_web/package.json",
      {
        ...JSON.parse(readFileSync(resolve(root, "src_web/package.json"), "utf8")),
        name: `${machineName}-web`,
      },
    ],
  ]) {
    const result = await format(path, JSON.stringify(data), formatOptions);
    if (result.errors.length) throw new Error(`${path} 格式化失败。`);
    updates.set(path, result.code);
  }

  const zigName = machineName.replaceAll("-", "_");
  const fingerprint = `0x${crc32(zigName).toString(16).padStart(8, "0")}5a707070`;
  let zon = readFileSync(resolve(root, "build.zig.zon"), "utf8");
  for (const [pattern, replacement] of [
    [/\.name\s*=\s*\.(?:@"[^"]+"|[a-zA-Z_][a-zA-Z0-9_]*),/, `.name = .${zigName},`],
    [/\.fingerprint\s*=\s*0x[0-9a-fA-F]+,/, `.fingerprint = ${fingerprint},`],
  ]) {
    if (!pattern.test(zon)) throw new Error("build.zig.zon 缺少包名或 fingerprint。");
    zon = zon.replace(pattern, () => replacement);
  }
  // 用 Zig 自身验证 ZON，拒绝关键字包名并保持原生格式。
  const formattedZon = spawnSync("zig", ["fmt", "--stdin", "--zon"], {
    input: zon,
    encoding: "utf8",
  });
  if (formattedZon.status !== 0)
    throw new Error(
      `Zig 包名或 ZON 无效，请确认已安装 Zig，且机器名不是 Zig 关键字：${formattedZon.stderr || formattedZon.error?.message}`,
    );
  updates.set("build.zig.zon", formattedZon.stdout);

  const html = readFileSync(resolve(root, "src_web/index.html"), "utf8");
  if (!/<title>[^]*?<\/title>/.test(html)) throw new Error("src_web/index.html 缺少 title。");
  const title = displayName
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
  const result = await format(
    "src_web/index.html",
    html.replace(/<title>[^]*?<\/title>/, () => `<title>${title}</title>`),
    formatOptions,
  );
  if (result.errors.length) throw new Error("src_web/index.html 格式化失败。");
  updates.set("src_web/index.html", result.code);

  // 所有输入验证完成后再写入，失败时保留原配置。
  for (const [path, content] of updates) writeFileSync(resolve(root, path), content, "utf8");
  console.log(`应用已改名为 ${displayName}（${machineName}）。`);
  console.log(`应用 ID：${bundleId}`);
  console.log(`需要时再将项目目录改为 ${machineName}。`);
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
