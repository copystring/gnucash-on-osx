#!/usr/bin/env python3

import argparse
from collections import deque
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


CORE_NAMESPACE = "http://www.gtk.org/introspection/core/1.0"
DEFAULT_ROOTS = (
    "cairo-1.0",
    "Gio-2.0",
    "GdkPixbuf-2.0",
    "Pango-1.0",
    "PangoCairo-1.0",
    "Graphene-1.0",
)


def gir_identity(path):
    try:
        repository = ET.parse(path).getroot()
    except ET.ParseError as error:
        raise ValueError(f"Cannot parse GIR {path.name}: {error}") from error
    namespace = repository.find(f"{{{CORE_NAMESPACE}}}namespace")
    if namespace is None:
        raise ValueError(f"GIR {path.name} has no introspection namespace")
    name = namespace.attrib.get("name")
    version = namespace.attrib.get("version")
    if not name or not version:
        raise ValueError(f"GIR {path.name} has an incomplete namespace identity")
    return repository, f"{name}-{version}"


def verify_closure(prefix, roots=DEFAULT_ROOTS):
    gir_directory = prefix / "share" / "gir-1.0"
    typelib_directory = prefix / "lib" / "girepository-1.0"
    if not gir_directory.is_dir():
        raise ValueError(f"Missing GIR directory: {gir_directory}")
    if not typelib_directory.is_dir():
        raise ValueError(f"Missing typelib directory: {typelib_directory}")

    pending = deque(roots)
    visited = set()
    while pending:
        identity = pending.popleft()
        if identity in visited:
            continue
        gir = gir_directory / f"{identity}.gir"
        if not gir.is_file():
            raise ValueError(f"Missing GIR include: {gir.name}")
        repository, actual_identity = gir_identity(gir)
        if actual_identity != identity:
            raise ValueError(
                f"GIR identity mismatch for {gir.name}: found {actual_identity}")
        typelib = typelib_directory / f"{identity}.typelib"
        if not typelib.is_file() or typelib.stat().st_size == 0:
            raise ValueError(f"Missing compiled typelib: {typelib.name}")
        visited.add(identity)
        for include in repository.findall(f"{{{CORE_NAMESPACE}}}include"):
            name = include.attrib.get("name")
            version = include.attrib.get("version")
            if not name or not version:
                raise ValueError(f"GIR {gir.name} has an incomplete include")
            pending.append(f"{name}-{version}")
    return visited


def main():
    parser = argparse.ArgumentParser(
        description="Verify the GTK4 refresh GIR and compiled typelib closure")
    parser.add_argument("prefix", type=Path)
    parser.add_argument("roots", nargs="*", default=DEFAULT_ROOTS)
    arguments = parser.parse_args()
    try:
        closure = verify_closure(arguments.prefix, arguments.roots)
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    print("Verified GTK4 refresh GIR closure: " + ", ".join(sorted(closure)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
