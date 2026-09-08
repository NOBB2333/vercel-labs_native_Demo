#!/usr/bin/env sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

command -v pnpm >/dev/null 2>&1 || {
  echo "未找到 pnpm，请先安装 Node.js 24 和 pnpm。" >&2
  exit 1
}
command -v zig >/dev/null 2>&1 || {
  echo "未找到 Zig，请安装 .zigversion 指定的版本。" >&2
  exit 1
}

pnpm install --frozen-lockfile
exec pnpm run dev
