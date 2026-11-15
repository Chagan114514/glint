#!/bin/bash
# Build the compatibility-edition DMG from .build/compat/Glint.app.
set -euo pipefail
cd "$(dirname "$0")"

APP=".build/compat/Glint.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="Glint-${VERSION}-macOS11.dmg"
PYTHON="${PYTHON:-python3}"
TOOLS=".build/dmg-tools"

if [ ! -d "$APP" ]; then
    echo "==> 未找到 $APP，请先运行 ./build-compat.sh"
    exit 1
fi
if ! PYTHONPATH="$TOOLS" "$PYTHON" -c 'import dmgbuild' >/dev/null 2>&1; then
    echo "==> 安装 dmgbuild 到 $TOOLS"
    mkdir -p "$TOOLS"
    "$PYTHON" -m pip install --disable-pip-version-check --target "$TOOLS" dmgbuild
fi
rm -f "$DMG"
echo "==> 生成 $DMG"
GLINT_APP_PATH="$APP" GLINT_DMG_VOLUME="Glint ${VERSION} (macOS 11)" PYTHONPATH="$TOOLS" \
    "$PYTHON" -m dmgbuild -s dmg_settings.py "Glint ${VERSION} (macOS 11)" "$DMG"
echo "完成: $PWD/$DMG"
