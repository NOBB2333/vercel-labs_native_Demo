import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  copyFileSync,
  chmodSync,
  cpSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const fixtureFiles = [
  ".oxfmtrc.json",
  "package.json",
  "app.json",
  "build.zig.zon",
  "src_web/package.json",
  "src_web/index.html",
  "scripts/version.mjs",
  "scripts/rename.mjs",
  "scripts/dev-config.mjs",
  "scripts/package.mjs",
  "config/native.json",
];

// 在独立临时模板中运行真实 CLI，避免测试改动当前项目的名称或版本。
function fixture(t) {
  const dir = mkdtempSync(resolve(tmpdir(), "native-template-test-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  for (const file of fixtureFiles) {
    mkdirSync(dirname(resolve(dir, file)), { recursive: true });
    copyFileSync(resolve(root, file), resolve(dir, file));
  }
  symlinkSync(
    resolve(root, "node_modules"),
    resolve(dir, "node_modules"),
    process.platform === "win32" ? "junction" : "dir",
  );
  const read = (file) => readFileSync(resolve(dir, file), "utf8");
  const json = (file) => JSON.parse(read(file));
  const write = (file, content) => writeFileSync(resolve(dir, file), content, "utf8");
  const run = (script, ...args) =>
    spawnSync(process.execPath, [`scripts/${script}.mjs`, ...args], { cwd: dir, encoding: "utf8" });
  const snapshot = () => fixtureFiles.map((file) => read(file));
  return { dir, read, json, write, run, snapshot };
}

test("version set synchronizes valid SemVer without touching nested version fields", (t) => {
  const f = fixture(t);
  const pkg = f.json("package.json");
  const manifest = f.json("app.json");
  f.write("package.json", JSON.stringify({ metadata: { version: "unchanged" }, ...pkg }));
  const version = "1.2.3-beta.1+build.007";
  const result = f.run("version", "set", "--", version);
  assert.equal(result.status, 0, result.stderr);
  for (const file of ["package.json", "src_web/package.json", "app.json"]) {
    assert.equal(f.json(file).version, version);
  }
  assert.equal(f.json("package.json").metadata.version, "unchanged");
  assert.deepEqual(f.json("app.json"), { ...manifest, version });
  assert.ok(f.read("build.zig.zon").includes(`.version = "${version}",`));
  assert.equal(f.run("version", "check").status, 0);
});

test("invalid SemVer is rejected without changing files", (t) => {
  const f = fixture(t);
  const before = f.snapshot();
  for (const version of [
    "01.2.3",
    "1.02.3",
    "1.2.03",
    "1.2.3-01",
    "1.2.3-beta..1",
    "1.2.3+build..1",
    "v1.2.3",
  ]) {
    assert.notEqual(f.run("version", "set", version).status, 0, version);
    assert.deepEqual(f.snapshot(), before);
  }
});

test("version check detects drift and sync repairs it", (t) => {
  const f = fixture(t);
  f.write("app.json", JSON.stringify({ ...f.json("app.json"), version: "2.0.0" }));
  const source = f.read("app.json");
  assert.notEqual(f.run("version", "check").status, 0);
  assert.equal(f.run("version", "sync").status, 0);
  assert.equal(f.read("app.json"), source);
  assert.equal(f.run("version", "check").status, 0);
});

test("version set leaves existing files intact when a target cannot be parsed", (t) => {
  const f = fixture(t);
  f.write("build.zig.zon", ".{}");
  const before = f.snapshot();
  assert.notEqual(f.run("version", "set", "2.0.0").status, 0);
  assert.deepEqual(f.snapshot(), before);
});

test("dev port synchronization preserves the application version and unrelated settings", (t) => {
  const f = fixture(t);
  const manifest = f.json("app.json");
  const result = f.run("dev-config", "set-port", "--", "5180");
  assert.equal(result.status, 0, result.stderr);
  assert.equal(f.json("config/native.json").devServer.port, 5180);
  assert.equal(f.json("app.json").frontend.dev.url, "http://127.0.0.1:5180/");
  assert.equal(f.json("app.json").version, manifest.version);
  assert.deepEqual(f.json("app.json").windows, manifest.windows);
  assert.equal(f.run("dev-config", "check").status, 0);
});

test("dev config rejects noncanonical hosts and preserves the source on synchronization failure", (t) => {
  const f = fixture(t);
  const config = f.json("config/native.json");
  for (const host of ["0.0.0.0", "127.1", "LOCALHOST", "https://localhost"]) {
    f.write(
      "config/native.json",
      JSON.stringify({ ...config, devServer: { ...config.devServer, host } }),
    );
    assert.notEqual(f.run("dev-config", "check").status, 0, host);
  }
  f.write("config/native.json", JSON.stringify(config));
  f.write("app.json", "{");
  const before = f.snapshot();
  assert.notEqual(f.run("dev-config", "set-port", "5180").status, 0);
  assert.deepEqual(f.snapshot(), before);
});

test("portable verification rejects stale frontend resources", (t) => {
  const f = fixture(t);
  mkdirSync(resolve(f.dir, "src_web/dist/assets"), { recursive: true });
  mkdirSync(resolve(f.dir, "zig-out/package"), { recursive: true });
  const manifest = f.json("app.json");
  const artifact = `zig-out/package/${manifest.name}-${manifest.version}-linux-ReleaseFast-portable`;
  f.write("src_web/dist/index.html", "<html>current page</html>");
  f.write("src_web/dist/assets/app.js", "console.log(1)");
  f.write(artifact, "index.html\0<html>current page</html>\0assets/app.js\0console.log(1)");
  chmodSync(resolve(f.dir, artifact), 0o755);
  const valid = f.run("package", "verify-portable", "linux");
  assert.equal(valid.status, 0, valid.stderr);
  f.write("src_web/dist/assets/app.js", "console.log(2)");
  const stale = f.run("package", "verify-portable", "linux");
  assert.notEqual(stale.status, 0);
  assert.match(stale.stderr, /未嵌入当前前端资源/);
});

test("rename handles argument separators and special characters without rewriting commands", (t) => {
  const f = fixture(t);
  const name = '工具 "Desk" \\ <local> & $name';
  const originalScripts = f.json("package.json").scripts;
  const bridge = f.json("app.json").bridge;
  const result = f.run("rename", "--", name, "com.example.tool", "app");
  assert.equal(result.status, 0, result.stderr);
  assert.equal(f.json("app.json").display_name, name);
  assert.equal(f.json("app.json").windows[0].title, name);
  assert.equal(f.json("app.json").id, "com.example.tool");
  assert.equal(f.json("package.json").name, "app");
  assert.equal(f.json("src_web/package.json").name, "app-web");
  assert.ok(f.read("src_web/index.html").includes("&lt;local&gt; &amp; $name"));
  assert.deepEqual(f.json("package.json").scripts, originalScripts);
  assert.deepEqual(f.json("app.json").bridge, bridge);
  assert.equal(f.run("rename", "Second", "com.example.second", "second").status, 0);
  assert.equal(f.json("app.json").name, "second");
  assert.deepEqual(f.json("package.json").scripts, originalScripts);
  assert.deepEqual(f.json("app.json").bridge, bridge);
  assert.equal(f.run("version", "check").status, 0);
});

test("rename rejects invalid identifiers before modifying files", (t) => {
  const f = fixture(t);
  const before = f.snapshot();
  for (const args of [
    ["App", "com.example.app", "123-app"],
    ["App", "com.example.app", "con"],
    ["App", "com.example.app", "test"],
    ["App", "com.example_app.test", "app"],
    ["   ", "com.example.app", "app"],
    ["App\nName", "com.example.app", "app"],
  ]) {
    assert.notEqual(f.run("rename", ...args).status, 0);
    assert.deepEqual(f.snapshot(), before);
  }
});

test("rename validates all targets before writing", (t) => {
  const f = fixture(t);
  f.write("build.zig.zon", ".{}");
  const before = f.snapshot();
  assert.notEqual(f.run("rename", "App", "com.example.app", "app").status, 0);
  assert.deepEqual(f.snapshot(), before);
});

test("renamed and versioned templates compile; direct Zig builds reject version drift", (t) => {
  const f = fixture(t);
  cpSync(resolve(root, "src"), resolve(f.dir, "src"), { recursive: true });
  cpSync(resolve(root, "config"), resolve(f.dir, "config"), { recursive: true });
  copyFileSync(resolve(root, "build.zig"), resolve(f.dir, "build.zig"));
  const renamed = f.run("rename", "--", '工具 "Desk" \\ local', "com.example.review", "review-app");
  assert.equal(renamed.status, 0, renamed.stderr);
  const versioned = f.run("version", "set", "1.2.3-beta.1");
  assert.equal(versioned.status, 0, versioned.stderr);
  const config = f.json("config/native.json");
  f.write(
    "config/native.json",
    JSON.stringify({ ...config, devServer: { host: "[::1]", port: 80, strictPort: true } }),
  );
  const synced = f.run("dev-config", "sync");
  assert.equal(synced.status, 0, synced.stderr);
  assert.equal(f.json("app.json").frontend.dev.url, "http://[::1]/");
  const build = () =>
    spawnSync("zig", ["build", "test", "-Dplatform=null"], {
      cwd: f.dir,
      encoding: "utf8",
      timeout: 60000,
    });
  const valid = build();
  assert.equal(valid.status, 0, valid.stderr);
  f.write("app.json", JSON.stringify({ ...f.json("app.json"), version: "2.0.0" }));
  const drift = build();
  assert.notEqual(drift.status, 0);
  assert.match(drift.stderr, /pnpm version:sync/);
});
