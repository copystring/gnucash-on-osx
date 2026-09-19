#!/usr/bin/env python3

import argparse
import hashlib
from pathlib import Path
import re
import sys


PLACEHOLDER = re.compile(r"@[A-Z][A-Z0-9_]*@")


def materialize(template_bytes, expected_sha256, python, datadir):
    actual_sha256 = hashlib.sha256(template_bytes).hexdigest()
    if actual_sha256 != expected_sha256:
        raise ValueError(
            f"gdbus-codegen template SHA-256 mismatch: expected {expected_sha256}, "
            f"got {actual_sha256}")

    template = template_bytes.decode("utf-8")
    replacements = {"@PYTHON@": python, "@DATADIR@": datadir}
    for placeholder, value in replacements.items():
        if template.count(placeholder) != 1:
            raise ValueError(
                f"gdbus-codegen template must contain exactly one {placeholder}")
        template = template.replace(placeholder, value)

    remaining = sorted(set(PLACEHOLDER.findall(template)))
    if remaining:
        raise ValueError(
            "gdbus-codegen template contains unsubstituted placeholders: " +
            ", ".join(remaining))
    return template.encode("utf-8")


def main():
    parser = argparse.ArgumentParser(
        description="Materialize the pinned upstream GLib gdbus-codegen template")
    parser.add_argument("template", type=Path)
    parser.add_argument("expected_sha256")
    parser.add_argument("python")
    parser.add_argument("datadir")
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    try:
        output = materialize(
            arguments.template.read_bytes(), arguments.expected_sha256,
            arguments.python, arguments.datadir)
        arguments.output.write_bytes(output)
        arguments.output.chmod(0o755)
    except (OSError, UnicodeDecodeError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
