#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
verify="$script_dir/../verify-macos-app-bundle.sh"
metadata="$script_dir/../macos-bundle-metadata.py"
plist_template="$script_dir/../gnucash-bundler/Info-unstable.plist"
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
plist="$app/Contents/Info.plist"
log="$fixture/verify.log"
core_version="5.90"
bundle_revision="1"
copyright_year="2026"
verify_app=(bash "$verify" "$app" "$core_version" "$bundle_revision" \
    "$copyright_year")

assert_fails_with "Missing macOS app bundle: $app" "$log" \
    "${verify_app[@]}"

mkdir -p "$(dirname "$binary")" "$(dirname "$settings")"
: > "$binary"
: > "$settings"
assert_fails_with "Missing or non-executable app binary: $binary" "$log" \
    "${verify_app[@]}"

rm "$binary"
mkdir "$binary"
assert_fails_with "Missing or non-executable app binary: $binary" "$log" \
    "${verify_app[@]}"

rmdir "$binary"
cp "$BASH" "$binary"
rm "$settings"
assert_fails_with "Missing GTK4 settings file: $settings" "$log" \
    "${verify_app[@]}"

: > "$settings"
assert_fails_with "Missing app bundle metadata: $plist" "$log" \
    "${verify_app[@]}"

valid_cache="$fixture/CMakeCache.txt"
printf 'CMAKE_PROJECT_VERSION:STATIC=%s\n' "$core_version" > "$valid_cache"
test "$(python3 "$metadata" core-version "$valid_cache")" = "$core_version"

missing_cache="$fixture/missing-CMakeCache.txt"
: > "$missing_cache"
assert_fails_with 'expected exactly one CMAKE_PROJECT_VERSION:STATIC entry' \
    "$log" python3 "$metadata" core-version "$missing_cache"

duplicate_cache="$fixture/duplicate-CMakeCache.txt"
printf 'CMAKE_PROJECT_VERSION:STATIC=5.90\nCMAKE_PROJECT_VERSION:STATIC=5.91\n' \
    > "$duplicate_cache"
assert_fails_with 'expected exactly one CMAKE_PROJECT_VERSION:STATIC entry' \
    "$log" python3 "$metadata" core-version "$duplicate_cache"

invalid_cache="$fixture/invalid-CMakeCache.txt"
printf 'CMAKE_PROJECT_VERSION:STATIC=5.90.1\n' > "$invalid_cache"
assert_fails_with 'expected major.minor CMake project version' "$log" \
    python3 "$metadata" core-version "$invalid_cache"

assert_fails_with \
    "CFBundleShortVersionString: expected '4.904.0', found '4.904-1'" \
    "$log" python3 "$metadata" verify "$plist_template" 4.904 1 2023

cp "$plist_template" "$plist"
python3 "$metadata" prepare "$plist" "$plist" \
    "$core_version" "$bundle_revision" "$copyright_year"
"${verify_app[@]}"

assert_fails_with "CFBundleVersion: expected '5.90.2', found '5.90.1'" "$log" \
    bash "$verify" "$app" "$core_version" 2 "$copyright_year"

echo "macOS app bundle contract fixtures passed."
