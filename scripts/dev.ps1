$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $ProjectRoot

if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    throw "未找到 pnpm，请先安装 Node.js 24 和 pnpm。"
}
if (-not (Get-Command zig -ErrorAction SilentlyContinue)) {
    throw "未找到 Zig，请安装 .zigversion 指定的版本。"
}

& pnpm install --frozen-lockfile
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& pnpm run dev
exit $LASTEXITCODE
