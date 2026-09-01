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

mkdir -p "$INST_DIR" "$PARK_DIR" "$TAR_DIR" "$BUILD_DIR"
if [ ! -d "$SRC_DIR/.git" ]; then
    mkdir -p "$(dirname -- "$SRC_DIR")"
    git clone "$SRC_URI" "$SRC_DIR"
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
    if [ "${VERIFY_GTK4:-0}" != 1 ]; then
        return
    fi
    "$INST_DIR/bin/pkgconf" --atleast-version=4.14 gtk4
    "$INST_DIR/bin/pkgconf" --exists gtk4-macos gwengui-gtk4 aqbanking
}

reset_from_tarball()
{
    local entry

    if [ ! -e "$ACTIVE_FILE" ] && [ ! -L "$INST_DIR/bin" ]; then
        return
    fi
    for entry in bin include lib share
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

    for entry in bin include lib share
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
    for entry in bin include lib share
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
        echo "Usage: $0 [use_tarball|restore|build]" >&2
        exit 2
        ;;
esac

exit 0
