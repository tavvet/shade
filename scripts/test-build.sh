#!/bin/sh
set -eu

app=${1:?Usage: test-build.sh <app-path> <configuration>}
configuration=${2:?Missing build configuration}
project=$(pwd -P)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM

# Exercise the installed executable while hiding the developer build tree.
# This catches Bundle.module accidentally falling back to an absolute .build path.
build_path=$(printf '%s' "$project/.build" | sed 's/\\/\\\\/g; s/"/\\"/g')
sandbox-exec -p "(version 1) (allow default) (deny file-read* (subpath \"$build_path\"))" \
    "$app/Contents/MacOS/Shade" --verify-resource-bundles

mkdir -p "$scratch/tools" "$scratch/products"
cp Tests/BuildFixtures/tool.sh "$scratch/tools/tool"
chmod +x "$scratch/tools/tool"
for tool in swift cp plutil codesign; do
    ln -s tool "$scratch/tools/$tool"
done
cp "$app/Contents/MacOS/Shade" "$scratch/products/Shade"
cp -R "$app/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle" "$scratch/products/"
cp -R "$app/Contents/Resources/SwiftTerm_SwiftTerm.bundle" "$scratch/products/"

# Stub compilation only; use the real Makefile recipe, copy/plutil and signing.
# The app under test always lives inside this fixture's temporary directory.
for failure in cp plutil codesign; do
    if env PATH="$scratch/tools:$PATH" SHADE_TEST_PRODUCTS="$scratch/products" \
        SHADE_TEST_FAIL_TOOL="$failure" \
        make --no-print-directory build CONFIG="$configuration" \
        APP_DIR="$scratch/Failure.app" >"$scratch/failure.log" 2>&1; then
        echo "error: make build accepted a failed $failure command" >&2
        exit 1
    fi
    if ! grep -q "injected $failure failure" "$scratch/failure.log"; then
        cat "$scratch/failure.log" >&2
        echo "error: fixture did not reach $failure" >&2
        exit 1
    fi
done

mv "$scratch/products/KeyboardShortcuts_KeyboardShortcuts.bundle" "$scratch/removed.bundle"
if env PATH="$scratch/tools:$PATH" SHADE_TEST_PRODUCTS="$scratch/products" \
    make --no-print-directory build CONFIG="$configuration" \
    APP_DIR="$scratch/Missing.app" >"$scratch/failure.log" 2>&1; then
    echo 'error: make build accepted a missing resource bundle' >&2
    exit 1
fi

cp -R "$app" "$scratch/Incomplete.app"
mv "$scratch/Incomplete.app/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle" \
    "$scratch/incomplete-resources.bundle"
if sh scripts/verify-bundle.sh "$scratch/Incomplete.app" >"$scratch/verify.log" 2>&1; then
    echo 'error: bundle verification accepted missing resources' >&2
    exit 1
fi

cp -R "$app" "$scratch/Unsigned.app"
codesign --remove-signature "$scratch/Unsigned.app"
if sh scripts/verify-bundle.sh "$scratch/Unsigned.app" >"$scratch/verify.log" 2>&1; then
    echo 'error: bundle verification accepted a missing signature' >&2
    exit 1
fi

echo '✓ packaging regression checks passed'
