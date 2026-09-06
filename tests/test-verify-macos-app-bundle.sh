#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
verify="$script_dir/../verify-macos-app-bundle.sh"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/gnucash-app-bundle.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

assert_fails_with()
{
    expected="$1"
    log="$2"
    shift 2

    if "$@" >"$log" 2>&1; then
        echo "Expected command to fail: $*" >&2
        exit 1
    fi
    if ! grep -Fq "$expected" "$log"; then
        echo "Expected diagnostic not found in $log:" >&2
        cat "$log" >&2
        exit 1
    fi
}

app="$fixture/Gnucash.app"
binary="$app/Contents/MacOS/Gnucash"
settings="$app/Contents/Resources/etc/gtk-4.0/settings.ini"
log="$fixture/verify.log"

assert_fails_with "Missing macOS app bundle: $app" "$log" \
    bash "$verify" "$app"

mkdir -p "$(dirname "$binary")" "$(dirname "$settings")"
: > "$binary"
: > "$settings"
assert_fails_with "Missing or non-executable app binary: $binary" "$log" \
    bash "$verify" "$app"

rm "$binary"
mkdir "$binary"
assert_fails_with "Missing or non-executable app binary: $binary" "$log" \
    bash "$verify" "$app"

rmdir "$binary"
cp "$BASH" "$binary"
rm "$settings"
assert_fails_with "Missing GTK4 settings file: $settings" "$log" \
    bash "$verify" "$app"

: > "$settings"
bash "$verify" "$app"

echo "macOS app bundle contract fixtures passed."
