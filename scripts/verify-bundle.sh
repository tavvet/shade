#!/bin/sh
set -eu

app=${1:?Usage: verify-bundle.sh <app-path>}
contents="$app/Contents"
resources="$contents/Resources"

test -f "$resources/LICENSE"
test -f "$resources/THIRDPARTY.md"
test -d "$resources/KeyboardShortcuts_KeyboardShortcuts.bundle"
test -d "$resources/SwiftTerm_SwiftTerm.bundle"

bundle_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$contents/Info.plist")
case "$bundle_build" in ''|*[!0-9]*)
    echo "error: invalid CFBundleVersion '$bundle_build'" >&2
    exit 1
esac
if [ "$bundle_build" -le 1 ]; then
    echo 'error: CFBundleVersion must be greater than 1' >&2
    exit 1
fi

codesign --verify --deep --strict "$app"
"$contents/MacOS/Shade" --verify-resource-bundles
echo '✓ verified signature, metadata, license notices and packaged resources'
