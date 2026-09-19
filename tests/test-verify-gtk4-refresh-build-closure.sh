#!/usr/bin/env bash

set -euo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository="$(cd -- "$test_dir/.." && pwd)"
verify="$repository/verify-gtk4-refresh-build-closure.sh"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/gtk4-refresh-closure-fixture.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

grep -Fxq 'include/ffi.h include/ffitarget.h' \
    "$repository/dependencies-gtk4.txt"
grep -Fxq "module_extra_env['gtk-osx-docbook'] = {'LC_ALL':'C'}" \
    "$repository/jhbuildrc-custom"

workflow="$repository/.github/workflows/gtk4-macos-dependencies.yml"
libffi_line="$(grep -n 'buildone --force --no-network libffi' "$workflow" | cut -d: -f1)"
verify_line="$(grep -n 'verify-gtk4-refresh-build-closure.sh' "$workflow" | cut -d: -f1)"
gi_line="$(grep -n 'for module in gobject-introspection libepoxy gtk-4' "$workflow" | cut -d: -f1)"
test -n "$libffi_line"
test -n "$verify_line"
test -n "$gi_line"
test "$libffi_line" -lt "$verify_line"
test "$verify_line" -lt "$gi_line"

prefix="$fixture/prefix"
mkdir -p "$prefix/bin" \
    "$prefix/include/atk" \
    "$prefix/include/cairo" \
    "$prefix/include/gdk-pixbuf/gdk-pixbuf" \
    "$prefix/include/glib-2.0" \
    "$prefix/include/graphene-1.0" \
    "$prefix/include/pango"
for header in \
    ffi.h \
    ffitarget.h \
    atk/atk.h \
    cairo/cairo.h \
    gdk-pixbuf/gdk-pixbuf.h \
    glib-2.0/glib.h \
    graphene-1.0/graphene.h \
    pango/pango.h
do
    : > "$prefix/include/$header"
done

cat > "$prefix/bin/pkgconf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
    --modversion)
        test "$2" = libffi
        printf '%s\n' 3.5.2
        ;;
    --exists)
        ;;
    --cflags)
        printf '%s\n' "-I$FIXTURE_PREFIX/include -I$FIXTURE_PREFIX/include/glib-2.0 -I$FIXTURE_PREFIX/include/cairo -I$FIXTURE_PREFIX/include/atk -I$FIXTURE_PREFIX/include/gdk-pixbuf -I$FIXTURE_PREFIX/include/graphene-1.0 -I$FIXTURE_PREFIX/include/pango"
        ;;
    --libs)
        printf '%s\n' ''
        ;;
    *)
        echo "Unexpected pkgconf invocation: $*" >&2
        exit 1
        ;;
esac
EOF

cat > "$fixture/cc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source_file=
output=
while [ "$#" -gt 0 ]
do
    case "$1" in
        *.c) source_file="$1" ;;
        -o)
            shift
            output="$1"
            ;;
    esac
    shift
done
test -n "$source_file"
test -n "$output"
while IFS= read -r include
do
    case "$include" in
        ffi.h|ffitarget.h) header="$FIXTURE_PREFIX/include/$include" ;;
        glib.h) header="$FIXTURE_PREFIX/include/glib-2.0/$include" ;;
        cairo.h) header="$FIXTURE_PREFIX/include/cairo/$include" ;;
        atk/atk.h) header="$FIXTURE_PREFIX/include/$include" ;;
        gdk-pixbuf/gdk-pixbuf.h) header="$FIXTURE_PREFIX/include/$include" ;;
        graphene.h) header="$FIXTURE_PREFIX/include/graphene-1.0/$include" ;;
        pango/pango.h) header="$FIXTURE_PREFIX/include/$include" ;;
        *) continue ;;
    esac
    test -f "$header" || {
        echo "fixture compiler missing header: $include" >&2
        exit 1
    }
done < <(sed -n 's/^#include <\([^>]*\)>/\1/p' "$source_file")
: > "$output"
EOF
chmod +x "$prefix/bin/pkgconf" "$fixture/cc"

export FIXTURE_PREFIX="$prefix"
CC="$fixture/cc" "$verify" "$prefix" 3.5.2

rm "$prefix/include/ffi.h"
if CC="$fixture/cc" "$verify" "$prefix" 3.5.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected missing libffi header to fail' >&2
    exit 1
fi
grep -Fq 'missing the libffi developer header: include/ffi.h' "$fixture/error.log"
: > "$prefix/include/ffi.h"

rm "$prefix/include/pango/pango.h"
if CC="$fixture/cc" "$verify" "$prefix" 3.5.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected incomplete GTK developer closure to fail' >&2
    exit 1
fi
grep -Fq 'cannot compile and link the gtk developer closure' "$fixture/error.log"

echo 'GTK4 refresh build-closure fixtures passed.'
