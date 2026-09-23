#!/usr/bin/env python3

import os
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "modulesets" / "generate-docs-overlay.py"
BASE_MODULESET = ROOT / "modulesets" / "gnucash.modules"
JHBUILD_CONFIG = ROOT / "jhbuildrc-custom"
PINNED_REPOSITORY = "copystring/gnucash-docs"
PINNED_BRANCH = "fix/gtk4-docs-integrated-prepr-20260912"
PINNED_REVISION = "824a138e8588264c971bb58ad9dacd34420a6bd4"


def docs_module(root):
    modules = [
        module
        for module in root
        if module.tag == "cmake" and module.get("id") == "gnucash-docs"
    ]
    if len(modules) != 1:
        raise AssertionError("expected exactly one gnucash-docs module")
    return modules[0]


def non_branch_children(module):
    return [
        ET.tostring(child, encoding="unicode")
        for child in module
        if child.tag != "branch"
    ]


class DocsOverlayGeneratorTest(unittest.TestCase):
    def generate(self, output, repository, branch, revision):
        return subprocess.run(
            [
                sys.executable,
                str(GENERATOR),
                str(BASE_MODULESET),
                str(output),
                repository,
                branch,
                revision,
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def configured_modulesets(self, docs_moduleset=None, deployment_target=None):
        environment = {
            "MODULESET": str(BASE_MODULESET),
            "HOME": "/tmp/home",
            "CC": "cc",
            "CFLAGS": "-O2",
            "CXXFLAGS": "-O2",
        }
        if docs_moduleset:
            environment["DOCS_MODULESET"] = str(docs_moduleset)
        if deployment_target is not None:
            environment["MACOSX_DEPLOYMENT_TARGET"] = deployment_target
        setup_sdk = mock.Mock()
        namespace = {
            "os": os,
            "_target": "26.6",
            "setup_sdk": setup_sdk,
            "append_autogenargs": lambda *_args: None,
            "module_extra_env": {},
            "module_cmakeargs": {},
        }
        with mock.patch.dict(os.environ, environment, clear=True):
            exec(JHBUILD_CONFIG.read_text(encoding="utf-8"), namespace)
        setup_sdk.assert_called_once_with(
            target=deployment_target if deployment_target is not None else "26.6"
        )
        return namespace["moduleset"]

    def test_explicit_deployment_target_preserves_archive_contract(self):
        self.assertEqual(
            self.configured_modulesets(deployment_target="26.5"),
            str(BASE_MODULESET),
        )

    def test_blank_inputs_leave_the_tarball_moduleset_unchanged(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "docs-overlay.modules"
            result = self.generate(output, "", "", "")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(output.exists())
            self.assertEqual(self.configured_modulesets(), str(BASE_MODULESET))

    def test_pin_round_trip_preserves_the_docs_build_attributes(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "docs-overlay.modules"
            result = self.generate(output, PINNED_REPOSITORY, PINNED_BRANCH,
                                   PINNED_REVISION)
            self.assertEqual(result.returncode, 0, result.stderr)

            base = docs_module(ET.parse(BASE_MODULESET).getroot())
            overlay_root = ET.parse(output).getroot()
            overlay = docs_module(overlay_root)
            self.assertEqual(overlay.attrib, base.attrib)
            self.assertEqual(non_branch_children(overlay), non_branch_children(base))

            repositories = [
                repository
                for repository in overlay_root
                if repository.tag == "repository" and repository.get("name") == "github"
            ]
            self.assertEqual(len(repositories), 1)
            self.assertEqual(repositories[0].attrib, {
                "type": "git",
                "name": "github",
                "href": "https://github.com/",
            })

            branches = [child for child in overlay if child.tag == "branch"]
            self.assertEqual(len(branches), 1)
            self.assertEqual(branches[0].attrib, {
                "repo": "github",
                "module": f"{PINNED_REPOSITORY}.git",
                "tag": PINNED_BRANCH,
                "checkoutdir": "gnucash-docs",
            })
            self.assertEqual(
                self.configured_modulesets(output),
                [str(BASE_MODULESET), str(output)],
            )

    def test_incomplete_or_unsafe_inputs_fail_closed(self):
        cases = (
            (PINNED_REPOSITORY, "", PINNED_REVISION, "all be blank or supplied"),
            ("", PINNED_BRANCH, PINNED_REVISION, "all be blank or supplied"),
            ("copystring/../gnucash-docs", PINNED_BRANCH, PINNED_REVISION,
             "owner/repository"),
            (PINNED_REPOSITORY, "../invalid", PINNED_REVISION, "valid branch"),
            (PINNED_REPOSITORY, PINNED_BRANCH, "stable", "40-character commit SHA"),
        )
        with tempfile.TemporaryDirectory() as temporary:
            for number, (repository, branch, revision, expected) in enumerate(cases):
                output = Path(temporary) / f"invalid-{number}.modules"
                result = self.generate(output, repository, branch, revision)
                self.assertEqual(result.returncode, 2)
                self.assertIn(expected, result.stderr)
                self.assertFalse(output.exists())

    def test_existing_overlay_is_never_reused_or_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "docs-overlay.modules"
            original = "old overlay must remain untouched\n"
            output.write_text(original, encoding="utf-8")

            for repository, branch, revision in (("", "", ""),
                                                 (PINNED_REPOSITORY, PINNED_BRANCH,
                                                  PINNED_REVISION)):
                result = self.generate(output, repository, branch, revision)
                self.assertEqual(result.returncode, 2)
                self.assertIn("existing overlay", result.stderr)
                self.assertEqual(output.read_text(encoding="utf-8"), original)


if __name__ == "__main__":
    unittest.main()
