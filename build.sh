#!/bin/bash
# 编译 Glint.app —— 只需 macOS Command Line Tools，无需 Xcode 工程。
set -euo pipefail
cd "$(dirname "$0")"

APP="Glint.app"
BIN="$APP/Contents/MacOS/Glint"
ARCH="$(uname -m)"
SDK="$(xcrun --show-sdk-path)"

echo "==> 清理"
mkdir -p .build/modulecache
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译 Swift (${ARCH}, macOS 14+)"
swiftc \
    -swift-version 5 \
    -O -whole-module-optimization \
    -target "${ARCH}-apple-macos14.0" \
    -sdk "$SDK" \
    -module-cache-path "$PWD/.build/modulecache" \
    Sources/*.swift \
    -o "$BIN" \
    -framework AppKit \
    -framework ScreenCaptureKit \
    -framework AVFoundation \
    -framework AVKit \
    -framework Carbon \
    -framework QuartzCore \
    -framework ImageIO \
    -framework UniformTypeIdentifiers \
    -framework CoreMedia

echo "==> 打包 Info.plist"
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -f Resources/Glint.icns ]; then
    cp Resources/Glint.icns "$APP/Contents/Resources/Glint.icns"
fi

echo "==> ad-hoc 签名"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "    (签名跳过)"

echo "完成: $PWD/$APP"
