#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP_NAME="Shade"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

echo "→ swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)"
EXECUTABLE="${BIN_PATH}/${APP_NAME}"

if [[ ! -x "${EXECUTABLE}" ]]; then
    echo "error: executable not found at ${EXECUTABLE}" >&2
    exit 1
fi

# (Re)generate AppIcon.icns from the source PNG if it's missing or stale.
# Source (Resources/AppIcon.png) is checked into the repo; the derived .icns isn't.
if [[ -f Resources/AppIcon.png ]]; then
    if [[ ! -f Resources/AppIcon.icns || Resources/AppIcon.png -nt Resources/AppIcon.icns ]]; then
        ./Scripts/make-icon.sh Resources/AppIcon.png
    fi
fi

echo "→ bundling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${EXECUTABLE}" "${MACOS_DIR}/${APP_NAME}"
cp Resources/Info.plist "${CONTENTS}/Info.plist"

if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"
fi
if [[ -f Resources/MenubarIcon.png ]]; then
    cp Resources/MenubarIcon.png "${RESOURCES_DIR}/MenubarIcon.png"
fi

# Code-sign: real Developer ID if provided, otherwise ad-hoc.
# Pass DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" to sign for distribution.
SIGN_IDENTITY="${DEVELOPER_ID:--}"
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    echo "→ ad-hoc signing"
    codesign --force --sign - "${APP_DIR}" >/dev/null
else
    echo "→ signing with ${SIGN_IDENTITY}"
    codesign --force --options runtime --timestamp \
        --sign "${SIGN_IDENTITY}" "${APP_DIR}"
fi

echo "✓ built ${APP_DIR}"
