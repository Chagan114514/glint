#!/bin/bash
# Build a styled Glint DMG. Requires Python 3 and network access on first run
# (dmgbuild is installed into .build/dmg-tools).
set -euo pipefail
cd "$(dirname "$0")"

APP="Glint.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="Glint-${VERSION}.dmg"
PYTHON="${PYTHON:-python3}"
TOOLS=".build/dmg-tools"

if [ ! -d "$APP" ]; then
    echo "==> 未找到 $APP，请先运行 ./build.sh"
    exit 1
fi

if ! PYTHONPATH="$TOOLS" "$PYTHON" -c 'import dmgbuild' >/dev/null 2>&1; then
    echo "==> 安装 dmgbuild 到 $TOOLS"
    mkdir -p "$TOOLS"
    "$PYTHON" -m pip install --disable-pip-version-check --target "$TOOLS" dmgbuild
fi

rm -f "$DMG"
echo "==> 生成 $DMG"
GLINT_DMG_VOLUME="Glint ${VERSION}" PYTHONPATH="$TOOLS" "$PYTHON" -m dmgbuild -s dmg_settings.py "Glint ${VERSION}" "$DMG"

echo "完成: $PWD/$DMG"
