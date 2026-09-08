#!/usr/bin/env sh
set -eu

mode=all
case "${1:-}" in
  ""|--all|--portable) ;;
  --standard-only) mode=standard ;;
  --portable-only) mode=portable ;;
  *)
    echo "用法：./scripts/package.sh [--all|--standard-only|--portable-only]" >&2
    exit 1
    ;;
esac

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

case "$(uname -s)" in
  Darwin) package_target=macos ;;
  Linux) package_target=linux ;;
  *)
    echo "package.sh 只用于 macOS 或 Linux；Windows 请运行 package.ps1。" >&2
    exit 1
    ;;
esac

pnpm install --frozen-lockfile
pnpm run check
case "$mode" in
  all)
    zig build package portable -Dpackage-target="$package_target"
    node scripts/package.mjs stage-release "$package_target" ReleaseFast
    ;;
  standard)
    zig build package -Dpackage-target="$package_target"
    node scripts/package.mjs verify "$package_target" ReleaseFast
    ;;
  portable)
    zig build portable -Dpackage-target="$package_target"
    node scripts/package.mjs verify-portable "$package_target" ReleaseFast
    ;;
esac
