#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_base="$(cd -- "${TMPDIR:-/tmp}" && pwd -P)"
test_root="$(mktemp -d "$tmp_base/gnucash-icon-themes.XXXXXX")"

cleanup()
{
    case "$test_root" in
        "$tmp_base"/gnucash-icon-themes.*) rm -rf -- "$test_root" ;;
        *)
            echo "Refusing to clean unexpected icon-theme test path: $test_root" >&2
            return 1
            ;;
    esac
}
trap cleanup EXIT

python="${ARCHIVE_VERIFY_PYTHON:-}"
if [ -z "$python" ]; then
    python="$(command -v python3 || command -v python)"
fi

active_prefix="$test_root/active-prefix"
active_park="$test_root/active-park"
linked_bin="$test_root/linked-bin"
mkdir -p "$active_prefix" "$active_park/bin" "$linked_bin"
touch "$active_park/.tarball-active"
echo 'installed sentinel' > "$linked_bin/sentinel"
echo 'parked sentinel' > "$active_park/bin/sentinel"
ln -s "$linked_bin" "$active_prefix/bin"
if [ ! -L "$active_prefix/bin" ]; then
    echo 'Could not create active-prefix symlink fixture.' >&2
    exit 1
fi

bundle_file="$test_root/test.bundle"
cat > "$bundle_file" <<'EOF'
<?xml version="1.0"?>
<app-bundle>
  <icon-theme icons="auto">Adwaita</icon-theme>
</app-bundle>
EOF

write_theme()
{
    local root="$1"
    local theme="$2"
    local inherits="${3:-}"
    local theme_dir="$root/share/icons/$theme"

    mkdir -p "$theme_dir"
    {
        echo '[Icon Theme]'
        echo "Name=$theme"
        if [ -n "$inherits" ]; then
            echo "Inherits=$inherits"
        fi
        echo 'Directories=scalable/actions'
    } > "$theme_dir/index.theme"
}

run_verifier()
{
    local archive_root="$1"
    VERIFY_GTK4=1 \
    JHBUILD_PREFIX="$active_prefix" \
    PARK_DIR="$active_park" \
    TAR_DIR="$archive_root" \
    BUNDLE_FILE="$bundle_file" \
    ARCHIVE_VERIFY_PYTHON="$python" \
        bash "$SCRIPT_DIR/depstarball.sh" verify-icon-themes
}

run_symlink_verifier()
{
    local archive_root="$1"
    VERIFY_GTK4=1 \
    JHBUILD_PREFIX="$active_prefix" \
    PARK_DIR="$active_park" \
    TAR_DIR="$archive_root" \
    ARCHIVE_VERIFY_PYTHON="$python" \
        bash "$SCRIPT_DIR/depstarball.sh" verify-symlinks
}

assert_active_prefix_unchanged()
{
    [ -L "$active_prefix/bin" ]
    [ "$(readlink "$active_prefix/bin")" = "$linked_bin" ]
    [ -f "$active_park/.tarball-active" ]
    grep -qx 'installed sentinel' "$linked_bin/sentinel"
    grep -qx 'parked sentinel' "$active_park/bin/sentinel"
}

valid="$test_root/valid"
write_theme "$valid" Adwaita 'AdwaitaLegacy,hicolor'
write_theme "$valid" AdwaitaLegacy hicolor
write_theme "$valid" hicolor
run_verifier "$valid"
assert_active_prefix_unchanged
run_symlink_verifier "$valid"
assert_active_prefix_unchanged

missing_direct="$test_root/missing-direct"
write_theme "$missing_direct" Adwaita 'AdwaitaLegacy,hicolor'
write_theme "$missing_direct" hicolor
if run_verifier "$missing_direct" > "$test_root/missing-direct.log" 2>&1; then
    echo 'Missing directly inherited icon theme unexpectedly passed.' >&2
    exit 1
fi
grep -q 'share/icons/AdwaitaLegacy/index.theme' "$test_root/missing-direct.log"

missing_transitive="$test_root/missing-transitive"
write_theme "$missing_transitive" Adwaita AdwaitaLegacy
write_theme "$missing_transitive" AdwaitaLegacy hicolor
if run_verifier "$missing_transitive" > "$test_root/missing-transitive.log" 2>&1; then
    echo 'Missing transitively inherited icon theme unexpectedly passed.' >&2
    exit 1
fi
grep -q 'share/icons/hicolor/index.theme' "$test_root/missing-transitive.log"
assert_active_prefix_unchanged

malformed="$test_root/malformed"
mkdir -p "$malformed/share/icons/Adwaita"
: > "$malformed/share/icons/Adwaita/index.theme"
if run_verifier "$malformed" > "$test_root/malformed.log" 2>&1; then
    echo 'Structurally invalid icon theme unexpectedly passed.' >&2
    exit 1
fi
grep -q 'missing \[Icon Theme\] section' "$test_root/malformed.log"
assert_active_prefix_unchanged

echo 'GTK4 archive icon-theme closure fixtures passed.'
