#!/bin/bash
# Build the macOS 11 compatibility edition (universal arm64 + x86_64).
set -euo pipefail
cd "$(dirname "$0")"

OUT=".build/compat"
APP="$OUT/Glint.app"
SDK="$(xcrun --show-sdk-path)"
mkdir -p .build/modulecache11 "$OUT"
rm -rf "$APP" "$OUT/Glint-arm64" "$OUT/Glint-x86_64"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

build_slice() {
    local arch="$1"
    local bin="$2"
    echo "==> 编译 macOS 11 兼容版 ($arch)"
    swiftc \
        -swift-version 5 \
        -D GLINT_COMPAT \
        -O -whole-module-optimization \
        -target "${arch}-apple-macos11.0" \
        -sdk "$SDK" \
        -module-cache-path "$PWD/.build/modulecache11" \
        Sources/*.swift \
        -o "$bin" \
        -framework AppKit \
        -framework AVFoundation \
        -framework AVKit \
        -framework Carbon \
        -framework QuartzCore \
        -framework ImageIO \
        -framework UniformTypeIdentifiers \
        -framework CoreMedia \
        -framework Vision
}

build_slice arm64 "$OUT/Glint-arm64"
build_slice x86_64 "$OUT/Glint-x86_64"
lipo -create "$OUT/Glint-arm64" "$OUT/Glint-x86_64" -output "$APP/Contents/MacOS/Glint"
cp Info-compat.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f Resources/Glint.icns ]; then
    cp Resources/Glint.icns "$APP/Contents/Resources/Glint.icns"
fi
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "    (签名跳过)"
echo "完成: $PWD/$APP"
lipo -info "$APP/Contents/MacOS/Glint"
