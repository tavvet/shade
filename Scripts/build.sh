#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP_NAME="Shade"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"

echo "→ swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)"
EXECUTABLE="${BIN_PATH}/${APP_NAME}"

if [[ ! -x "${EXECUTABLE}" ]]; then
    echo "error: executable not found at ${EXECUTABLE}" >&2
    exit 1
fi

echo "→ bundling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
cp "${EXECUTABLE}" "${MACOS_DIR}/${APP_NAME}"
cp Resources/Info.plist "${CONTENTS}/Info.plist"

# Ad-hoc sign so the app can request system permissions cleanly.
codesign --force --sign - "${APP_DIR}" >/dev/null

echo "✓ built ${APP_DIR}"
