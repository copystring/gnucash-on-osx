#!/usr/bin/env bash

set -euo pipefail

if test "$#" -ne 4; then
    echo "Usage: $0 APP_BUNDLE CORE_VERSION BUNDLE_REVISION COPYRIGHT_YEAR" >&2
    exit 2
fi

app="$1"
core_version="$2"
bundle_revision="$3"
copyright_year="$4"
executable="$app/Contents/MacOS/Gnucash"
settings="$app/Contents/Resources/etc/gtk-4.0/settings.ini"
guide="$app/Contents/Resources/en.lproj/GnuCash Guide/index.html"
plist="$app/Contents/Info.plist"
script_dir="$(cd "$(dirname "$0")" && pwd)"
python="${PYTHON:-python3}"

if ! test -d "$app"; then
    echo "Missing macOS app bundle: $app" >&2
    exit 1
fi

if ! test -f "$executable" || ! test -x "$executable"; then
    echo "Missing or non-executable app binary: $executable" >&2
    exit 1
fi

if ! test -f "$settings"; then
    echo "Missing GTK4 settings file: $settings" >&2
    exit 1
fi

if ! test -f "$guide"; then
    echo "Missing bundled GnuCash Guide: $guide" >&2
    exit 1
fi

if ! test -f "$plist"; then
    echo "Missing app bundle metadata: $plist" >&2
    exit 1
fi

"$python" "$script_dir/macos-bundle-metadata.py" verify "$plist" \
    "$core_version" "$bundle_revision" "$copyright_year"
"$python" "$script_dir/macos-bundle-metadata.py" verify-minimum-system-version \
    "$plist" "$app/Contents" --otool "${OTOOL:-otool}"
