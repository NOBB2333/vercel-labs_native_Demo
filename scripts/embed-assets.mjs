import { readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";

const [distArg, loaderArg, ...rest] = process.argv.slice(2);
const bundleArg = rest.at(-2);
const sourceArg = rest.at(-1);
const extraArgs = rest.slice(0, -2);
if (!distArg || !bundleArg || !sourceArg) {
  console.error(
    "用法：embed-assets.mjs <dist> <loader-or-> [extra-file ...] <bundle> <zig-source>",
  );
  process.exit(2);
}

const dist = resolve(distArg);
const files = [];
function visit(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true }).sort((a, b) =>
    a.name.localeCompare(b.name),
  )) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) visit(path);
    else if (entry.isFile())
      files.push({ path: relative(dist, path).replaceAll("\\", "/"), bytes: readFileSync(path) });
  }
}
visit(dist);
if (loaderArg && loaderArg !== "-") {
  const loader = resolve(loaderArg);
  if (statSync(loader).isFile())
    files.push({ path: "__native/WebView2Loader.dll", bytes: readFileSync(loader) });
}
for (const extraArg of extraArgs) {
  const extra = resolve(extraArg);
  if (statSync(extra).isFile())
    files.push({
      path: `assets/${relative(resolve("assets"), extra).replaceAll("\\", "/")}`,
      bytes: readFileSync(extra),
    });
}

const chunks = [Buffer.from("LDF1\0", "ascii")];
for (const file of files) {
  const name = Buffer.from(file.path, "utf8");
  const header = Buffer.alloc(12);
  header.writeUInt32LE(name.length, 0);
  header.writeBigUInt64LE(BigInt(file.bytes.length), 4);
  chunks.push(header, name, file.bytes);
}
writeFileSync(bundleArg, Buffer.concat(chunks));
writeFileSync(
  sourceArg,
  `pub const bytes = @embedFile("${resolve(bundleArg).replaceAll("\\", "/")}");\n`,
);
