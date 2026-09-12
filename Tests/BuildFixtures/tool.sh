#!/bin/sh
set -eu

tool=${0##*/}
if [ "$tool" = "${SHADE_TEST_FAIL_TOOL:-}" ]; then
    echo "injected $tool failure" >&2
    exit 42
fi

case "$tool" in
    swift)
        case "$*" in
            *--verify-generated) ;;
            *--show-bin-path*) printf '%s\n' "$SHADE_TEST_PRODUCTS" ;;
            scripts/prepare-resource-overlay.swift*) printf '%s\n' "$SHADE_TEST_PRODUCTS/overlay.json" ;;
        esac
        ;;
    cp) exec /bin/cp "$@" ;;
    plutil|codesign) exec "/usr/bin/$tool" "$@" ;;
    *) echo "unexpected fixture command: $tool" >&2; exit 1 ;;
esac
