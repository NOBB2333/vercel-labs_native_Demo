/**
 * 维护 Vite、Native manifest 与 Zig Bridge 共用的开发地址。
 * config/native.json 是唯一手工配置源，其他文件由本脚本同步。
 */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { format } from "oxfmt";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const configPath = resolve(root, "config/native.json");
const manifestPath = resolve(root, "app.json");

/** 读取并验证唯一开发地址配置。 */
function readConfig(config = JSON.parse(readFileSync(configPath, "utf8"))) {
  const devServer = config.devServer;
  if (!["127.0.0.1", "localhost", "[::1]"].includes(devServer?.host)) {
    throw new Error(
      "config/native.json 的 devServer.host 必须使用 127.0.0.1、localhost 或 [::1]。",
    );
  }
  if (!Number.isInteger(devServer.port) || devServer.port < 1 || devServer.port > 65535) {
    throw new Error("config/native.json 的 devServer.port 必须是 1 到 65535 之间的整数。");
  }
  if (devServer.strictPort !== true) {
    throw new Error(
      "config/native.json 的 devServer.strictPort 必须保持 true，避免 Native Bridge 来源白名单失配。",
    );
  }
  const url = new URL(`http://${devServer.host}:${devServer.port}/`);
  return { ...devServer, origin: url.origin, url: url.href };
}

/** 识别应随本地开发端口变化的 loopback HTTP origin。 */
function isDevelopmentOrigin(value) {
  if (typeof value !== "string") return false;
  try {
    const url = new URL(value);
    return url.protocol === "http:" && ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname);
  } catch {
    return false;
  }
}

function replaceDevelopmentOrigins(origins, expectedOrigin) {
  if (!Array.isArray(origins)) return origins;
  return origins.map((origin) => (isDevelopmentOrigin(origin) ? expectedOrigin : origin));
}

/** 仅将开发地址同步到 manifest。 */
async function sync(config, nativeConfig) {
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  manifest.frontend.dev.url = config.url;
  for (const command of manifest.bridge?.commands ?? []) {
    command.origins = replaceDevelopmentOrigins(command.origins, config.origin);
  }
  manifest.security.navigation.allowed_origins = replaceDevelopmentOrigins(
    manifest.security.navigation.allowed_origins,
    config.origin,
  );
  const options = JSON.parse(readFileSync(resolve(root, ".oxfmtrc.json"), "utf8"));
  const formatted = await format("app.json", JSON.stringify(manifest), options);
  if (formatted.errors.length) throw new Error("app.json 格式化失败。");
  // 目标解析成功后再更新源配置，避免同步失败却已经切换了 Vite 端口。
  writeFileSync(manifestPath, formatted.code, "utf8");
  if (nativeConfig) writeFileSync(configPath, `${JSON.stringify(nativeConfig, null, 2)}\n`, "utf8");
}

/** 检查派生配置，避免启动后才发现 WebView 或 Bridge 指向旧端口。 */
function check(config) {
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  const origins = [
    ...(manifest.bridge?.commands ?? []).flatMap((command) => command.origins ?? []),
    ...(manifest.security?.navigation?.allowed_origins ?? []),
  ].filter(isDevelopmentOrigin);
  const problems = [];
  if (manifest.frontend?.dev?.url !== config.url)
    problems.push(`app.json frontend.dev.url 应为 ${config.url}`);
  if (origins.length === 0 || origins.some((origin) => origin !== config.origin)) {
    problems.push(`app.json 中所有本地开发 origin 应为 ${config.origin}`);
  }
  if (problems.length > 0) {
    for (const problem of problems) console.error(problem);
    console.error("请运行 pnpm dev:config:sync 修复配置漂移。");
    process.exit(1);
  }
  console.log(`开发地址一致：${config.url}（端口冲突时直接报错）`);
}

const [command, ...rawArgs] = process.argv.slice(2);
const [requestedPort] = rawArgs[0] === "--" ? rawArgs.slice(1) : rawArgs;
try {
  if (command === "set-port") {
    const port = Number(requestedPort);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      throw new Error("用法：pnpm dev:port <1-65535>，例如 pnpm dev:port 5180");
    }
    const current = readConfig();
    const nativeConfig = JSON.parse(readFileSync(configPath, "utf8"));
    nativeConfig.devServer = {
      ...nativeConfig.devServer,
      host: current.host,
      port,
      strictPort: true,
    };
    const next = readConfig(nativeConfig);
    await sync(next, nativeConfig);
    console.log(`默认开发端口已更新为 ${port}`);
  } else if (command === "sync") {
    const config = readConfig();
    await sync(config);
    console.log(`开发地址已同步：${config.url}`);
  } else if (command === "check") {
    check(readConfig());
  } else {
    throw new Error("用法：node scripts/dev-config.mjs <set-port|sync|check> [port]");
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
