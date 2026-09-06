#!/usr/bin/env python3

import argparse
import plistlib
import re
import subprocess
import sys
from pathlib import Path


CORE_VERSION_RE = re.compile(r"^([0-9]+)\.([0-9]+)$")
REVISION_RE = re.compile(r"^[1-9][0-9]*$")
YEAR_RE = re.compile(r"^[0-9]{4}$")
CMAKE_VERSION_PREFIX = "CMAKE_PROJECT_VERSION:STATIC="
MACOS_VERSION_RE = re.compile(r"^(0|[1-9][0-9]*)(?:\.(0|[1-9][0-9]*)){1,2}$")
MACH_O_MAGICS = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
    b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
}
ARCHITECTURE_HEADER_RE = re.compile(r"^.* \(architecture ([^)]+)\):$")


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


def macos_version_key(version):
    if not MACOS_VERSION_RE.fullmatch(version):
        raise ValueError(f"invalid macOS version: {version!r}")
    parts = [int(part) for part in version.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))


def is_mach_o(path):
    with path.open("rb") as source:
        return source.read(4) in MACH_O_MAGICS


def architecture_sections(output):
    sections = []
    current = []
    architecture = "thin"
    saw_header = False

    for line in output.splitlines():
        match = ARCHITECTURE_HEADER_RE.fullmatch(line)
        if match:
            if saw_header:
                sections.append((architecture, current))
            architecture = match.group(1)
            current = []
            saw_header = True
        else:
            current.append(line)
    sections.append((architecture, current))
    return sections


def load_command_minimum_versions(output, path):
    versions = []

    for architecture, lines in architecture_sections(output):
        architecture_versions = []
        command = None
        platform = None
        version = None

        def finish_command():
            nonlocal command, platform, version
            if command == "LC_BUILD_VERSION":
                if platform not in ("1", "MACOS"):
                    raise ValueError(
                        f"Mach-O file has {command} without a macOS platform "
                        f"in architecture {architecture}: {path}"
                    )
                if version is None:
                    raise ValueError(
                        f"Mach-O file has {command} without a minimum OS version "
                        f"in architecture {architecture}: {path}"
                    )
                architecture_versions.append(version)
            elif command == "LC_VERSION_MIN_MACOSX":
                if version is None:
                    raise ValueError(
                        f"Mach-O file has {command} without a minimum OS version "
                        f"in architecture {architecture}: {path}"
                    )
                architecture_versions.append(version)
            command = None
            platform = None
            version = None

        for line in lines:
            fields = line.split()
            if len(fields) == 2 and fields[0] == "cmd":
                finish_command()
                command = (fields[1] if fields[1] in ("LC_BUILD_VERSION",
                                                       "LC_VERSION_MIN_MACOSX")
                           else None)
            elif command == "LC_BUILD_VERSION" and len(fields) == 2:
                if fields[0] == "platform":
                    platform = fields[1].upper()
                elif fields[0] == "minos":
                    version = fields[1]
            elif (command == "LC_VERSION_MIN_MACOSX" and len(fields) == 2
                  and fields[0] == "version"):
                version = fields[1]
        finish_command()

        if not architecture_versions:
            raise ValueError(
                f"Mach-O file has no macOS minimum OS load command in "
                f"architecture {architecture}: {path}"
            )
        for minimum in architecture_versions:
            macos_version_key(minimum)
        versions.extend(architecture_versions)

    return versions


def bundle_minimum_version(contents_path, otool):
    contents = Path(contents_path)
    if not contents.is_dir():
        raise ValueError(f"missing bundle Contents directory: {contents}")

    versions = []
    for path in contents.rglob("*"):
        if path.is_symlink() or not path.is_file() or not is_mach_o(path):
            continue
        completed = subprocess.run([otool, "-l", str(path)], check=False,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True)
        if completed.returncode != 0:
            detail = completed.stderr.strip() or "no diagnostic"
            raise ValueError(f"cannot inspect Mach-O file {path}: {detail}")
        versions.extend(load_command_minimum_versions(completed.stdout, path))

    if not versions:
        raise ValueError(f"no Mach-O files found in bundle Contents: {contents}")
    return max(versions, key=macos_version_key)


def declared_minimum_version(plist_path):
    declared = read_plist(plist_path).get("LSMinimumSystemVersion")
    if not isinstance(declared, str):
        raise ValueError(f"missing LSMinimumSystemVersion in {plist_path}")
    macos_version_key(declared)
    return declared


def synchronize_minimum_version(plist_path, contents_path, otool):
    contents = read_plist(plist_path)
    declared = contents.get("LSMinimumSystemVersion")
    if not isinstance(declared, str):
        raise ValueError(f"missing LSMinimumSystemVersion in {plist_path}")
    payload_minimum = bundle_minimum_version(contents_path, otool)
    minimum = max((declared, payload_minimum), key=macos_version_key)
    contents["LSMinimumSystemVersion"] = minimum
    with Path(plist_path).open("wb") as output:
        plistlib.dump(contents, output, sort_keys=False)
    return minimum


def verify_minimum_version(plist_path, contents_path, otool):
    declared = declared_minimum_version(plist_path)
    payload_minimum = bundle_minimum_version(contents_path, otool)
    if macos_version_key(declared) < macos_version_key(payload_minimum):
        raise ValueError(
            "LSMinimumSystemVersion is lower than an included Mach-O minimum: "
            f"declared {declared}, payload requires {payload_minimum}"
        )


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

    for command in ("bundle-minimum-system-version",
                    "synchronize-minimum-system-version",
                    "verify-minimum-system-version"):
        minimum = subparsers.add_parser(command)
        if command != "bundle-minimum-system-version":
            minimum.add_argument("plist", type=Path)
        minimum.add_argument("contents", type=Path)
        minimum.add_argument("--otool", default="otool")
    return parser


def main():
    args = create_parser().parse_args()
    if args.command == "core-version":
        print(read_core_version(args.cmake_cache))
    elif args.command == "prepare":
        prepare_plist(args.source_plist, args.output_plist,
                      args.core_version, args.revision, args.year)
    elif args.command == "verify":
        verify_plist(args.plist, args.core_version, args.revision, args.year)
    elif args.command == "bundle-minimum-system-version":
        print(bundle_minimum_version(args.contents, args.otool))
    elif args.command == "synchronize-minimum-system-version":
        print(synchronize_minimum_version(args.plist, args.contents, args.otool))
    else:
        verify_minimum_version(args.plist, args.contents, args.otool)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"macOS bundle metadata error: {error}", file=sys.stderr)
        sys.exit(1)
