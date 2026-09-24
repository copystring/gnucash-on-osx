#!/usr/bin/env bash
set -euo pipefail

revision=$1
target=$2
python=${PYTHON_BIN:-python3}
candidate="$(mktemp "${TMPDIR:-/tmp}/gnucash-jhbuildrc.XXXXXX")"
trap 'rm -f -- "$candidate"' EXIT

curl --fail --location --show-error --retry 2 --retry-delay 5 \
    --connect-timeout 30 \
    "https://raw.githubusercontent.com/GNOME/gtk-osx/$revision/jhbuildrc-gtk-osx" \
    --output "$candidate"

"$python" - "$candidate" <<'PY'
import ast
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
try:
    tree = ast.parse(source)
except SyntaxError as error:
    raise SystemExit(f"Pinned JHBuild configuration is not valid Python: {error}")
if not any(
    isinstance(node, ast.Import)
    and any(alias.name == "jhbuild" for alias in node.names)
    for node in ast.walk(tree)
):
    raise SystemExit("Pinned JHBuild configuration is missing its JHBuild import.")
PY

install -m 600 "$candidate" "$target"
