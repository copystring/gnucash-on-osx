#!/usr/bin/env python3

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "macos-bundle-metadata.py"
SPEC = importlib.util.spec_from_file_location("macos_bundle_metadata", SCRIPT)
metadata = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(metadata)


FAT_OUTPUT = """\
sample (architecture arm64):
Load command 1
      cmd LC_BUILD_VERSION
 platform 1
    minos 12.3
sample (architecture x86_64):
Load command 1
      cmd LC_BUILD_VERSION
 platform MACOS
    minos 26.5
"""


class BundleMinimumVersionTest(unittest.TestCase):
    def test_compares_versions_numerically(self):
        self.assertGreater(metadata.macos_version_key("26.5"),
                           metadata.macos_version_key("11.15"))
        self.assertEqual(metadata.macos_version_key("26.5"),
                         metadata.macos_version_key("26.5.0"))

    def test_compares_each_fat_architecture(self):
        self.assertEqual(
            metadata.load_command_minimum_versions(FAT_OUTPUT, "fat"),
            ["12.3", "26.5"],
        )

    def test_rejects_architecture_without_minimum(self):
        output = FAT_OUTPUT.replace("    minos 26.5\n", "")
        with self.assertRaisesRegex(ValueError, "architecture x86_64"):
            metadata.load_command_minimum_versions(output, "fat")

    def test_rejects_architecture_without_minimum_load_command(self):
        output = FAT_OUTPUT.replace(
            "Load command 1\n      cmd LC_BUILD_VERSION\n platform MACOS\n"
            "    minos 26.5\n",
            "Load command 1\n      cmd LC_UUID\n",
        )
        with self.assertRaisesRegex(ValueError, "architecture x86_64"):
            metadata.load_command_minimum_versions(output, "fat")

    def test_rejects_non_macos_or_missing_build_platform(self):
        for platform in ("2", None):
            platform_line = "" if platform is None else f" platform {platform}\n"
            output = (
                "Load command 1\n"
                "      cmd LC_BUILD_VERSION\n"
                f"{platform_line}"
                "    minos 26.5\n"
            )
            with self.assertRaisesRegex(ValueError, "macOS platform"):
                metadata.load_command_minimum_versions(output, "thin")

    def test_accepts_legacy_minimum_command(self):
        output = """\
Load command 1
      cmd LC_VERSION_MIN_MACOSX
  version 10.15.7
"""
        self.assertEqual(
            metadata.load_command_minimum_versions(output, "legacy"),
            ["10.15.7"],
        )

    def test_bundle_scan_skips_resources_and_uses_highest_architecture(self):
        with tempfile.TemporaryDirectory() as temporary:
            contents = Path(temporary)
            binary = contents / "Frameworks" / "example"
            binary.parent.mkdir()
            binary.write_bytes(b"\xca\xfe\xba\xbe")
            (contents / "README").write_text("ordinary resource", encoding="utf-8")
            completed = subprocess.CompletedProcess(["otool"], 0, FAT_OUTPUT, "")
            with mock.patch.object(metadata.subprocess, "run", return_value=completed):
                self.assertEqual(metadata.bundle_minimum_version(contents, "otool"),
                                 "26.5")


if __name__ == "__main__":
    unittest.main()
