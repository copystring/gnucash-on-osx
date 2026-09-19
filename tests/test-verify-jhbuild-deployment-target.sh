#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
verify="$script_dir/../verify-jhbuild-deployment-target.sh"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/gnucash-jhbuild-target.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

cat > "$fixture/jhbuild-real" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
test "$1" = run
shift
# Pinned JHBuild 16e05af uses os.execlp(args[0], *args).
exec "$@"
EOF

cat > "$fixture/jhbuild" <<EOF
#!/usr/bin/env bash
# Pinned GTK-OSX 0889e03 emits this unquoted forwarding contract.
exec "$fixture/jhbuild-real" \$@
EOF

cat > "$fixture/clang" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=
while test "$#" -gt 0; do
    if test "$1" = -o; then
        output="$2"
        shift 2
    else
        shift
    fi
done
test -n "$output"
: > "$output"
EOF

cat > "$fixture/otool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<OUTPUT
Load command 1
      cmd LC_BUILD_VERSION
 platform 1
    minos ${OTOOL_FIXTURE_MIN_OS:-26.5}
OUTPUT
EOF

chmod +x "$fixture/jhbuild" "$fixture/jhbuild-real" \
    "$fixture/clang" "$fixture/otool"
probe_source="$fixture/probe-source.c"
probe_library="$fixture/probe-library.dylib"
printf 'int deployment_target_probe(void) { return 0; }\n' > "$probe_source"

export CC="$fixture/clang"
export OTOOL="$fixture/otool"
export MACOSX_DEPLOYMENT_TARGET=26.5
export CFLAGS='-O2 -mmacosx-version-min=26.5'
export LDFLAGS='-mmacosx-version-min=26.5'

old_inline='if [ "$1" = 26.5 ]; then printf "%s\n" "$1"; fi'
if "$fixture/jhbuild" run sh -c "$old_inline" sh 26.5 \
    >"$fixture/old-inline.log" 2>&1; then
    echo 'Expected pinned GTK-OSX wrapper to break the inline sh -c argument' >&2
    exit 1
fi
grep -Fiq 'syntax error' "$fixture/old-inline.log"

"$fixture/jhbuild" run bash "$verify" 26.5 "$probe_source" "$probe_library"
test -f "$probe_library"

assert_fails_with()
{
    expected="$1"
    shift
    log="$fixture/failure.log"
    if "$@" >"$log" 2>&1; then
        echo "Expected command to fail: $*" >&2
        exit 1
    fi
    grep -Fq "$expected" "$log"
}

MACOSX_DEPLOYMENT_TARGET=26.6 assert_fails_with \
    'JHBuild deployment target mismatch' \
    "$fixture/jhbuild" run bash "$verify" 26.5 "$probe_source" "$probe_library"

CFLAGS='-O2' assert_fails_with \
    'JHBuild CFLAGS lacks -mmacosx-version-min=26.5' \
    "$fixture/jhbuild" run bash "$verify" 26.5 "$probe_source" "$probe_library"

OTOOL_FIXTURE_MIN_OS=26.6 assert_fails_with \
    'Refresh probe deployment target mismatch' \
    "$fixture/jhbuild" run bash "$verify" 26.5 "$probe_source" "$probe_library"

echo 'JHBuild deployment-target contract fixtures passed.'
