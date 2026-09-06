#!/usr/bin/env bash

set -euo pipefail

if test "$#" -ne 1; then
    echo "Usage: $0 APP_BUNDLE" >&2
    exit 2
fi

app="$1"
executable="$app/Contents/MacOS/Gnucash"
settings="$app/Contents/Resources/etc/gtk-4.0/settings.ini"

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
