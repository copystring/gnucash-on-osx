#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
verify="$script_dir/../verify-macos-app-bundle.sh"
metadata="$script_dir/../macos-bundle-metadata.py"
plist_template="$script_dir/../gnucash-bundler/Info-unstable.plist"
python="${PYTHON:-python3}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/gnucash-app-bundle.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
otool="$fixture/otool"

cat > "$otool" <<'EOF'
#!/usr/bin/env bash
set -eu

case "$2" in
  *Gnucash)
    cat <<'OUTPUT'
Load command 1
      cmd LC_BUILD_VERSION
 platform 1
    minos 11.2
Load command 2
      cmd LC_VERSION_MIN_MACOSX
    version 10.13
OUTPUT
    ;;
  *fat)
    cat <<'OUTPUT'
fixture (architecture arm64):
Load command 1
      cmd LC_BUILD_VERSION
 platform 1
    minos 12.3
fixture (architecture x86_64):
Load command 1
      cmd LC_BUILD_VERSION
 platform MACOS
    minos 26.5
OUTPUT
    ;;
  *legacy)
    cat <<'OUTPUT'
Load command 1
      cmd LC_VERSION_MIN_MACOSX
    version 10.15.7
OUTPUT
    ;;
  */missing)
    cat <<'OUTPUT'
Load command 1
      cmd LC_BUILD_VERSION
 platform 1
OUTPUT
    ;;
  */malformed)
    cat <<'OUTPUT'
Load command 1
      cmd LC_BUILD_VERSION
 platform MACOS
    minos eleven.two
OUTPUT
    ;;
  */unreadable)
    echo 'cannot read Mach-O file' >&2
    exit 1
    ;;
  *multiarch-missing)
    cat <<'OUTPUT'
fixture (architecture arm64):
Load command 1
      cmd LC_BUILD_VERSION
 platform 1
    minos 26.5
fixture (architecture x86_64):
Load command 1
      cmd LC_BUILD_VERSION
 platform 1
OUTPUT
    ;;
  *multiarch-no-minimum-command)
    cat <<'OUTPUT'
fixture (architecture arm64):
Load command 1
      cmd LC_BUILD_VERSION
 platform 1
    minos 26.5
fixture (architecture x86_64):
Load command 1
      cmd LC_UUID
OUTPUT
    ;;
  *)
    echo "Unexpected otool fixture: $2" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$otool"
export OTOOL="$otool"

write_mach_o()
{
    printf '\317\372\355\376' > "$1"
}

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
guide="$app/Contents/Resources/en.lproj/GnuCash Guide/index.html"
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
mkdir -p "$app/Contents/Frameworks"
write_mach_o "$app/Contents/Frameworks/fat"
rm "$settings"
assert_fails_with "Missing GTK4 settings file: $settings" "$log" \
    "${verify_app[@]}"

: > "$settings"
mkdir -p "$(dirname "$guide")"
: > "$guide"
assert_fails_with "Missing app bundle metadata: $plist" "$log" \
    "${verify_app[@]}"

valid_cache="$fixture/CMakeCache.txt"
printf 'CMAKE_PROJECT_VERSION:STATIC=%s\n' "$core_version" > "$valid_cache"
test "$("$python" "$metadata" core-version "$valid_cache")" = "$core_version"

missing_cache="$fixture/missing-CMakeCache.txt"
: > "$missing_cache"
assert_fails_with 'expected exactly one CMAKE_PROJECT_VERSION:STATIC entry' \
    "$log" "$python" "$metadata" core-version "$missing_cache"

duplicate_cache="$fixture/duplicate-CMakeCache.txt"
printf 'CMAKE_PROJECT_VERSION:STATIC=5.90\nCMAKE_PROJECT_VERSION:STATIC=5.91\n' \
    > "$duplicate_cache"
assert_fails_with 'expected exactly one CMAKE_PROJECT_VERSION:STATIC entry' \
    "$log" "$python" "$metadata" core-version "$duplicate_cache"

invalid_cache="$fixture/invalid-CMakeCache.txt"
printf 'CMAKE_PROJECT_VERSION:STATIC=5.90.1\n' > "$invalid_cache"
assert_fails_with 'expected major.minor CMake project version' "$log" \
    "$python" "$metadata" core-version "$invalid_cache"

assert_fails_with \
    "CFBundleShortVersionString: expected '4.904.0', found '4.904-1'" \
    "$log" "$python" "$metadata" verify "$plist_template" 4.904 1 2023

cp "$plist_template" "$plist"
rm "$guide"
assert_fails_with "Missing bundled GnuCash Guide: $guide" "$log" \
    "${verify_app[@]}"

: > "$guide"
"$python" "$metadata" prepare "$plist" "$plist" \
    "$core_version" "$bundle_revision" "$copyright_year"
test "$("$python" "$metadata" bundle-minimum-system-version \
    "$app/Contents" --otool "$otool")" = 26.5
test "$("$python" "$metadata" synchronize-minimum-system-version \
    "$plist" "$app/Contents" --otool "$otool")" = 26.5
"${verify_app[@]}"

assert_fails_with "CFBundleVersion: expected '5.90.2', found '5.90.1'" "$log" \
    bash "$verify" "$app" "$core_version" 2 "$copyright_year"

perl -0pi -e 's|<string>26\.5</string>|<string>27.0</string>|' "$plist"
test "$("$python" "$metadata" synchronize-minimum-system-version \
    "$plist" "$app/Contents" --otool "$otool")" = 27.0
"${verify_app[@]}"
perl -0pi -e 's|<string>27\.0</string>|<string>10.13</string>|' "$plist"
assert_fails_with \
    "LSMinimumSystemVersion is lower than an included Mach-O minimum" "$log" \
    "${verify_app[@]}"

minimum_fixture="$fixture/minimum-contents"
mkdir -p "$minimum_fixture"
write_mach_o "$minimum_fixture/fat"
write_mach_o "$minimum_fixture/legacy"
: > "$minimum_fixture/resource.txt"
test "$("$python" "$metadata" bundle-minimum-system-version \
    "$minimum_fixture" --otool "$otool")" = 26.5

for invalid in missing malformed unreadable; do
    invalid_fixture="$fixture/$invalid-contents"
    mkdir "$invalid_fixture"
    write_mach_o "$invalid_fixture/$invalid"
    expected="$invalid"
    if test "$invalid" = malformed; then
        expected="invalid macOS version"
    fi
    assert_fails_with "$expected" "$log" \
        "$python" "$metadata" bundle-minimum-system-version \
        "$invalid_fixture" --otool "$otool"
done

multiarch_fixture="$fixture/multiarch-contents"
mkdir "$multiarch_fixture"
write_mach_o "$multiarch_fixture/multiarch-missing"
assert_fails_with "architecture x86_64" "$log" \
    "$python" "$metadata" bundle-minimum-system-version \
    "$multiarch_fixture" --otool "$otool"

no_minimum_command_fixture="$fixture/multiarch-no-minimum-command-contents"
mkdir "$no_minimum_command_fixture"
write_mach_o "$no_minimum_command_fixture/multiarch-no-minimum-command"
assert_fails_with "architecture x86_64" "$log" \
    "$python" "$metadata" bundle-minimum-system-version \
    "$no_minimum_command_fixture" --otool "$otool"

echo "macOS app bundle contract fixtures passed."
