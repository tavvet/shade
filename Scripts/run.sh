#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
./Scripts/build.sh

APP_DIR="build/Shade.app"

# Kill previous instance so a fresh build takes over.
pkill -x Shade >/dev/null 2>&1 || true

echo "→ launching ${APP_DIR}"
open "${APP_DIR}"
