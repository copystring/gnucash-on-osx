#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_base="$(cd -- "${TMPDIR:-/tmp}" && pwd -P)"
test_root="$(mktemp -d "$tmp_base/gnucash-bundle-inputs.XXXXXX")"

cleanup()
{
    case "$test_root" in
        "$tmp_base"/gnucash-bundle-inputs.*) rm -rf -- "$test_root" ;;
        *)
            echo "Refusing to clean unexpected bundle-input test path: $test_root" >&2
            return 1
            ;;
    esac
}
trap cleanup EXIT

if ! grep -qx 'bin/gdk-pixbuf-query-loaders' \
    "$SCRIPT_DIR/dependencies-gtk4.txt"; then
    echo 'GTK4 dependency manifest is missing bin/gdk-pixbuf-query-loaders.' >&2
    exit 1
fi

active_prefix="$test_root/active-prefix"
mkdir -p "$active_prefix/bin"
cat > "$active_prefix/bin/pkgconf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$#" -eq 2 ] &&
   [ "$1" = "--variable=gdk_pixbuf_binary_version" ] &&
   [ "$2" = "gdk-pixbuf-2.0" ]; then
    [ -z "${PKG_CONFIG_PATH:-}" ]
    pc_dir="${PKG_CONFIG_LIBDIR%%:*}"
    pc_file="$pc_dir/gdk-pixbuf-2.0.pc"
    [ -f "$pc_file" ]
    version="$(sed -n 's/^gdk_pixbuf_binary_version=//p' "$pc_file")"
    [ -n "$version" ]
    echo "$version"
    exit 0
fi
exit 2
EOF
chmod 755 "$active_prefix/bin/pkgconf"

host_pc_dir="$test_root/host-pkgconfig"
mkdir -p "$host_pc_dir"
echo 'gdk_pixbuf_binary_version=9.9.9' > "$host_pc_dir/gdk-pixbuf-2.0.pc"
export PKG_CONFIG_PATH="$host_pc_dir"

write_valid_archive()
{
    local archive_root="$1"
    local loader_dir="$archive_root/lib/gdk-pixbuf-2.0/2.10.0/loaders"

    mkdir -p "$archive_root/bin" "$archive_root/lib/pkgconfig" "$loader_dir"
    cat > "$archive_root/bin/gdk-pixbuf-query-loaders" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod 755 "$archive_root/bin/gdk-pixbuf-query-loaders"
    cat > "$archive_root/lib/pkgconfig/gdk-pixbuf-2.0.pc" <<'EOF'
gdk_pixbuf_binary_version=2.10.0
Name: GdkPixbuf
Description: GTK4 archive contract fixture
Version: 2.42.0
EOF
    : > "$loader_dir/libpixbufloader-svg.so"
}

run_verifier()
{
    local archive_root="$1"

    VERIFY_GTK4=1 \
    JHBUILD_PREFIX="$active_prefix" \
    TAR_DIR="$archive_root" \
        bash "$SCRIPT_DIR/depstarball.sh" verify-bundle-inputs
}

valid="$test_root/valid"
write_valid_archive "$valid"
run_verifier "$valid"

missing_tool="$test_root/missing-tool"
write_valid_archive "$missing_tool"
rm "$missing_tool/bin/gdk-pixbuf-query-loaders"
if run_verifier "$missing_tool" > "$test_root/missing-tool.log" 2>&1; then
    echo 'Missing GDK Pixbuf query tool unexpectedly passed.' >&2
    exit 1
fi
grep -q 'missing required bundle tool: bin/gdk-pixbuf-query-loaders' \
    "$test_root/missing-tool.log"

non_executable_tool="$test_root/non-executable-tool"
write_valid_archive "$non_executable_tool"
echo 'not executable' > "$non_executable_tool/bin/gdk-pixbuf-query-loaders"
chmod 644 "$non_executable_tool/bin/gdk-pixbuf-query-loaders"
if run_verifier "$non_executable_tool" > "$test_root/non-executable-tool.log" 2>&1; then
    echo 'Non-executable GDK Pixbuf query tool unexpectedly passed.' >&2
    exit 1
fi
grep -q 'bundle tool is not executable: bin/gdk-pixbuf-query-loaders' \
    "$test_root/non-executable-tool.log"

missing_loaders="$test_root/missing-loaders"
write_valid_archive "$missing_loaders"
rm "$missing_loaders/lib/gdk-pixbuf-2.0/2.10.0/loaders/libpixbufloader-svg.so"
if run_verifier "$missing_loaders" > "$test_root/missing-loaders.log" 2>&1; then
    echo 'Missing GDK Pixbuf loader modules unexpectedly passed.' >&2
    exit 1
fi
grep -q 'missing GDK Pixbuf loader modules: lib/gdk-pixbuf-2.0/2.10.0/loaders/\*.so' \
    "$test_root/missing-loaders.log"

missing_loader_dir="$test_root/missing-loader-dir"
write_valid_archive "$missing_loader_dir"
rm -r "$missing_loader_dir/lib/gdk-pixbuf-2.0/2.10.0/loaders"
if run_verifier "$missing_loader_dir" > "$test_root/missing-loader-dir.log" 2>&1; then
    echo 'Missing GDK Pixbuf loader directory unexpectedly passed.' >&2
    exit 1
fi
grep -q 'missing GDK Pixbuf loader directory: lib/gdk-pixbuf-2.0/2.10.0/loaders' \
    "$test_root/missing-loader-dir.log"

missing_pc="$test_root/missing-pc"
write_valid_archive "$missing_pc"
rm "$missing_pc/lib/pkgconfig/gdk-pixbuf-2.0.pc"
if run_verifier "$missing_pc" > "$test_root/missing-pc.log" 2>&1; then
    echo 'Missing archived GDK Pixbuf pkg-config data unexpectedly passed.' >&2
    exit 1
fi
grep -q 'Cannot determine the GDK Pixbuf loader version' "$test_root/missing-pc.log"

mismatched_pc="$test_root/mismatched-pc"
write_valid_archive "$mismatched_pc"
cat > "$mismatched_pc/lib/pkgconfig/gdk-pixbuf-2.0.pc" <<'EOF'
gdk_pixbuf_binary_version=9.9.9
Name: GdkPixbuf
Description: Mismatched GTK4 archive contract fixture
Version: 2.42.0
EOF
if run_verifier "$mismatched_pc" > "$test_root/mismatched-pc.log" 2>&1; then
    echo 'Mismatched archived GDK Pixbuf pkg-config data unexpectedly passed.' >&2
    exit 1
fi
grep -q 'missing GDK Pixbuf loader directory: lib/gdk-pixbuf-2.0/9.9.9/loaders' \
    "$test_root/mismatched-pc.log"

directory_loader="$test_root/directory-loader"
write_valid_archive "$directory_loader"
rm "$directory_loader/lib/gdk-pixbuf-2.0/2.10.0/loaders/libpixbufloader-svg.so"
mkdir "$directory_loader/lib/gdk-pixbuf-2.0/2.10.0/loaders/fake.so"
if run_verifier "$directory_loader" > "$test_root/directory-loader.log" 2>&1; then
    echo 'Directory with an .so suffix unexpectedly passed as a loader module.' >&2
    exit 1
fi
grep -q 'missing GDK Pixbuf loader modules: lib/gdk-pixbuf-2.0/2.10.0/loaders/\*.so' \
    "$test_root/directory-loader.log"

echo 'GTK4 archive bundle-input fixtures passed.'
