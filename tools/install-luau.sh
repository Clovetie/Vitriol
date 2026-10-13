#!/usr/bin/env bash
# Install the pinned official Luau CLI into ignored .tools/bin. No Studio changes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/.tools/bin"
if [ -x "$ROOT/.tools/bin/luau-compile" ]; then
  "$ROOT/.tools/bin/luau-compile" --help >/dev/null
  echo 'Luau compiler already installed'
  exit 0
fi
case "$(uname -s):$(uname -m)" in
  Linux:x86_64|Linux:amd64) asset=luau-ubuntu.zip ;;
  Darwin:arm64) asset=luau-macos.zip ;;
  *) echo 'Unsupported platform; install official luau-compile manually into .tools/bin' >&2; exit 1 ;;
esac
archive="$ROOT/.tools/bin/luau-cli.zip"
curl --fail --location --silent --show-error --retry 2 -o "$archive" \
  "https://github.com/luau-lang/luau/releases/download/0.736/$asset"
unzip -oq "$archive" -d "$ROOT/.tools/bin"
rm -f "$archive"
chmod +x "$ROOT/.tools/bin/luau-compile" "$ROOT/.tools/bin/luau-analyze"
"$ROOT/.tools/bin/luau-compile" --help >/dev/null
echo 'Installed official Luau compiler 0.736'
