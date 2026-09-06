#!/usr/bin/env python3

import argparse
import plistlib
import re
import sys
from pathlib import Path


CORE_VERSION_RE = re.compile(r"^([0-9]+)\.([0-9]+)$")
REVISION_RE = re.compile(r"^[1-9][0-9]*$")
YEAR_RE = re.compile(r"^[0-9]{4}$")
CMAKE_VERSION_PREFIX = "CMAKE_PROJECT_VERSION:STATIC="


def validate_components(core_version, revision, year):
    version_match = CORE_VERSION_RE.fullmatch(core_version)
    if not version_match:
        raise ValueError(
            f"expected major.minor CMake project version: {core_version!r}"
        )
    if not REVISION_RE.fullmatch(revision):
        raise ValueError(f"invalid macOS bundle revision: {revision!r}")
    if not YEAR_RE.fullmatch(year):
        raise ValueError(f"invalid copyright year: {year!r}")
    return version_match.groups()


def package_metadata(core_version, revision, year):
    major, minor = validate_components(core_version, revision, year)
    package_version = f"{core_version}-{revision}"
    product_version = f"{major}.{minor}.0"
    build_version = f"{major}.{minor}.{revision}"
    return {
        "CFBundleGetInfoString":
            f"Gnucash version {package_version} © {year} GnucashContributors",
        "CFBundleLongVersionString":
            f"{package_version} © {year} Gnucash Contributors",
        "CFBundleShortVersionString": product_version,
        "CFBundleVersion": build_version,
        "NSHumanReadableCopyright":
            f"Copyright {year} Gnucash Contributors",
    }


def read_core_version(cache_path):
    values = []
    with cache_path.open(encoding="utf-8") as cache:
        for line in cache:
            if line.startswith(CMAKE_VERSION_PREFIX):
                values.append(line[len(CMAKE_VERSION_PREFIX):].strip())

    if len(values) != 1:
        raise ValueError(
            "expected exactly one CMAKE_PROJECT_VERSION:STATIC entry in "
            f"{cache_path}, found {len(values)}"
        )
    core_version = values[0]
    if not CORE_VERSION_RE.fullmatch(core_version):
        raise ValueError(
            "expected major.minor CMake project version in "
            f"{cache_path}: {core_version!r}"
        )
    return core_version


def read_plist(plist_path):
    with plist_path.open("rb") as source:
        contents = plistlib.load(source)
    if not isinstance(contents, dict):
        raise ValueError(f"expected a dictionary plist: {plist_path}")
    return contents


def prepare_plist(source_path, output_path, core_version, revision, year):
    contents = read_plist(source_path)
    contents.update(package_metadata(core_version, revision, year))
    with output_path.open("wb") as output:
        plistlib.dump(contents, output, sort_keys=False)


def verify_plist(plist_path, core_version, revision, year):
    contents = read_plist(plist_path)
    mismatches = []
    for key, expected in package_metadata(core_version, revision, year).items():
        actual = contents.get(key)
        if actual != expected:
            mismatches.append(f"{key}: expected {expected!r}, found {actual!r}")
    if mismatches:
        raise ValueError(
            f"bundle metadata mismatch in {plist_path}: " + "; ".join(mismatches)
        )


def create_parser():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    core_version = subparsers.add_parser("core-version")
    core_version.add_argument("cmake_cache", type=Path)

    prepare = subparsers.add_parser("prepare")
    prepare.add_argument("source_plist", type=Path)
    prepare.add_argument("output_plist", type=Path)
    prepare.add_argument("core_version")
    prepare.add_argument("revision")
    prepare.add_argument("year")

    verify = subparsers.add_parser("verify")
    verify.add_argument("plist", type=Path)
    verify.add_argument("core_version")
    verify.add_argument("revision")
    verify.add_argument("year")
    return parser


def main():
    args = create_parser().parse_args()
    if args.command == "core-version":
        print(read_core_version(args.cmake_cache))
    elif args.command == "prepare":
        prepare_plist(args.source_plist, args.output_plist,
                      args.core_version, args.revision, args.year)
    else:
        verify_plist(args.plist, args.core_version, args.revision, args.year)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"macOS bundle metadata error: {error}", file=sys.stderr)
        sys.exit(1)
