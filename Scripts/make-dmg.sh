#!/usr/bin/env bash
# Pack build/Shade.app into a distributable build/Shade.dmg with a drag-to-/Applications shortcut.
# Run after ./Scripts/build.sh has produced the bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_DIR="build/Shade.app"
DMG_PATH="build/Shade.dmg"
STAGE_DIR="build/dmg-stage"

if [[ ! -d "${APP_DIR}" ]]; then
    echo "error: ${APP_DIR} not found. Run ./Scripts/build.sh first." >&2
    exit 1
fi

rm -rf "${STAGE_DIR}" "${DMG_PATH}"
mkdir -p "${STAGE_DIR}"

cp -R "${APP_DIR}" "${STAGE_DIR}/Shade.app"
ln -s /Applications "${STAGE_DIR}/Applications"

hdiutil create \
    -volname "Shade" \
    -srcfolder "${STAGE_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" >/dev/null

rm -rf "${STAGE_DIR}"
echo "✓ built ${DMG_PATH}"
