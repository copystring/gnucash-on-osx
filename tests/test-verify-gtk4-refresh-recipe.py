#!/usr/bin/env python3

import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parent.parent
SCRIPT = REPOSITORY / "verify-gtk4-refresh-recipe.py"
SPEC = importlib.util.spec_from_file_location("verify_gtk4_refresh_recipe", SCRIPT)
RECIPE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RECIPE)

BASELINE = "c144445a3e021a3743b70b46119533995c588bce"
BASE_MANIFEST_SHA256 = "46c7c7962081bf255197954e7810080ad04120bcd346bbd905a6956021c1a3cd"


class RefreshRecipeTests(unittest.TestCase):
    @staticmethod
    def manifest():
        return (b"bin/cmake\nbin/ctest\nbin/gettext\n"
                b"include/dbi/\ninclude/freetype2/\ninclude/fribidi/\ninclude/gmp.h\n"
                b"include/pixman-1\n"
                b"include/python3.14/\ninclude/unicode/\n"
                b"lib/gio/\nlib/glib-2.0/\n"
                b"lib/libgpg-error.dylib lib/libgpg-error.0.dylib\n"
                b"lib/libpcre2-8.dylib lib/libpcre2-8.0.dylib\n"
                b"share/gettext-1.0/\nshare/glib-2.0/\n")

    def test_manifest_allows_only_audited_output_headers(self):
        base = self.manifest()
        output = RECIPE.expected_output_manifest(base)
        RECIPE.verify_manifest(base, output, hashlib.sha256(base).hexdigest())
        self.assertIn(b"include/epoxy/\n", output)
        self.assertIn(b"include/fontconfig/\n", output)
        self.assertIn(b"include/jconfig.h include/jerror.h include/jmorecfg.h include/jpeglib.h\n",
                      output)
        self.assertIn(b"include/tiff.h include/tiffconf.h include/tiffio.h include/tiffvers.h\n",
                      output)
        self.assertIn(b"include/pcre2.h include/pcre2posix.h\n", output)
        self.assertIn(b"include/zconf.h include/zlib.h\n", output)
        self.assertIn(b"lib/libpcre2-16.dylib lib/libpcre2-16.0.dylib\n", output)
        self.assertIn(b"lib/libpcre2-32.dylib lib/libpcre2-32.0.dylib\n", output)
        self.assertIn(b"lib/libpcre2-posix.dylib lib/libpcre2-posix.3.dylib\n", output)
        self.assertIn(b"include/gobject-introspection-1.0/\n", output)
        self.assertIn(
            b"lib/libgirepository-1.0.dylib lib/libgirepository-1.0.1.dylib\n",
            output)
        self.assertIn(b"lib/girepository-1.0/\n", output)
        self.assertIn(b"share/gir-1.0/\n", output)

        with self.assertRaisesRegex(ValueError, "beyond the audited developer-closure"):
            RECIPE.verify_manifest(base, output + b"include/unreviewed.h\n",
                                   hashlib.sha256(base).hexdigest())

    def test_manifest_rejects_wrong_input_sha(self):
        base = self.manifest()
        output = RECIPE.expected_output_manifest(base)
        with self.assertRaisesRegex(ValueError, "input manifest SHA-256 mismatch"):
            RECIPE.verify_manifest(base, output, "0" * 64)

    def test_moduleset_rejects_unreviewed_output_patch(self):
        base = self.moduleset(RECIPE.EXPECTED_BASE_PATCHES, include_refresh_zlib=False)
        output = self.moduleset(
            RECIPE.EXPECTED_OUTPUT_PATCHES + ["unreviewed.patch"])
        with self.assertRaisesRegex(ValueError, "only the audited ownership patches"):
            RECIPE.verify_moduleset(base, output)

    def test_moduleset_requires_exact_refresh_zlib_source(self):
        base = self.moduleset(RECIPE.EXPECTED_BASE_PATCHES,
                              include_refresh_zlib=False)
        missing = self.moduleset(RECIPE.EXPECTED_OUTPUT_PATCHES,
                                 include_refresh_zlib=False)
        with self.assertRaisesRegex(ValueError, "unexpected zlib repository"):
            RECIPE.verify_moduleset(base, missing)

        changed = self.moduleset(RECIPE.EXPECTED_OUTPUT_PATCHES).replace(
            "zlib-1.3.2.tar.xz", "zlib-1.3.1.tar.xz")
        with self.assertRaisesRegex(ValueError, "unexpected zlib source identity"):
            RECIPE.verify_moduleset(base, changed)

    def test_checkout_uses_exact_commits_not_platform_line_endings(self):
        with tempfile.TemporaryDirectory() as temporary:
            checkout = Path(temporary)
            subprocess.run(["git", "init", "--quiet", str(checkout)], check=True)
            subprocess.run(
                ["git", "-C", str(checkout), "config", "user.email", "fixture@example.invalid"],
                check=True)
            subprocess.run(
                ["git", "-C", str(checkout), "config", "user.name", "Fixture"], check=True)
            (checkout / "modulesets").mkdir()
            base_manifest = self.manifest()
            (checkout / RECIPE.BASE_MANIFEST_PATH).write_bytes(base_manifest)
            (checkout / RECIPE.MODULESET_PATH).write_text(
                self.moduleset(RECIPE.EXPECTED_BASE_PATCHES,
                               include_refresh_zlib=False), encoding="utf-8")
            subprocess.run(["git", "-C", str(checkout), "add", "."], check=True)
            subprocess.run(
                ["git", "-C", str(checkout), "commit", "--quiet", "-m", "base"], check=True)
            baseline = subprocess.check_output(
                ["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()

            (checkout / RECIPE.BASE_MANIFEST_PATH).write_bytes(
                RECIPE.expected_output_manifest(base_manifest))
            (checkout / RECIPE.MODULESET_PATH).write_text(
                self.moduleset(RECIPE.EXPECTED_OUTPUT_PATCHES), encoding="utf-8")
            subprocess.run(["git", "-C", str(checkout), "add", "."], check=True)
            subprocess.run(
                ["git", "-C", str(checkout), "commit", "--quiet", "-m", "output"], check=True)
            output_revision = subprocess.check_output(
                ["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()

            # Simulate a later CRLF working-tree mutation. The contract remains
            # tied to the two explicit, reviewed Git revisions.
            (checkout / RECIPE.BASE_MANIFEST_PATH).write_bytes(
                RECIPE.expected_output_manifest(base_manifest).replace(b"\n", b"\r\n"))
            RECIPE.verify_checkout(
                checkout, baseline, output_revision,
                hashlib.sha256(base_manifest).hexdigest())

    @staticmethod
    def moduleset(patch_names, include_refresh_zlib=True):
        patch_xml = "".join(f'<patch file="{name}"/>' for name in patch_names)
        zlib_xml = ""
        if include_refresh_zlib:
            zlib_xml = (
                '<repository name="zlib" href="https://zlib.net/fossils/" type="tarball"/>'
                '<autotools id="zlib-gtk4-refresh" autogen-sh="configure">'
                '<branch repo="zlib" module="zlib-1.3.2.tar.xz" version="1.3.2" '
                'hash="sha256:d7a0654783a4da529d1bb793b7ad9c3318020af77667bcae35f95d0e42a792f3"/>'
                '</autotools>')
        return (
            '<moduleset>' + zlib_xml + '<autotools id="gtk-4" autogenargs="--fixture">'
            f'<branch repo="fixture" module="gtk.tar.xz">{patch_xml}</branch>'
            '<dependencies><dep package="glib"/></dependencies>'
            '</autotools></moduleset>')

    def test_real_pinned_recipe_when_commit_is_available(self):
        available = subprocess.run(
            ["git", "-C", str(REPOSITORY), "cat-file", "-e", f"{BASELINE}^{{commit}}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        if available.returncode:
            self.skipTest("pinned refresh base commit is unavailable in this checkout")
        completed = subprocess.run(
            [sys.executable, str(SCRIPT), str(REPOSITORY), BASELINE,
             os.environ.get("OUTPUT_RECIPE_REVISION", "HEAD"), BASE_MANIFEST_SHA256],
            text=True, capture_output=True, check=False)
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_static_recipe_gate_precedes_expensive_bootstrap(self):
        workflow = (REPOSITORY / ".github/workflows/gtk4-macos-dependencies.yml").read_text(
            encoding="utf-8")
        recipe = workflow.index("- name: Validate GTK4 refresh input recipe")
        install = workflow.index("- name: Install GTK-OSX build environment")
        bootstrap = workflow.index("- name: Bootstrap GTK-OSX")
        restore = workflow.index("- name: Restore and validate GTK4 refresh base")
        self.assertLess(recipe, install)
        self.assertLess(install, bootstrap)
        self.assertLess(bootstrap, restore)
        self.assertIn(
            'output_recipe_ref="$(git -C "$GITHUB_WORKSPACE/gnucash-on-osx" rev-parse HEAD)"',
            workflow)
        self.assertNotIn("git -C \"$GITHUB_WORKSPACE/gnucash-on-osx\" diff --exit-code", workflow)


if __name__ == "__main__":
    unittest.main()
