#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
verify="$script_dir/../verify-jhbuild-prefix.sh"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/gnucash-jhbuild-prefix.XXXXXX")"
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
chmod +x "$fixture/jhbuild" "$fixture/jhbuild-real"

expected_prefix=/Users/runner/gnucash/inst
export JHBUILD_PREFIX="$expected_prefix"

old_inline='expected_prefix=$1
if [ "${JHBUILD_PREFIX:-}" != "$expected_prefix" ]; then
  exit 1
fi'
# The broken inline form silently accepts a false prefix because only its first
# assignment survives as the bash -c command string after unquoted forwarding.
JHBUILD_PREFIX=/unexpected/prefix \
    "$fixture/jhbuild" run bash -c "$old_inline" bash "$expected_prefix"

"$fixture/jhbuild" run bash "$verify" "$expected_prefix"

log="$fixture/wrong-prefix.log"
if JHBUILD_PREFIX=/unexpected/prefix \
    "$fixture/jhbuild" run bash "$verify" "$expected_prefix" \
    >"$log" 2>&1; then
    echo 'Expected mismatched JHBUILD_PREFIX to fail' >&2
    exit 1
fi
grep -Fq "Expected JHBUILD_PREFIX=$expected_prefix, got /unexpected/prefix" "$log"

echo 'JHBuild prefix contract fixtures passed.'
