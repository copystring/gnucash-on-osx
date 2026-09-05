#!/usr/bin/env bash

set -euo pipefail

if [ -z "${JHBUILD_PREFIX:-}" ]; then
    echo "This script requires that you be in a JHBuild shell for making dependencies" >&2
    exit 1
fi

GC_VERSION="${GC_VERSION:-5.15}"
SRC_URI="${SRC_URI:-https://github.com/gnucash/gnucash}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Paths:
ROOT_DIR="${ROOT_DIR:-/Users/runner/gnucash}"
INST_DIR="${INST_DIR:-$JHBUILD_PREFIX}"
PARK_DIR="${PARK_DIR:-$ROOT_DIR/parked}"
TAR_DIR="${TAR_DIR:-$ROOT_DIR/gc-tarball}"
ACTIVE_FILE="$PARK_DIR/.tarball-active"
SRC_DIR="${GNC_SOURCE_DIR:-$ROOT_DIR/src/gnucash-git}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/gnucash-git}"
DEPS_FILE="${DEPS_FILE:-$SCRIPT_DIR/dependencies.txt}"
GTEST_ROOT="${GTEST_ROOT:-$ROOT_DIR/src/googletest-1.17.0}"
TARBALL="${TARBALL:-$HOME/gnucash-$GC_VERSION-mac-dependencies.tar}"
COMP_TARBALL="$TARBALL.xz"

ARCHIVE_ROOTS=(bin include lib share)
if { [ -f "$DEPS_FILE" ] && grep -Eq '^etc(/|$)' "$DEPS_FILE"; } ||
   [ -L "$INST_DIR/etc" ] || [ -e "$PARK_DIR/etc" ]; then
    ARCHIVE_ROOTS=(bin etc include lib share)
fi

VERIFY_ONLY_MODE=
case "${1:-}" in
    verify-symlinks|verify-icon-themes|verify-bundle-inputs) VERIFY_ONLY_MODE="$1" ;;
esac
if [ -z "$VERIFY_ONLY_MODE" ]; then
    mkdir -p "$INST_DIR" "$PARK_DIR" "$TAR_DIR" "$BUILD_DIR"
    if [ ! -d "$SRC_DIR/.git" ]; then
        mkdir -p "$(dirname -- "$SRC_DIR")"
        git clone "$SRC_URI" "$SRC_DIR"
    fi
fi

clean_directory()
{
    local directory="$1"
    case "$directory" in
        "$ROOT_DIR"/*) ;;
        *)
            echo "Refusing to clean path outside $ROOT_DIR: $directory" >&2
            exit 1
            ;;
    esac
    rm -rf "$directory"
    mkdir -p "$directory"
}

verify_gtk4_dependencies()
{
    local cflags
    local cflag
    local include_path
    local -a include_flags=()

    if [ "${VERIFY_GTK4:-0}" != 1 ]; then
        return
    fi
    "$INST_DIR/bin/pkgconf" --atleast-version=4.14 gtk4
    "$INST_DIR/bin/pkgconf" --exists gtk4-macos gwengui-gtk4 aqbanking
    cflags="$("$INST_DIR/bin/pkgconf" --cflags-only-I gtk4 gtk4-macos gwengui-gtk4 aqbanking)" || return 1
    read -r -a include_flags <<< "$cflags"
    for cflag in "${include_flags[@]}"
    do
        case "$cflag" in
            -I"$INST_DIR"/*)
                include_path="${cflag#-I}"
                if [ ! -d "$include_path" ]; then
                    echo "Missing GTK4 pkg-config include directory: $include_path" >&2
                    return 1
                fi
                ;;
        esac
    done
}

verify_macho_closure()
{
    local binary
    local dependency
    local relative_dependency
    local missing_file="$TAR_DIR/.missing-macho-dependencies"

    if [ "${VERIFY_GTK4:-0}" != 1 ]; then
        return
    fi
    if ! command -v otool >/dev/null; then
        echo "otool is required to verify the GTK4 dependency archive" >&2
        return 1
    fi

    : > "$missing_file"
    while IFS= read -r -d '' binary
    do
        if ! file "$binary" | grep -q 'Mach-O'; then
            continue
        fi
        while IFS= read -r dependency
        do
            case "$dependency" in
                "$INST_DIR"/*)
                    relative_dependency="${dependency#"$INST_DIR"/}"
                    if [ ! -e "$TAR_DIR/$relative_dependency" ]; then
                        printf '%s\n' "$relative_dependency" >> "$missing_file"
                    fi
                    ;;
            esac
        done < <(otool -L "$binary" 2>/dev/null | awk 'NR > 1 { print $1 }')
    done < <(find "$TAR_DIR/bin" "$TAR_DIR/lib" -type f -print0)

    if [ -s "$missing_file" ]; then
        echo "GTK4 dependency archive has unresolved Mach-O dependencies:" >&2
        sort -u "$missing_file" >&2
        rm -f "$missing_file"
        return 1
    fi
    rm -f "$missing_file"
}

verify_gtk4_archive_data()
{
    local required_path
    local -a required_paths=(
        etc/chipcard
        etc/fonts
        share/aqbanking
        share/chipcard
        share/fontconfig
        share/glib-2.0
        share/gwenhywfar
        share/icons
        share/libofx
        share/locale
        share/mime
    )

    if [ "${VERIFY_GTK4:-0}" != 1 ]; then
        return
    fi
    for required_path in "${required_paths[@]}"
    do
        if [ ! -d "$TAR_DIR/$required_path" ]; then
            echo "GTK4 dependency archive is missing required bundle data: $required_path" >&2
            return 1
        fi
    done
}

verify_gtk4_archive_bundle_inputs()
{
    local query_tool="$TAR_DIR/bin/gdk-pixbuf-query-loaders"
    local pixbuf_version
    local loader_dir
    local loader
    local valid_loader=
    local -a loaders=()

    if [ "${VERIFY_GTK4:-0}" != 1 ]; then
        return
    fi
    if [ ! -f "$query_tool" ]; then
        echo "GTK4 dependency archive is missing required bundle tool: bin/gdk-pixbuf-query-loaders" >&2
        return 1
    fi
    if [ ! -x "$query_tool" ]; then
        echo "GTK4 dependency archive bundle tool is not executable: bin/gdk-pixbuf-query-loaders" >&2
        return 1
    fi
    if ! pixbuf_version="$(PKG_CONFIG_DIR= PKG_CONFIG_PATH= \
        PKG_CONFIG_LIBDIR="$TAR_DIR/lib/pkgconfig:$TAR_DIR/share/pkgconfig" \
        "$INST_DIR/bin/pkgconf" \
        --variable=gdk_pixbuf_binary_version gdk-pixbuf-2.0)"; then
        echo "Cannot determine the GDK Pixbuf loader version for the GTK4 bundle archive" >&2
        return 1
    fi
    case "$pixbuf_version" in
        ""|*[!A-Za-z0-9._-]*)
            echo "Invalid GDK Pixbuf loader version for the GTK4 bundle archive: $pixbuf_version" >&2
            return 1
            ;;
    esac

    loader_dir="$TAR_DIR/lib/gdk-pixbuf-2.0/$pixbuf_version/loaders"
    if [ ! -d "$loader_dir" ]; then
        echo "GTK4 dependency archive is missing GDK Pixbuf loader directory: lib/gdk-pixbuf-2.0/$pixbuf_version/loaders" >&2
        return 1
    fi
    shopt -s nullglob
    loaders=("$loader_dir"/*.so)
    shopt -u nullglob
    for loader in "${loaders[@]}"
    do
        if [ -f "$loader" ]; then
            valid_loader=1
            break
        fi
    done
    if [ -z "$valid_loader" ]; then
        echo "GTK4 dependency archive is missing GDK Pixbuf loader modules: lib/gdk-pixbuf-2.0/$pixbuf_version/loaders/*.so" >&2
        return 1
    fi
}

verify_gtk4_archive_symlinks()
{
    local python="${ARCHIVE_VERIFY_PYTHON:-$INST_DIR/bin/python3}"

    if [ "${VERIFY_GTK4:-0}" != 1 ]; then
        return
    fi
    if [ ! -x "$python" ]; then
        echo "Python 3 is required to verify GTK4 archive symlinks: $python" >&2
        return 1
    fi

    "$python" - "$TAR_DIR" <<'PY'
import errno
import os
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve(strict=True)
links = []
def raise_walk_error(error):
    raise error

try:
    for directory, directories, files in os.walk(
            root, followlinks=False, onerror=raise_walk_error):
        for name in directories + files:
            path = Path(directory, name)
            if path.is_symlink():
                links.append(path)
except OSError as error:
    print(f"Cannot inspect GTK4 dependency archive symlinks: {error}", file=sys.stderr)
    sys.exit(1)

errors = []
for path in links:
    relative_path = path.relative_to(root)
    target = os.readlink(path)
    if os.path.isabs(target):
        errors.append(("absolute target", relative_path, target))
        continue
    try:
        resolved_target = path.resolve(strict=True)
    except FileNotFoundError:
        errors.append(("missing target", relative_path, target))
        continue
    except RuntimeError:
        errors.append(("symlink loop", relative_path, target))
        continue
    except OSError as error:
        if error.errno == errno.ELOOP:
            errors.append(("symlink loop", relative_path, target))
        else:
            errors.append((f"cannot resolve target: {error}", relative_path, target))
        continue

    try:
        resolved_target.relative_to(root)
    except ValueError:
        errors.append(("target escapes archive", relative_path, target))

if errors:
    print("GTK4 dependency archive has invalid symlinks:", file=sys.stderr)
    for error, path, target in errors:
        print(f"{error}: {path} -> {target}", file=sys.stderr)
    sys.exit(1)

print(f"Verified {len(links)} GTK4 dependency archive symlinks")
PY
}

verify_gtk4_archive_icon_themes()
{
    local python="${ARCHIVE_VERIFY_PYTHON:-$INST_DIR/bin/python3}"
    local bundle_file="${BUNDLE_FILE:-$SCRIPT_DIR/gnucash-bundler/gnucash-unstable.bundle}"

    if [ "${VERIFY_GTK4:-0}" != 1 ]; then
        return
    fi
    if [ ! -x "$python" ]; then
        echo "Python 3 is required to verify GTK4 archive icon themes: $python" >&2
        return 1
    fi
    if [ ! -f "$bundle_file" ]; then
        echo "GTK4 bundle definition is missing: $bundle_file" >&2
        return 1
    fi

    "$python" - "$TAR_DIR" "$bundle_file" <<'PY'
import configparser
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

root = Path(sys.argv[1]).resolve(strict=True)
bundle_file = Path(sys.argv[2]).resolve(strict=True)

try:
    bundle = ET.parse(bundle_file)
except (ET.ParseError, OSError) as error:
    print(f"Cannot read GTK4 bundle icon themes: {error}", file=sys.stderr)
    sys.exit(1)

requested = []
for element in bundle.getroot().iter("icon-theme"):
    if element.text and element.text.strip():
        requested.append(element.text.strip())
if not requested:
    print(f"GTK4 bundle has no icon themes: {bundle_file}", file=sys.stderr)
    sys.exit(1)

pending = [(theme, "bundle definition") for theme in requested]
checked = set()
errors = []
while pending:
    theme, inherited_by = pending.pop(0)
    if theme in checked:
        continue
    checked.add(theme)
    if theme in (".", "..") or Path(theme).name != theme or "/" in theme or "\\" in theme:
        errors.append(f"invalid icon theme name inherited by {inherited_by}: {theme}")
        continue

    index_file = root / "share" / "icons" / theme / "index.theme"
    if not index_file.is_file():
        errors.append(f"missing icon theme index inherited by {inherited_by}: share/icons/{theme}/index.theme")
        continue

    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    try:
        with index_file.open(encoding="utf-8") as stream:
            parser.read_file(stream)
        if not parser.has_section("Icon Theme"):
            raise configparser.Error("missing [Icon Theme] section")
        for required_key in ("Name", "Directories"):
            if not parser.get("Icon Theme", required_key, fallback="").strip():
                raise configparser.Error(f"missing required {required_key} entry in [Icon Theme]")
        inherits = parser.get("Icon Theme", "Inherits", fallback="")
    except (configparser.Error, OSError, UnicodeError) as error:
        errors.append(f"cannot read share/icons/{theme}/index.theme: {error}")
        continue
    for inherited in (name.strip() for name in inherits.split(",")):
        if inherited:
            pending.append((inherited, theme))

if errors:
    print("GTK4 dependency archive has an incomplete icon-theme closure:", file=sys.stderr)
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(1)

print(f"Verified {len(checked)} GTK4 archive icon themes: {', '.join(sorted(checked))}")
PY
}

reset_from_tarball()
{
    local entry

    if [ ! -e "$ACTIVE_FILE" ] && [ ! -L "$INST_DIR/bin" ]; then
        return
    fi
    for entry in "${ARCHIVE_ROOTS[@]}"
    do
        if [ -L "$INST_DIR/$entry" ]; then
            rm "$INST_DIR/$entry"
        elif [ -e "$INST_DIR/$entry" ] && [ -e "$PARK_DIR/$entry" ]; then
            echo "Cannot restore $entry: both installed and parked copies exist" >&2
            return 1
        fi
        if [ ! -e "$INST_DIR/$entry" ] && [ -e "$PARK_DIR/$entry" ]; then
            mv "$PARK_DIR/$entry" "$INST_DIR"
        fi
    done
    rm -f "$ACTIVE_FILE"
}

enable_tarball()
{
    local entry

    for entry in "${ARCHIVE_ROOTS[@]}"
    do
        if [ ! -d "$INST_DIR/$entry" ]; then
            echo "Missing installed dependency directory: $INST_DIR/$entry" >&2
            return 1
        fi
        if [ ! -d "$TAR_DIR/$entry" ]; then
            echo "Missing archived dependency directory: $TAR_DIR/$entry" >&2
            return 1
        fi
    done
    clean_directory "$PARK_DIR"
    : > "$ACTIVE_FILE"
    pushd "$INST_DIR"
    for entry in "${ARCHIVE_ROOTS[@]}"
    do
        mv "$entry" "$PARK_DIR"
        ln -s "$TAR_DIR/$entry" .
    done
    popd
}

create_tarball()
{
    local line
    local -a entries=()
    local -a line_entries=()

    verify_gtk4_dependencies
    while IFS= read -r line
    do
        [ -n "$line" ] || continue
        case "$line" in
            '#'* ) continue ;;
        esac
        read -r -a line_entries <<< "$line"
        entries+=("${line_entries[@]}")
    done < "$DEPS_FILE"
    if [ "${#entries[@]}" -eq 0 ]; then
        echo "Dependency manifest is empty: $DEPS_FILE" >&2
        exit 1
    fi

    pushd "$INST_DIR"
    rm -f "$TARBALL" "$COMP_TARBALL"
    tar -cf "$TARBALL" "${entries[@]}"
    xz -f "$TARBALL"
    popd
}

test_tarball()
{
    clean_directory "$TAR_DIR"
    pushd "$TAR_DIR"
    tar -xf "$COMP_TARBALL"
    popd
    verify_gtk4_archive_data
    verify_gtk4_archive_bundle_inputs
    verify_gtk4_archive_icon_themes
    verify_gtk4_archive_symlinks
    verify_macho_closure
    enable_tarball
    verify_gtk4_dependencies
    clean_directory "$BUILD_DIR"
    pushd "$BUILD_DIR"
    cmake -G Ninja \
        -DPython3_ROOT_DIR="$INST_DIR" \
        -DPKG_CONFIG_EXECUTABLE="$INST_DIR/bin/pkgconf" \
        -DCMAKE_PREFIX_PATH="$INST_DIR" \
        -DCMAKE_INSTALL_PREFIX="$INST_DIR" \
        -DGTEST_ROOT="$GTEST_ROOT" \
        -DWITH_PYTHON=YES \
        "$SRC_DIR"
    ninja
    CTEST_OUTPUT_ON_FAILURE=On ninja check
    popd
    reset_from_tarball
}

case "$VERIFY_ONLY_MODE" in
    verify-symlinks)
        verify_gtk4_archive_symlinks
        exit 0
        ;;
    verify-icon-themes)
        verify_gtk4_archive_icon_themes
        exit 0
        ;;
    verify-bundle-inputs)
        verify_gtk4_archive_bundle_inputs
        exit 0
        ;;
esac

trap reset_from_tarball EXIT

if [ -e "$ACTIVE_FILE" ] || [ -L "$INST_DIR/bin" ]; then
    reset_from_tarball
fi

case "${1:-}" in
    use_tarball)
        enable_tarball
        trap - EXIT
        ;;
    restore)
        reset_from_tarball
        ;;
    build)
        test_tarball
        ;;
    "")
        create_tarball
        test_tarball
        ;;
    *)
        echo "Usage: $0 [use_tarball|restore|build|verify-symlinks|verify-icon-themes|verify-bundle-inputs]" >&2
        exit 2
        ;;
esac

exit 0
