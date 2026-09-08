param(
    [ValidateSet("All", "Standard", "Portable")]
    [string]$Mode = "All"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $ProjectRoot

if ($env:OS -ne "Windows_NT") {
    throw "package.ps1 只用于 Windows；macOS 或 Linux 请运行 package.sh。"
}

if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    throw "未找到 pnpm，请先安装 Node.js 24 和 pnpm。"
}
if (-not (Get-Command zig -ErrorAction SilentlyContinue)) {
    throw "未找到 Zig，请安装 .zigversion 指定的版本。"
}

& pnpm install --frozen-lockfile
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& pnpm run check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

switch ($Mode) {
    "All" { & zig build package portable "-Dpackage-target=windows" }
    "Standard" { & zig build package "-Dpackage-target=windows" }
    "Portable" { & zig build portable "-Dpackage-target=windows" }
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

switch ($Mode) {
    "All" { & node scripts/package.mjs stage-release windows ReleaseFast }
    "Standard" { & node scripts/package.mjs verify windows ReleaseFast }
    "Portable" { & node scripts/package.mjs verify-portable windows ReleaseFast }
}
exit $LASTEXITCODE
