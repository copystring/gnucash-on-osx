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
grep -Fxq 'include/pcre2.h include/pcre2posix.h' \
    "$repository/dependencies-gtk4.txt"
grep -Fxq 'include/zconf.h include/zlib.h' \
    "$repository/dependencies-gtk4.txt"
grep -Fxq 'include/gobject-introspection-1.0/' \
    "$repository/dependencies-gtk4.txt"
grep -Fxq 'lib/libgirepository-1.0.dylib lib/libgirepository-1.0.1.dylib' \
    "$repository/dependencies-gtk4.txt"
grep -Fxq 'include/epoxy/' "$repository/dependencies-gtk4.txt"
grep -Fxq 'include/fontconfig/' "$repository/dependencies-gtk4.txt"
grep -Fxq 'include/freetype2/' "$repository/dependencies-gtk4.txt"
grep -Fxq 'include/libxml2/' "$repository/dependencies-gtk4.txt"
grep -Fxq 'include/jconfig.h include/jerror.h include/jmorecfg.h include/jpeglib.h' \
    "$repository/dependencies-gtk4.txt"
grep -Fxq 'include/tiff.h include/tiffconf.h include/tiffio.h include/tiffvers.h' \
    "$repository/dependencies-gtk4.txt"
grep -Fxq 'lib/girepository-1.0/' "$repository/dependencies-gtk4.txt"
grep -Fxq 'share/gir-1.0/' "$repository/dependencies-gtk4.txt"
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
leaf_line="$(grep -n 'for module in libffi libpcre2 zlib-gtk4-refresh fontconfig libjpeg libtiff libepoxy' "$workflow" | cut -d: -f1)"
gdbus_line="$(grep -n 'verify-gtk4-refresh-gdbus-codegen.sh' "$workflow" | cut -d: -f1)"
native_verify_line="$(grep -n 'verify-gtk4-refresh-build-closure.sh' "$workflow" | cut -d: -f1 | head -n 1)"
verify_line="$(grep -n 'verify-gtk4-refresh-build-closure.sh' "$workflow" | cut -d: -f1 | tail -n 1)"
gi_line="$(grep -Fn '            gobject-introspection \' "$workflow" | cut -d: -f1)"
glib_line="$(grep -Fn '            glib \' "$workflow" | cut -d: -f1)"
harfbuzz_line="$(grep -Fn '            harfbuzz \' "$workflow" | cut -d: -f1)"
pango_line="$(grep -Fn '            pango \' "$workflow" | cut -d: -f1)"
pixbuf_line="$(grep -Fn '            gdk-pixbuf \' "$workflow" | cut -d: -f1)"
graphene_line="$(grep -Fn '            graphene' "$workflow" | cut -d: -f1)"
gtk_line="$(grep -n 'buildone --force --no-network gtk-4' "$workflow" | cut -d: -f1)"
test -n "$leaf_line"
test -n "$gdbus_line"
test -n "$verify_line"
test -n "$native_verify_line"
test -n "$gi_line"
test -n "$glib_line"
test -n "$harfbuzz_line"
test -n "$pango_line"
test -n "$pixbuf_line"
test -n "$graphene_line"
test -n "$gtk_line"
test "$gdbus_line" -lt "$leaf_line"
test "$leaf_line" -lt "$native_verify_line"
test "$native_verify_line" -lt "$gi_line"
test "$gi_line" -lt "$glib_line"
test "$glib_line" -lt "$harfbuzz_line"
test "$harfbuzz_line" -lt "$pango_line"
test "$pango_line" -lt "$pixbuf_line"
test "$pixbuf_line" -lt "$graphene_line"
test "$graphene_line" -lt "$verify_line"
test "$verify_line" -lt "$gtk_line"

prefix="$fixture/prefix"
mkdir -p "$prefix/bin" \
    "$prefix/include/atk" \
    "$prefix/include/cairo" \
    "$prefix/include/epoxy" \
    "$prefix/include/fontconfig" \
    "$prefix/include/freetype2/freetype" \
    "$prefix/include/fribidi" \
    "$prefix/include/gdk-pixbuf/gdk-pixbuf" \
    "$prefix/include/glib-2.0/gio" \
    "$prefix/include/graphene-1.0" \
    "$prefix/include/gobject-introspection-1.0" \
    "$prefix/include/harfbuzz" \
    "$prefix/include/pango" \
    "$prefix/include/unicode" \
    "$prefix/lib/girepository-1.0" \
    "$prefix/share/gir-1.0" \
    "$prefix/share/glib-2.0/codegen"
for header in \
    ffi.h \
    ffitarget.h \
    pcre2.h \
    pcre2posix.h \
    zconf.h \
    zlib.h \
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
    fribidi/fribidi.h \
    gdk-pixbuf/gdk-pixbuf.h \
    glib-2.0/gio/gio.h \
    glib-2.0/glib.h \
    glib-2.0/glib-object.h \
    glib-2.0/gmodule.h \
    graphene-1.0/graphene.h \
    gobject-introspection-1.0/girepository.h \
    harfbuzz/hb.h \
    pango/pango.h \
    pango/pangocairo.h \
    pango/pangofc-fontmap.h \
    pango/pangoft2.h \
    unicode/uversion.h
do
    : > "$prefix/include/$header"
done

host_python="$(command -v python3 || command -v python)"
cat > "$prefix/bin/python3" <<EOF
#!/usr/bin/env bash
exec "$host_python" "\$@"
EOF

install_gir()
{
    local name="$1"
    local version="$2"
    cat > "$prefix/share/gir-1.0/$name-$version.gir" <<EOF
<?xml version="1.0"?>
<repository xmlns="http://www.gtk.org/introspection/core/1.0" version="1.2">
  <namespace name="$name" version="$version"/>
</repository>
EOF
    printf 'compiled fixture\n' > "$prefix/lib/girepository-1.0/$name-$version.typelib"
}
for identity in \
    cairo:1.0 \
    Gio:2.0 \
    GdkPixbuf:2.0 \
    Pango:1.0 \
    PangoCairo:1.0 \
    Graphene:1.0
do
    install_gir "${identity%%:*}" "${identity#*:}"
done

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
            libpcre2-8) printf '%s\n' 10.47 ;;
            zlib) printf '%s\n' 1.3.2 ;;
            *) echo "Unexpected version package: $2" >&2; exit 1 ;;
        esac
        ;;
    --exists)
        ;;
    --cflags)
        printf '%s\n' "-I$FIXTURE_PREFIX/include -I$FIXTURE_PREFIX/include/glib-2.0 -I$FIXTURE_PREFIX/include/cairo -I$FIXTURE_PREFIX/include/atk -I$FIXTURE_PREFIX/include/epoxy -I$FIXTURE_PREFIX/include/fontconfig -I$FIXTURE_PREFIX/include/freetype2 -I$FIXTURE_PREFIX/include/fribidi -I$FIXTURE_PREFIX/include/gdk-pixbuf -I$FIXTURE_PREFIX/include/graphene-1.0 -I$FIXTURE_PREFIX/include/gobject-introspection-1.0 -I$FIXTURE_PREFIX/include/harfbuzz -I$FIXTURE_PREFIX/include/pango -I$FIXTURE_PREFIX/include/unicode"
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
        ffi.h|ffitarget.h|pcre2.h|pcre2posix.h|zconf.h|zlib.h) header="$FIXTURE_PREFIX/include/$include" ;;
        jconfig.h|jerror.h|jmorecfg.h|jpeglib.h) header="$FIXTURE_PREFIX/include/$include" ;;
        png.h) header="$FIXTURE_PREFIX/include/$include" ;;
        tiff.h|tiffconf.h|tiffio.h|tiffvers.h) header="$FIXTURE_PREFIX/include/$include" ;;
        glib.h|glib-object.h|gmodule.h) header="$FIXTURE_PREFIX/include/glib-2.0/$include" ;;
        gio/gio.h) header="$FIXTURE_PREFIX/include/glib-2.0/$include" ;;
        cairo.h) header="$FIXTURE_PREFIX/include/cairo/$include" ;;
        epoxy/gl.h) header="$FIXTURE_PREFIX/include/$include" ;;
        fontconfig/fontconfig.h) header="$FIXTURE_PREFIX/include/$include" ;;
        ft2build.h) header="$FIXTURE_PREFIX/include/freetype2/$include" ;;
        freetype/freetype.h) header="$FIXTURE_PREFIX/include/freetype2/$include" ;;
        fribidi.h) header="$FIXTURE_PREFIX/include/fribidi/$include" ;;
        atk/atk.h) header="$FIXTURE_PREFIX/include/$include" ;;
        gdk-pixbuf/gdk-pixbuf.h) header="$FIXTURE_PREFIX/include/$include" ;;
        graphene.h) header="$FIXTURE_PREFIX/include/graphene-1.0/$include" ;;
        girepository.h) header="$FIXTURE_PREFIX/include/gobject-introspection-1.0/$include" ;;
        hb.h) header="$FIXTURE_PREFIX/include/harfbuzz/$include" ;;
        pango/pango.h|pango/pangocairo.h|pango/pangofc-fontmap.h|pango/pangoft2.h) header="$FIXTURE_PREFIX/include/$include" ;;
        unicode/uversion.h) header="$FIXTURE_PREFIX/include/$include" ;;
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
CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 10.47 1.3.2

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
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 10.47 1.3.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected missing libffi header to fail' >&2
    exit 1
fi
grep -Fq 'missing the libffi developer header: include/ffi.h' "$fixture/error.log"
: > "$prefix/include/ffi.h"

rm "$prefix/include/pcre2.h"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 10.47 1.3.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected incomplete PCRE2 developer closure to fail' >&2
    exit 1
fi
grep -Fq 'missing a PCRE2 developer header: include/pcre2.h' "$fixture/error.log"
: > "$prefix/include/pcre2.h"

rm "$prefix/include/zconf.h"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 10.47 1.3.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected incomplete zlib developer closure to fail' >&2
    exit 1
fi
grep -Fq 'missing a zlib developer header: include/zconf.h' "$fixture/error.log"
: > "$prefix/include/zconf.h"

rm "$prefix/include/jconfig.h"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 10.47 1.3.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected incomplete libjpeg developer closure to fail' >&2
    exit 1
fi
grep -Fq 'missing a libjpeg developer header: include/jconfig.h' "$fixture/error.log"
: > "$prefix/include/jconfig.h"

rm "$prefix/include/tiffconf.h"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 10.47 1.3.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected incomplete libtiff developer closure to fail' >&2
    exit 1
fi
grep -Fq 'missing a libtiff developer header: include/tiffconf.h' "$fixture/error.log"
: > "$prefix/include/tiffconf.h"

rm "$prefix/include/fontconfig/fontconfig.h"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 10.47 1.3.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected incomplete Fontconfig developer closure to fail' >&2
    exit 1
fi
grep -Fq 'missing the fontconfig developer header: include/fontconfig/fontconfig.h' "$fixture/error.log"
: > "$prefix/include/fontconfig/fontconfig.h"

rm "$prefix/include/freetype2/ft2build.h"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 10.47 1.3.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected incomplete FreeType developer closure to fail' >&2
    exit 1
fi
grep -Fq 'missing the FreeType developer header: include/freetype2/ft2build.h' "$fixture/error.log"
: > "$prefix/include/freetype2/ft2build.h"

rm "$prefix/share/gir-1.0/Gio-2.0.gir"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 10.47 1.3.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected incomplete GTK GIR closure to fail' >&2
    exit 1
fi
grep -Fq 'Missing GIR include: Gio-2.0.gir' "$fixture/error.log"
install_gir Gio 2.0

rm "$prefix/lib/girepository-1.0/Pango-1.0.typelib"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 10.47 1.3.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected missing compiled GTK typelib to fail' >&2
    exit 1
fi
grep -Fq 'Missing compiled typelib: Pango-1.0.typelib' "$fixture/error.log"
install_gir Pango 1.0

rm "$prefix/include/gobject-introspection-1.0/girepository.h"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 10.47 1.3.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected incomplete GObject Introspection developer closure to fail' >&2
    exit 1
fi
grep -Fq 'cannot compile and link the gobject-introspection developer closure' \
    "$fixture/error.log"
: > "$prefix/include/gobject-introspection-1.0/girepository.h"

rm "$prefix/include/pango/pango.h"
if CC="$fixture/cc" bash "$verify" "$prefix" 3.5.2 10.47 1.3.2 >"$fixture/error.log" 2>&1; then
    echo 'Expected incomplete GTK developer closure to fail' >&2
    exit 1
fi
grep -Fq 'cannot compile and link the gtk developer closure' "$fixture/error.log"

echo 'GTK4 refresh build-closure fixtures passed.'
