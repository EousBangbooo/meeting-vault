#!/bin/bash
# 只写当前原型目录。产物：MeetingVaultPanel.app 与 .build/MeetingVaultPanel。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/.build"
APP="$ROOT/MeetingVaultPanel.app"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos13.0"

case "$APP" in
  "$ROOT"/*.app) ;;
  *) echo "[build] refuse unexpected app path: $APP" >&2; exit 1 ;;
esac

mkdir -p "$BUILD/modulecache"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "[build] swiftc $(swiftc --version | head -1)"
echo "[build] target=$TARGET module-cache=$BUILD/modulecache"

swiftc \
  -O \
  -target "$TARGET" \
  -module-cache-path "$BUILD/modulecache" \
  -framework AppKit \
  -framework Foundation \
  "$ROOT"/Sources/*.swift \
  -o "$BUILD/MeetingVaultPanel"

cp "$BUILD/MeetingVaultPanel" "$APP/Contents/MacOS/MeetingVaultPanel"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
  if codesign --force --sign - "$APP" 2>"$BUILD/codesign.log"; then
    echo "[build] ad-hoc codesign ok"
  else
    echo "[build] WARN: ad-hoc codesign failed, see .build/codesign.log"
  fi
fi

echo "[build] app: $APP"
echo "[build] binary: $BUILD/MeetingVaultPanel"
"$BUILD/MeetingVaultPanel" --help
