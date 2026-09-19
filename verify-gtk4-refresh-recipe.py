#!/usr/bin/env python3

import argparse
import difflib
import hashlib
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET


BASE_MANIFEST_PATH = "dependencies-gtk4.txt"
MODULESET_PATH = "modulesets/gnucash.modules"
OUTPUT_MANIFEST_ADDITIONS = (
    (b"bin/ctest\n", b"bin/gdbus-codegen\n"),
    (b"include/dbi/\n", b"include/epoxy/\ninclude/fontconfig/\n"),
    (b"include/fribidi/\n", b"include/ffi.h include/ffitarget.h\n"),
    (b"include/gmp.h\n",
     b"include/gobject-introspection-1.0/\n"
     b"include/jconfig.h include/jerror.h include/jmorecfg.h include/jpeglib.h\n"),
    (b"include/pixman-1\n", b"include/pcre2.h include/pcre2posix.h\n"),
    (b"include/python3.14/\n",
     b"include/tiff.h include/tiffconf.h include/tiffio.h include/tiffvers.h\n"),
    (b"include/unicode/\n", b"include/zconf.h include/zlib.h\n"),
    (b"lib/gio/\n", b"lib/girepository-1.0/\n"),
    (b"lib/libgpg-error.dylib lib/libgpg-error.0.dylib\n",
     b"lib/libgirepository-1.0.dylib lib/libgirepository-1.0.1.dylib\n"),
    (b"lib/libpcre2-8.dylib lib/libpcre2-8.0.dylib\n",
     b"lib/libpcre2-16.dylib lib/libpcre2-16.0.dylib\n"
     b"lib/libpcre2-32.dylib lib/libpcre2-32.0.dylib\n"
     b"lib/libpcre2-posix.dylib lib/libpcre2-posix.3.dylib\n"),
    (b"share/gettext-1.0/\n", b"share/gir-1.0/\n"),
)
EXPECTED_BASE_PATCHES = ["gtk-4.22.1-macos-toplevel-remap.patch"]
EXPECTED_OUTPUT_PATCHES = [
    *EXPECTED_BASE_PATCHES,
    "gtk-4.22.1-column-view-focus-column-ownership.patch",
    "gtk-4.22.1-window-deferred-focus-ownership.patch",
]
EXPECTED_REFRESH_ZLIB = {
    "id": "zlib-gtk4-refresh",
    "autogen-sh": "configure",
    "repo": "zlib",
    "module": "zlib-1.3.2.tar.xz",
    "version": "1.3.2",
    "hash": "sha256:d7a0654783a4da529d1bb793b7ad9c3318020af77667bcae35f95d0e42a792f3",
    "href": "https://zlib.net/fossils/",
    "type": "tarball",
}


def git_bytes(checkout, *arguments):
    return subprocess.check_output(
        ["git", "-C", str(checkout), *arguments], stderr=subprocess.STDOUT)


def expected_output_manifest(base_manifest):
    output_manifest = base_manifest
    for anchor, addition in OUTPUT_MANIFEST_ADDITIONS:
        if output_manifest.count(anchor) != 1:
            raise ValueError(
                f"GTK refresh input manifest has an unexpected {anchor.strip()!r} anchor")
        if addition in output_manifest.splitlines(keepends=True):
            raise ValueError(
                f"GTK refresh input manifest already contains output-only {addition.strip()!r}")
        output_manifest = output_manifest.replace(anchor, anchor + addition, 1)
    return output_manifest


def verify_manifest(base_manifest, output_manifest, expected_sha256):
    actual_sha256 = hashlib.sha256(base_manifest).hexdigest()
    if actual_sha256 != expected_sha256:
        raise ValueError(
            f"GTK refresh input manifest SHA-256 mismatch: expected {expected_sha256}, "
            f"got {actual_sha256}")
    expected_output = expected_output_manifest(base_manifest)
    if output_manifest != expected_output:
        difference = "".join(difflib.unified_diff(
            expected_output.decode("utf-8").splitlines(keepends=True),
            output_manifest.decode("utf-8").splitlines(keepends=True),
            fromfile="expected-output-manifest",
            tofile="dependencies-gtk4.txt"))
        raise ValueError(
            "GTK refresh output manifest differs from the pinned input manifest "
            f"beyond the audited developer-closure additions:\n{difference}")


def gtk_module(root):
    matches = [module for module in root if module.attrib.get("id") == "gtk-4"]
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one gtk-4 module, found {len(matches)}")
    return matches[0]


def packages(module):
    dependencies = module.find("dependencies")
    if dependencies is None:
        raise ValueError("gtk-4 module has no dependencies")
    return [item.attrib["package"] for item in dependencies]


def patches(module):
    branch = module.find("branch")
    if branch is None:
        raise ValueError("gtk-4 module has no branch")
    return [item.attrib["file"] for item in branch.findall("patch")]


def verify_moduleset(base_xml, output_xml):
    base_root = ET.fromstring(base_xml)
    output_root = ET.fromstring(output_xml)
    base = gtk_module(base_root)
    output = gtk_module(output_root)
    base_branch = base.find("branch")
    output_branch = output.find("branch")
    if base_branch is None or output_branch is None:
        raise ValueError("gtk-4 module has no branch")
    if base.attrib != output.attrib:
        raise ValueError("GTK refresh base has different GTK module arguments")
    if base_branch.attrib != output_branch.attrib:
        raise ValueError("GTK refresh base has different GTK source identity")
    if packages(base) != packages(output):
        raise ValueError("GTK refresh base has different GTK dependencies")
    if patches(base) != EXPECTED_BASE_PATCHES:
        raise ValueError("GTK refresh base has an unexpected GTK patch set")
    if patches(output) != EXPECTED_OUTPUT_PATCHES:
        raise ValueError("GTK refresh mode permits only the audited ownership patches")
    if any(module.attrib.get("id") == EXPECTED_REFRESH_ZLIB["id"]
           for module in base_root):
        raise ValueError("GTK refresh base unexpectedly contains the output-only zlib module")
    zlib_repositories = [repository for repository in output_root.findall("repository")
                         if repository.attrib.get("name") == "zlib"]
    expected_repository_attributes = {
        "name": "zlib",
        "href": EXPECTED_REFRESH_ZLIB["href"],
        "type": EXPECTED_REFRESH_ZLIB["type"],
    }
    if len(zlib_repositories) != 1 or \
       zlib_repositories[0].attrib != expected_repository_attributes:
        raise ValueError("GTK refresh output has an unexpected zlib repository")
    zlib_modules = [module for module in output_root
                    if module.attrib.get("id") == EXPECTED_REFRESH_ZLIB["id"]]
    if len(zlib_modules) != 1:
        raise ValueError("GTK refresh output must contain exactly one pinned zlib module")
    zlib_module = zlib_modules[0]
    zlib_branch = zlib_module.find("branch")
    expected_module_attributes = {
        "id": EXPECTED_REFRESH_ZLIB["id"],
        "autogen-sh": EXPECTED_REFRESH_ZLIB["autogen-sh"],
    }
    expected_branch_attributes = {
        key: EXPECTED_REFRESH_ZLIB[key]
        for key in ("repo", "module", "version", "hash")
    }
    if zlib_module.tag != "autotools" or zlib_module.attrib != expected_module_attributes:
        raise ValueError("GTK refresh output has an unexpected zlib build definition")
    if zlib_branch is None or zlib_branch.attrib != expected_branch_attributes:
        raise ValueError("GTK refresh output has an unexpected zlib source identity")


def verify_checkout(checkout, baseline, output_revision, manifest_sha256):
    base_manifest = git_bytes(checkout, "show", f"{baseline}:{BASE_MANIFEST_PATH}")
    output_manifest = git_bytes(
        checkout, "show", f"{output_revision}:{BASE_MANIFEST_PATH}")
    verify_manifest(base_manifest, output_manifest, manifest_sha256)
    base_moduleset = git_bytes(checkout, "show", f"{baseline}:{MODULESET_PATH}")
    output_moduleset = git_bytes(
        checkout, "show", f"{output_revision}:{MODULESET_PATH}")
    verify_moduleset(base_moduleset, output_moduleset)


def main():
    parser = argparse.ArgumentParser(
        description="Verify the pinned GTK4 refresh input recipe and audited output delta")
    parser.add_argument("checkout", type=Path)
    parser.add_argument("baseline")
    parser.add_argument("output_revision")
    parser.add_argument("manifest_sha256")
    arguments = parser.parse_args()
    try:
        verify_checkout(arguments.checkout, arguments.baseline,
                        arguments.output_revision,
                        arguments.manifest_sha256)
    except (ET.ParseError, OSError, subprocess.CalledProcessError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    print("Verified GTK4 refresh input recipe and output manifest contract.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
