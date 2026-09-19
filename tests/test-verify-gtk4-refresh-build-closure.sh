#!/usr/bin/env bash

set -euo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository="$(cd -- "$test_dir/.." && pwd)"
verify="$repository/verify-gtk4-refresh-build-closure.sh"
verify_gdbus="$repository/verify-gtk4-refresh-gdbus-codegen.sh"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/gtk4-refresh-closure-fixture.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

grep -Fxq 'include/ffi.h include/ffitarget.h' \
    "$repository/dependencies-gtk4.txt"
grep -Fxq 'include/epoxy/' "$repository/dependencies-gtk4.txt"
grep -Fxq 'include/fontconfig/' "$repository/dependencies-gtk4.txt"
grep -Fxq 'include/freetype2/' "$repository/dependencies-gtk4.txt"
grep -Fxq 'include/libxml2/' "$repository/dependencies-gtk4.txt"
grep -Fxq 'include/jconfig.h include/jerror.h include/jmorecfg.h include/jpeglib.h' \
    "$repository/dependencies-gtk4.txt"
grep -Fxq 'include/tiff.h include/tiffconf.h include/tiffio.h include/tiffvers.h' \
    "$repository/dependencies-gtk4.txt"
grep -Fxq 'bin/gdbus-codegen' "$repository/dependencies-gtk4.txt"
grep -Fxq "module_extra_env['gtk-osx-docbook'] = {'LC_ALL':'C'}" \
    "$repository/jhbuildrc-custom"
grep -Fq "if os.environ.get('GTK4_REFRESH_FONTCONFIG_XML_BACKEND') == 'libxml2':" \
    "$repository/jhbuildrc-custom"
grep -Fq "module_mesonargs['fontconfig'] = '-Dxml-backend=libxml2'" \
    "$repository/jhbuildrc-custom"
grep -Fq 'bash "$SCRIPT_DIR/verify-gtk4-refresh-build-closure.sh"' \
    "$repository/depstarball.sh"

workflow="$repository/.github/workflows/gtk4-macos-dependencies.yml"
grep -Fq 'require_version libxml-2.0 2.15.2' "$workflow"
grep -Fq 'test -f "$ROOT_DIR/inst/include/libxml2/libxml/parser.h"' "$workflow"
grep -Fq 'GTK4_REFRESH_FONTCONFIG_XML_BACKEND: libxml2' "$workflow"
leaf_line="$(grep -n 'for module in libffi fontconfig libjpeg libtiff' "$workflow" | cut -d: -f1)"
gdbus_line="$(grep -n 'verify-gtk4-refresh-gdbus-codegen.sh' "$workflow" | cut -d: -f1)"
verify_line="$(grep -n 'verify-gtk4-refresh-build-closure.sh' "$workflow" | cut -d: -f1)"
gi_line="$(grep -n 'for module in gobject-introspection libepoxy' "$workflow" | cut -d: -f1)"
gtk_line="$(grep -n 'buildone --force --no-network gtk-4' "$workflow" | cut -d: -f1)"
test -n "$leaf_line"
test -n "$gdbus_line"
test -n "$verify_line"
test -n "$gi_line"
test -n "$gtk_line"
test "$gdbus_line" -lt "$leaf_line"
test "$leaf_line" -lt "$gi_line"
test "$gi_line" -lt "$verify_line"
test "$verify_line" -lt "$gtk_line"

prefix="$fixture/prefix"
mkdir -p "$prefix/bin" \
    "$prefix/include/atk" \
    "$prefix/include/cairo" \
    "$prefix/include/epoxy" \
    "$prefix/include/fontconfig" \
    "$prefix/include/freetype2/freetype" \
    "$prefix/include/gdk-pixbuf/gdk-pixbuf" \
    "$prefix/include/glib-2.0" \
    "$prefix/include/graphene-1.0" \
    "$prefix/include/pango" \
    "$prefix/share/glib-2.0/codegen"
for header in \
    ffi.h \
    ffitarget.h \
    jconfig.h \
    jerror.h \
    jmorecfg.h \
    jpeglib.h \
    png.h \
    tiff.h \
    tiffconf.h \
    tiffio.h \
    tiffvers.h \
    atk/atk.h \
    cairo/cairo.h \
    epoxy/gl.h \
    fontconfig/fontconfig.h \
    freetype2/ft2build.h \
    freetype2/freetype/freetype.h \
    gdk-pixbuf/gdk-pixbuf.h \
    glib-2.0/glib.h \
    graphene-1.0/graphene.h \
    pango/pango.h \
    pango/pangofc-fontmap.h \
    pango/pangoft2.h
do
    : > "$prefix/include/$header"
done

host_python="$(command -v python3 || command -v python)"
cat > "$prefix/bin/python3" <<EOF
#!/usr/bin/env bash
exec "$host_python" "\$@"
EOF

cat > "$prefix/share/glib-2.0/codegen/__init__.py" <<'EOF'
EOF
cat > "$prefix/share/glib-2.0/codegen/config.py" <<'EOF'
MAJOR_VERSION = 2
MINOR_VERSION = 88
EOF
cat > "$prefix/share/glib-2.0/codegen/parser.py" <<'EOF'
EOF
cat > "$prefix/share/glib-2.0/codegen/codegen_main.py" <<'EOF'
def codegen_main():
    import argparse, pathlib
    parser = argparse.ArgumentParser()
    parser.add_argument('--generate-c-code', required=True)
    parser.add_argument('xml')
    arguments = parser.parse_args()
    output = pathlib.Path(arguments.generate_c_code)
    output.with_suffix('.h').write_text('#pragma once\n')
    output.with_suffix('.c').write_text('#include "gtk4-refresh-gdbus.h"\nint fixture(void) { return 0; }\n')
    return 0
EOF
cat > "$prefix/bin/gdbus-codegen" <<'EOF'
#!/usr/bin/env python3
import os, sys
path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'share', 'glib-2.0'))
sys.path.insert(0, path)
from codegen import codegen_main
sys.exit(codegen_main.codegen_main())
EOF

cat > "$prefix/bin/pkgconf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
    --modversion)
        case "$2" in
            libffi) printf '%s\n' 3.5.2 ;;
            *) echo "Unexpected version package: $2" >&2; exit 1 ;;
        esac
        ;;
    --exists)
        ;;
    --cflags)
        printf '%s\n' "-I$FIXTURE_PREFIX/include -I$FIXTURE_PREFIX/include/glib-2.0 -I$FIXTURE_PREFIX/include/cairo -I$FIXTURE_PREFIX/include/atk -I$FIXTURE_PREFIX/include/epoxy -I$FIXTURE_PREFIX/include/fontconfig -I$FIXTURE_PREFIX/include/freetype2 -I$FIXTURE_PREFIX/include/gdk-pixbuf -I$FIXTURE_PREFIX/include/graphene-1.0 -I$FIXTURE_PREFIX/include/pango"
        ;;
    --libs)
        # Both real package groups have libraries; keep the fixture faithful so
        # macOS Bash 3.2 reaches the fake compiler instead of an empty-array edge.
        printf '%s\n' '-lfixture'
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
        jconfig.h|jerror.h|jmorecfg.h|jpeglib.h) header="$FIXTURE_PREFIX/include/$include" ;;
        png.h) header="$FIXTURE_PREFIX/include/$include" ;;
        tiff.h|tiffconf.h|tiffio.h|tiffvers.h) header="$FIXTURE_PREFIX/include/$include" ;;
        glib.h) header="$FIXTURE_PREFIX/include/glib-2.0/$include" ;;
        cairo.h) header="$FIXTURE_PREFIX/include/cairo/$include" ;;
        epoxy/gl.h) header="$FIXTURE_PREFIX/include/$include" ;;
        fontconfig/fontconfig.h) header="$FIXTURE_PREFIX/include/$include" ;;
        ft2build.h) header="$FIXTURE_PREFIX/include/freetype2/$include" ;;
        freetype/freetype.h) header="$FIXTURE_PREFIX/include/freetype2/$include" ;;
        atk/atk.h) header="$FIXTURE_PREFIX/include/$include" ;;
        gdk-pixbuf/gdk-pixbuf.h) header="$FIXTURE_PREFIX/include/$include" ;;
        graphene.h) header="$FIXTURE_PREFIX/include/graphene-1.0/$include" ;;
        pango/pango.h|pango/pangofc-fontmap.h|pango/pangoft2.h) header="$FIXTURE_PREFIX/include/$include" ;;
        *) continue ;;
    esac
    test -f "$header" || {
        echo "fixture compiler missing header: $include" >&2
        exit 1
    }
done < <(sed -n 's/^#include <\([^>]*\)>/\1/p' "$source_file")
printf 'fixture object\n' > "$output"
EOF
chmod +x "$prefix/bin/pkgconf" "$prefix/bin/python3" \
    "$prefix/bin/gdbus-codegen" "$fixture/cc"

export FIXTURE_PREFIX="$prefix"
CC="$fixture/cc" bash "$verify_gdbus" "$prefix"
CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2

rm "$prefix/share/glib-2.0/codegen/codegen_main.py"
if CC="$fixture/cc" bash "$verify_gdbus" "$prefix" >"$fixture/error.log" 2>&1; then
    echo 'Expected missing gdbus-codegen module to fail' >&2
    exit 1
fi
grep -Fq 'missing the gdbus-codegen module: codegen_main.py' "$fixture/error.log"
cat > "$prefix/share/glib-2.0/codegen/codegen_main.py" <<'EOF'
def codegen_main():
    import argparse, pathlib
    parser = argparse.ArgumentParser()
    parser.add_argument('--generate-c-code', required=True)
    parser.add_argument('xml')
    arguments = parser.parse_args()
    output = pathlib.Path(arguments.generate_c_code)
    output.with_suffix('.h').write_text('#pragma once\n')
    output.with_suffix('.c').write_text('#include "gtk4-refresh-gdbus.h"\nint fixture(void) { return 0; }\n')
    return 0
EOF

rm "$prefix/include/ffi.h"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected missing libffi header to fail' >&2
    exit 1
fi
grep -Fq 'missing the libffi developer header: include/ffi.h' "$fixture/error.log"
: > "$prefix/include/ffi.h"

rm "$prefix/include/jconfig.h"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected incomplete libjpeg developer closure to fail' >&2
    exit 1
fi
grep -Fq 'missing a libjpeg developer header: include/jconfig.h' "$fixture/error.log"
: > "$prefix/include/jconfig.h"

rm "$prefix/include/tiffconf.h"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected incomplete libtiff developer closure to fail' >&2
    exit 1
fi
grep -Fq 'missing a libtiff developer header: include/tiffconf.h' "$fixture/error.log"
: > "$prefix/include/tiffconf.h"

rm "$prefix/include/fontconfig/fontconfig.h"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected incomplete Fontconfig developer closure to fail' >&2
    exit 1
fi
grep -Fq 'missing the fontconfig developer header: include/fontconfig/fontconfig.h' "$fixture/error.log"
: > "$prefix/include/fontconfig/fontconfig.h"

rm "$prefix/include/freetype2/ft2build.h"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected incomplete FreeType developer closure to fail' >&2
    exit 1
fi
grep -Fq 'missing the FreeType developer header: include/freetype2/ft2build.h' "$fixture/error.log"
: > "$prefix/include/freetype2/ft2build.h"

rm "$prefix/include/pango/pango.h"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected incomplete GTK developer closure to fail' >&2
    exit 1
fi
grep -Fq 'cannot compile and link the gtk developer closure' "$fixture/error.log"

echo 'GTK4 refresh build-closure fixtures passed.'
