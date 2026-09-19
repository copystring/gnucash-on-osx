#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 PREFIX EXPECTED_LIBFFI_VERSION" >&2
    exit 2
fi

prefix="$1"
expected_libffi_version="$2"
pkgconf="$prefix/bin/pkgconf"

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

cat > "$temporary/gobject-introspection.c" <<'EOF'
#include <cairo.h>
#include <ffi.h>
#include <glib.h>

int
main(void)
{
    ffi_cif cif;
    ffi_type *arguments[] = { &ffi_type_sint };
    cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1);
    GString *text = g_string_new("gtk4-refresh");
    ffi_status status = ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 1,
                                     &ffi_type_void, arguments);
    g_string_free(text, TRUE);
    cairo_surface_destroy(surface);
    return status == FFI_OK ? 0 : 1;
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

# These package sets mirror the pinned GTK-OSX module dependencies used by
# gobject-introspection and GTK. The image-library probes
# cover GTK's active built-in JPEG, PNG, and TIFF loader dependencies; libepoxy
# is rebuilt and included in the GTK probe before GTK itself is rebuilt.
compile_probe gobject-introspection "$temporary/gobject-introspection.c" \
    glib-2.0 cairo libffi
compile_probe gtk "$temporary/gtk.c" \
    pango atk gdk-pixbuf-2.0 graphene-1.0 epoxy
compile_probe jpeg "$temporary/jpeg.c" libjpeg
compile_probe png "$temporary/png.c" libpng
compile_probe tiff "$temporary/tiff.c" libtiff-4

echo "Verified GTK4 refresh developer build closure."
