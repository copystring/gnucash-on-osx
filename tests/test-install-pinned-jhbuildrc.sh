#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/gnucash-jhbuildrc.XXXXXX")"
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/bin"
target="$fixture/jhbuildrc"

cat > "$fixture/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target=
url=
while test "$#" -gt 0; do
    case "$1" in
        --output) target=$2; shift 2 ;;
        https://*) url=$1; shift ;;
        *) shift ;;
    esac
done
test "$url" = "https://raw.githubusercontent.com/GNOME/gtk-osx/$MOCK_REF/jhbuildrc-gtk-osx"
if test "$MOCK_CURL_MODE" = fail; then
    exit 22
fi
cp "$MOCK_SOURCE" "$target"
EOF
chmod +x "$fixture/bin/curl"

export PATH="$fixture/bin:$PATH"
export MOCK_REF=0889e034206c1019e408cff7e9f426fccd5e034e
export PYTHON_BIN=${PYTHON_BIN:-python3}
echo 'import jhbuild' > "$fixture/valid"
export MOCK_SOURCE="$fixture/valid"
MOCK_CURL_MODE=valid bash "$script_dir/../install-pinned-jhbuildrc.sh" \
    "$MOCK_REF" "$target"
cmp "$fixture/valid" "$target"

printf '<html><style>font-size: 1.75rem</style></html>\n' > "$fixture/html"
export MOCK_SOURCE="$fixture/html"
if MOCK_CURL_MODE=html bash "$script_dir/../install-pinned-jhbuildrc.sh" \
    "$MOCK_REF" "$target" >"$fixture/html.log" 2>&1; then
    echo 'HTML was accepted as JHBuild configuration.' >&2
    exit 1
fi
grep -q 'not valid Python' "$fixture/html.log"
cmp "$fixture/valid" "$target"

if MOCK_CURL_MODE=fail bash "$script_dir/../install-pinned-jhbuildrc.sh" \
    "$MOCK_REF" "$target" >"$fixture/download.log" 2>&1; then
    echo 'Failed download was accepted as JHBuild configuration.' >&2
    exit 1
fi
cmp "$fixture/valid" "$target"

echo 'Pinned JHBuild configuration fixtures passed.'
