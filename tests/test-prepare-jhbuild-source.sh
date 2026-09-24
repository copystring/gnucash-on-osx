#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/gnucash-jhbuild-source.XXXXXX")"
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/bin"

cat > "$fixture/bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if test "$1" = clone; then
    count=$(cat "$MOCK_STATE/clone-count" 2>/dev/null || echo 0)
    count=$((count + 1))
    echo "$count" > "$MOCK_STATE/clone-count"
    if test "$count" -le "${MOCK_CLONE_FAILURES:-0}"; then
        exit 1
    fi
    target=${@: -1}
    mkdir -p "$target/.git" "$target/jhbuild"
    if test "${MOCK_MISSING_PACKAGE:-0}" != 1; then
        touch "$target/jhbuild/__init__.py"
    fi
elif test "$1" = -C && test "$3" = fetch; then
    count=$(cat "$MOCK_STATE/fetch-count" 2>/dev/null || echo 0)
    count=$((count + 1))
    echo "$count" > "$MOCK_STATE/fetch-count"
    test "$count" -gt "${MOCK_FETCH_FAILURES:-0}"
elif test "$1" = -C && test "$3" = rev-parse; then
    echo "$MOCK_REVISION"
else
    echo "Unexpected git invocation: $*" >&2
    exit 1
fi
EOF
cat > "$fixture/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fixture/bin/git" "$fixture/bin/sleep"

export PATH="$fixture/bin:$PATH"
export MOCK_STATE="$fixture/state"
export MOCK_REVISION=16e05af9b58b9e7433ce7417ecd8915beba59133
mkdir -p "$MOCK_STATE"
MOCK_CLONE_FAILURES=1 MOCK_FETCH_FAILURES=1 \
    bash "$script_dir/../prepare-jhbuild-source.sh" \
    "$fixture/source/jhbuild" "$MOCK_REVISION"
test "$(cat "$MOCK_STATE/clone-count")" = 2
test "$(cat "$MOCK_STATE/fetch-count")" = 2
test -f "$fixture/source/jhbuild/jhbuild/__init__.py"

mkdir -p "$fixture/failed-state"
if MOCK_STATE="$fixture/failed-state" MOCK_CLONE_FAILURES=3 \
    bash "$script_dir/../prepare-jhbuild-source.sh" \
    "$fixture/failed/jhbuild" "$MOCK_REVISION" \
    >"$fixture/failed.log" 2>&1; then
    echo 'A failed JHBuild clone unexpectedly succeeded.' >&2
    exit 1
fi
test "$(cat "$fixture/failed-state/clone-count")" = 3
grep -q 'JHBuild source clone failed after 3 attempts' "$fixture/failed.log"

mkdir -p "$fixture/missing-state"
if MOCK_STATE="$fixture/missing-state" MOCK_MISSING_PACKAGE=1 \
    bash "$script_dir/../prepare-jhbuild-source.sh" \
    "$fixture/missing/jhbuild" "$MOCK_REVISION" \
    >"$fixture/missing.log" 2>&1; then
    echo 'A missing JHBuild package unexpectedly succeeded.' >&2
    exit 1
fi
grep -q 'JHBuild source is missing its Python package' "$fixture/missing.log"

echo 'JHBuild source bootstrap fixtures passed.'
