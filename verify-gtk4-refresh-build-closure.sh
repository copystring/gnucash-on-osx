#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 4 ] || [ "$#" -gt 5 ] ||
   { [ "$#" -eq 5 ] && [ "$5" != "--skip-gir" ]; }; then
    echo "Usage: $0 PREFIX EXPECTED_LIBFFI_VERSION EXPECTED_PCRE2_VERSION EXPECTED_ZLIB_VERSION [--skip-gir]" >&2
    exit 2
fi

prefix="$1"
expected_libffi_version="$2"
expected_pcre2_version="$3"
expected_zlib_version="$4"
gir_mode="${5:-}"
pkgconf="$prefix/bin/pkgconf"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -x "$pkgconf" ]; then
    echo "GTK4 refresh base has no executable pkgconf: $pkgconf" >&2
    exit 1
fi

for header in include/ffi.h include/ffitarget.h
do
    if [ ! -f "$prefix/$header" ]; then
        echo "GTK4 refresh base is missing the libffi developer header: $header" >&2
        exit 1
    fi
done

for header in include/pcre2.h include/pcre2posix.h
do
    if [ ! -f "$prefix/$header" ]; then
        echo "GTK4 refresh base is missing a PCRE2 developer header: $header" >&2
        exit 1
    fi
done

for header in include/zconf.h include/zlib.h
do
    if [ ! -f "$prefix/$header" ]; then
        echo "GTK4 refresh base is missing a zlib developer header: $header" >&2
        exit 1
    fi
done

for header in \
    include/jconfig.h \
    include/jerror.h \
    include/jmorecfg.h \
    include/jpeglib.h
do
    if [ ! -f "$prefix/$header" ]; then
        echo "GTK4 refresh base is missing a libjpeg developer header: $header" >&2
        exit 1
    fi
done

if [ ! -f "$prefix/include/fontconfig/fontconfig.h" ]; then
    echo "GTK4 refresh base is missing the fontconfig developer header: include/fontconfig/fontconfig.h" >&2
    exit 1
fi
if [ ! -f "$prefix/include/freetype2/ft2build.h" ]; then
    echo "GTK4 refresh base is missing the FreeType developer header: include/freetype2/ft2build.h" >&2
    exit 1
fi

for header in \
    include/tiff.h \
    include/tiffconf.h \
    include/tiffio.h \
    include/tiffvers.h
do
    if [ ! -f "$prefix/$header" ]; then
        echo "GTK4 refresh base is missing a libtiff developer header: $header" >&2
        exit 1
    fi
done

actual_libffi_version="$("$pkgconf" --modversion libffi)"
if [ "$actual_libffi_version" != "$expected_libffi_version" ]; then
    echo "Expected libffi $expected_libffi_version, got $actual_libffi_version" >&2
    exit 1
fi
actual_pcre2_version="$("$pkgconf" --modversion libpcre2-8)"
if [ "$actual_pcre2_version" != "$expected_pcre2_version" ]; then
    echo "Expected PCRE2 $expected_pcre2_version, got $actual_pcre2_version" >&2
    exit 1
fi
actual_zlib_version="$("$pkgconf" --modversion zlib)"
if [ "$actual_zlib_version" != "$expected_zlib_version" ]; then
    echo "Expected zlib $expected_zlib_version, got $actual_zlib_version" >&2
    exit 1
fi

read -r -a compiler <<< "${CC:-cc}"
if ! command -v "${compiler[0]}" >/dev/null 2>&1; then
    echo "GTK4 refresh build compiler is unavailable: ${compiler[0]}" >&2
    exit 1
fi

temporary="$(mktemp -d "${TMPDIR:-/tmp}/gtk4-refresh-closure.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT

compile_probe()
{
    local label="$1"
    local source="$2"
    shift 2
    local cflags_text
    local libs_text
    local -a cflags=()
    local -a libs=()

    "$pkgconf" --exists "$@"
    cflags_text="$("$pkgconf" --cflags "$@")"
    libs_text="$("$pkgconf" --libs "$@")"
    read -r -a cflags <<< "$cflags_text"
    read -r -a libs <<< "$libs_text"
    if ! "${compiler[@]}" -Werror=implicit-function-declaration \
        "${cflags[@]}" "$source" -o "$temporary/$label" "${libs[@]}"; then
        echo "GTK4 refresh base cannot compile and link the $label developer closure" >&2
        return 1
    fi
}

cat > "$temporary/glib.c" <<'EOF'
#define PCRE2_CODE_UNIT_WIDTH 8
#include <cairo.h>
#include <ffi.h>
#include <glib.h>
#include <pcre2.h>
#include <zlib.h>

int
main(void)
{
    ffi_cif cif;
    ffi_type *arguments[] = { &ffi_type_sint };
    cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1);
    GString *text = g_string_new("gtk4-refresh");
    int error_code;
    PCRE2_SIZE error_offset;
    pcre2_code *regex = pcre2_compile((PCRE2_SPTR) "gtk4", 4, 0,
                                      &error_code, &error_offset, NULL);
    ffi_status status = ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 1,
                                     &ffi_type_void, arguments);
    pcre2_code_free(regex);
    g_string_free(text, TRUE);
    cairo_surface_destroy(surface);
    return status == FFI_OK && regex != NULL && zlibVersion() != NULL ? 0 : 1;
}
EOF

cat > "$temporary/harfbuzz.c" <<'EOF'
#include <cairo.h>
#include <fontconfig/fontconfig.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <glib.h>
#include <hb.h>
#include <png.h>
#include <unicode/uversion.h>
#include <zlib.h>

int
main(void)
{
    FT_Library library;
    FT_Error error = FT_Init_FreeType(&library);
    FcPattern *pattern = FcPatternCreate();
    cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1);
    GString *text = g_string_new("gtk4-refresh");
    hb_buffer_t *buffer = hb_buffer_create();
    UVersionInfo unicode_version;
    u_getVersion(unicode_version);
    if (error == 0)
        FT_Done_FreeType(library);
    FcPatternDestroy(pattern);
    cairo_surface_destroy(surface);
    g_string_free(text, TRUE);
    hb_buffer_destroy(buffer);
    return error != 0 || png_access_version_number() == 0 ||
           zlibVersion() == NULL || unicode_version[0] == 0;
}
EOF

cat > "$temporary/pango.c" <<'EOF'
#include <cairo.h>
#include <fribidi.h>
#include <hb.h>
#include <pango/pango.h>
#include <pango/pangocairo.h>
#include <pango/pangofc-fontmap.h>
#include <pango/pangoft2.h>

int
main(void)
{
    cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1);
    hb_buffer_t *buffer = hb_buffer_create();
    PangoFontMap *font_map = pango_ft2_font_map_new();
    FriBidiCharType bidi_type = fribidi_get_bidi_type('A');
    GType font_map_type = pango_fc_font_map_get_type();
    cairo_surface_destroy(surface);
    hb_buffer_destroy(buffer);
    g_object_unref(font_map);
    return bidi_type == 0 || font_map_type == 0;
}
EOF

cat > "$temporary/gdk-pixbuf.c" <<'EOF'
#include <gio/gio.h>
#include <gmodule.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <png.h>
#include <stdio.h>
#include <jpeglib.h>
#include <tiffio.h>

int
main(void)
{
    GdkPixbuf *pixbuf = gdk_pixbuf_new(GDK_COLORSPACE_RGB, FALSE, 8, 1, 1);
    GInputStream *stream = g_memory_input_stream_new();
    struct jpeg_error_mgr jpeg_error;
    struct jpeg_decompress_struct decoder;
    decoder.err = jpeg_std_error(&jpeg_error);
    jpeg_create_decompress(&decoder);
    jpeg_destroy_decompress(&decoder);
    g_object_unref(stream);
    g_object_unref(pixbuf);
    return !g_module_supported() || png_access_version_number() == 0 ||
           TIFFGetVersion() == NULL;
}
EOF

cat > "$temporary/graphene.c" <<'EOF'
#include <glib-object.h>
#include <graphene.h>

int
main(void)
{
    graphene_point_t point;
    graphene_point_init(&point, 0.0f, 0.0f);
    return g_type_name(G_TYPE_OBJECT) == NULL || point.x != 0.0f;
}
EOF

cat > "$temporary/gobject-introspection.c" <<'EOF'
#include <girepository.h>

int
main(void)
{
    return g_irepository_get_default() == NULL;
}
EOF

cat > "$temporary/gtk.c" <<'EOF'
#include <atk/atk.h>
#include <epoxy/gl.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <graphene.h>
#include <pango/pango.h>

int
main(void)
{
    graphene_point_t point;
    GdkPixbuf *pixbuf = gdk_pixbuf_new(GDK_COLORSPACE_RGB, FALSE, 8, 1, 1);
    PangoFontDescription *font = pango_font_description_new();
    graphene_point_init(&point, 0.0f, 0.0f);
    pango_font_description_free(font);
    g_object_unref(pixbuf);
    return atk_get_root() == NULL && point.x != 0.0f;
}
EOF

cat > "$temporary/jpeg.c" <<'EOF'
#include <stdio.h>
#include <jpeglib.h>

int
main(void)
{
    struct jpeg_error_mgr error;
    struct jpeg_decompress_struct decoder;
    decoder.err = jpeg_std_error(&error);
    jpeg_create_decompress(&decoder);
    jpeg_destroy_decompress(&decoder);
    return 0;
}
EOF

cat > "$temporary/pango-fontconfig.c" <<'EOF'
#include <fontconfig/fontconfig.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <pango/pangofc-fontmap.h>
#include <pango/pangoft2.h>

int
main(void)
{
    FcPattern *pattern = FcPatternCreate();
    FT_Library library;
    FT_Error error = FT_Init_FreeType(&library);
    PangoFontMap *font_map = pango_ft2_font_map_new();
    GType font_map_type = pango_fc_font_map_get_type();
    if (error == 0)
        FT_Done_FreeType(library);
    FcPatternDestroy(pattern);
    g_object_unref(font_map);
    return error != 0 || font_map_type == 0;
}
EOF

cat > "$temporary/png.c" <<'EOF'
#include <png.h>

int
main(void)
{
    return png_access_version_number() == 0;
}
EOF

cat > "$temporary/tiff.c" <<'EOF'
#include <tiffio.h>

int
main(void)
{
    return TIFFGetVersion() == NULL;
}
EOF

# These package sets mirror the active native dependencies of every pinned
# module rebuilt to produce GTK's GIR closure. Run them once before that rebuild
# and again before GTK so archived .pc files cannot hide missing headers.
compile_probe glib "$temporary/glib.c" \
    glib-2.0 cairo libffi libpcre2-8 zlib
compile_probe harfbuzz "$temporary/harfbuzz.c" \
    harfbuzz freetype2 glib-2.0 gobject-2.0 cairo fontconfig icu-uc libpng zlib
compile_probe pango "$temporary/pango.c" \
    pango pangocairo pangofc pangoft2 harfbuzz fribidi cairo fontconfig \
    freetype2 glib-2.0 gio-2.0 gobject-2.0
compile_probe gdk-pixbuf "$temporary/gdk-pixbuf.c" \
    gdk-pixbuf-2.0 gio-2.0 gmodule-2.0 libpng libjpeg libtiff-4
compile_probe graphene "$temporary/graphene.c" graphene-1.0 gobject-2.0
compile_probe gtk "$temporary/gtk.c" \
    pango atk gdk-pixbuf-2.0 graphene-1.0 epoxy
compile_probe pango-fontconfig "$temporary/pango-fontconfig.c" \
    pangofc pangoft2 fontconfig freetype2
compile_probe jpeg "$temporary/jpeg.c" libjpeg
compile_probe png "$temporary/png.c" libpng
compile_probe tiff "$temporary/tiff.c" libtiff-4

# GTK's C dependency probes cannot establish its introspection build closure.
# Follow every include from the exact upstream GIR roots consumed by the GDK
# and GSK scanners, and require the corresponding compiled typelibs as well.
if [ "$gir_mode" != "--skip-gir" ]; then
    compile_probe gobject-introspection "$temporary/gobject-introspection.c" \
        gobject-introspection-1.0
    "$prefix/bin/python3" "$script_dir/verify-gtk4-refresh-gir-closure.py" "$prefix"
fi

echo "Verified GTK4 refresh developer build closure."
