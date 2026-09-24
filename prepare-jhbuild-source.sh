#!/usr/bin/env bash
set -euo pipefail

source_dir=$1
revision=$2
mirror=https://github.com/GNOME/jhbuild.git

if test -e "$source_dir"; then
    echo "JHBuild source destination already exists: $source_dir" >&2
    exit 1
fi

mkdir -p "$(dirname "$source_dir")"
for attempt in 1 2 3; do
    candidate="${source_dir}.attempt-${attempt}"
    if git clone --depth=1 --branch master "$mirror" "$candidate"; then
        mv "$candidate" "$source_dir"
        break
    fi
    if test "$attempt" -eq 3; then
        echo 'JHBuild source clone failed after 3 attempts.' >&2
        exit 1
    fi
    echo "JHBuild source clone failed (attempt $attempt/3); retrying." >&2
    sleep $((attempt * 5))
done

for attempt in 1 2 3; do
    if git -C "$source_dir" fetch --depth=1 origin "$revision"; then
        break
    fi
    if test "$attempt" -eq 3; then
        echo 'Pinned JHBuild revision download failed after 3 attempts.' >&2
        exit 1
    fi
    echo "Pinned JHBuild revision download failed (attempt $attempt/3); retrying." >&2
    sleep $((attempt * 5))
done

test "$(git -C "$source_dir" rev-parse FETCH_HEAD)" = "$revision"
test -f "$source_dir/jhbuild/__init__.py" || {
    echo 'JHBuild source is missing its Python package.' >&2
    exit 1
}
