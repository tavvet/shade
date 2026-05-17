#!/usr/bin/env bash
# Build Resources/AppIcon.icns from a single 1024×1024 source PNG.
# Usage:  ./Scripts/make-icon.sh path/to/source.png
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <source-1024.png>" >&2
    exit 1
fi

SRC="$1"
if [[ ! -f "${SRC}" ]]; then
    echo "error: ${SRC} not found" >&2
    exit 1
fi

cd "$(dirname "$0")/.."

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "${ICONSET}"

# Apple-required sizes for .icns. sips is built into macOS.
declare -a SPECS=(
    "16     icon_16x16.png"
    "32     icon_16x16@2x.png"
    "32     icon_32x32.png"
    "64     icon_32x32@2x.png"
    "128    icon_128x128.png"
    "256    icon_128x128@2x.png"
    "256    icon_256x256.png"
    "512    icon_256x256@2x.png"
    "512    icon_512x512.png"
    "1024   icon_512x512@2x.png"
)
for spec in "${SPECS[@]}"; do
    SIZE="$(echo "${spec}" | awk '{print $1}')"
    NAME="$(echo "${spec}" | awk '{print $2}')"
    sips -z "${SIZE}" "${SIZE}" "${SRC}" --out "${ICONSET}/${NAME}" >/dev/null
done

mkdir -p Resources
iconutil -c icns "${ICONSET}" -o Resources/AppIcon.icns

echo "✓ wrote Resources/AppIcon.icns"
