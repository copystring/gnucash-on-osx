#!/usr/bin/env bash

set -euo pipefail

if test "$#" -ne 1; then
    echo "Usage: $0 EXPECTED_PREFIX" >&2
    exit 2
fi

expected_prefix="$1"
if test "${JHBUILD_PREFIX:-}" != "$expected_prefix"; then
    printf 'Expected JHBUILD_PREFIX=%s, got %s\n' \
        "$expected_prefix" "${JHBUILD_PREFIX:-<unset>}" >&2
    exit 1
fi

if test "${PREFIX:-}" != "$expected_prefix"; then
    printf 'Expected PREFIX=%s, got %s\n' \
        "$expected_prefix" "${PREFIX:-<unset>}" >&2
    exit 1
fi
