#!/usr/bin/env bash

set -euo pipefail

if test "$#" -ne 3; then
    echo "Usage: $0 EXPECTED_TARGET PROBE_SOURCE PROBE_LIBRARY" >&2
    exit 2
fi

expected_target="$1"
probe_source="$2"
probe_library="$3"

if test "${MACOSX_DEPLOYMENT_TARGET:-}" != "$expected_target"; then
    printf 'JHBuild deployment target mismatch: expected %s, got %s; CFLAGS=%s\n' \
        "$expected_target" "${MACOSX_DEPLOYMENT_TARGET:-<unset>}" \
        "${CFLAGS:-<unset>}" >&2
    exit 1
fi

case " ${CFLAGS:-} " in
  *" -mmacosx-version-min=$expected_target "*) ;;
  *)
    printf 'JHBuild CFLAGS lacks -mmacosx-version-min=%s: %s\n' \
        "$expected_target" "${CFLAGS:-<unset>}" >&2
    exit 1
    ;;
esac

compiler="${CC:-clang}"
"$compiler" ${CFLAGS:-} -dynamiclib "$probe_source" -o "$probe_library" \
    ${LDFLAGS:-}

probe_min_os="$("${OTOOL:-otool}" -l "$probe_library" | awk '
  $1 == "cmd" && ($2 == "LC_BUILD_VERSION" || $2 == "LC_VERSION_MIN_MACOSX") { active = 1; next }
  active && ($1 == "minos" || $1 == "version") { print $2; exit }
  $1 == "cmd" { active = 0 }
')"
if test "$probe_min_os" != "$expected_target"; then
    printf 'Refresh probe deployment target mismatch: expected %s, got %s\n' \
        "$expected_target" "${probe_min_os:-<unset>}" >&2
    exit 1
fi
