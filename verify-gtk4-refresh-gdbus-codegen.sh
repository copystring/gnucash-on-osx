#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 PREFIX" >&2
    exit 2
fi

prefix="$1"
pkgconf="$prefix/bin/pkgconf"
python="$prefix/bin/python3"
gdbus_codegen="$prefix/bin/gdbus-codegen"

for executable in "$pkgconf" "$python" "$gdbus_codegen"
do
    if [ ! -x "$executable" ]; then
        echo "GTK4 refresh base has no executable build tool: $executable" >&2
        exit 1
    fi
done

for module in __init__.py codegen_main.py config.py parser.py
do
    if [ ! -f "$prefix/share/glib-2.0/codegen/$module" ]; then
        echo "GTK4 refresh base is missing the gdbus-codegen module: $module" >&2
        exit 1
    fi
done

read -r -a compiler <<< "${CC:-cc}"
if ! command -v "${compiler[0]}" >/dev/null 2>&1; then
    echo "GTK4 refresh build compiler is unavailable: ${compiler[0]}" >&2
    exit 1
fi

temporary="$(mktemp -d "${TMPDIR:-/tmp}/gtk4-refresh-gdbus.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT

cat > "$temporary/fixture.xml" <<'EOF'
<node>
  <interface name="org.gnucash.Gtk4Refresh">
    <method name="Ping">
      <arg name="request" type="s" direction="in"/>
    </method>
  </interface>
</node>
EOF

PATH="$prefix/bin:$PATH" "$gdbus_codegen" \
    --generate-c-code "$temporary/gtk4-refresh-gdbus" \
    "$temporary/fixture.xml"
test -s "$temporary/gtk4-refresh-gdbus.c"
test -s "$temporary/gtk4-refresh-gdbus.h"

"$pkgconf" --exists gio-2.0
read -r -a cflags <<< "$("$pkgconf" --cflags gio-2.0)"
"${compiler[@]}" -Werror=implicit-function-declaration \
    "${cflags[@]}" -c "$temporary/gtk4-refresh-gdbus.c" \
    -o "$temporary/gtk4-refresh-gdbus.o"
test -s "$temporary/gtk4-refresh-gdbus.o"

echo "Verified GTK4 refresh gdbus-codegen generation and compile closure."
