#!/usr/bin/env python3

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PREFLIGHT = ROOT / ".github" / "workflows" / "macos-gtk4-bundle-preflight.yml"
HANDOFF = ROOT / ".github" / "workflows" / "macos-gtk4-bundle-artifact.yml"


class BundleWorkflowContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.preflight = PREFLIGHT.read_text(encoding="utf-8")
        cls.handoff = HANDOFF.read_text(encoding="utf-8")

    def test_published_dispatch_contract_remains_required_and_native(self):
        dispatch = self.preflight.split("  workflow_dispatch:\n", 1)[1].split(
            "  workflow_call:\n", 1)[0]
        for input_name in ("dependencies_url", "dependencies_sha256"):
            section = dispatch.split(f"      {input_name}:\n", 1)[1]
            self.assertIn("        required: true\n", section)
        self.assertNotIn("dependencies_deployment_target", dispatch)

        job_environment = self.preflight.split("    env:\n", 1)[1].split(
            "\n    steps:\n", 1)[0]
        self.assertNotIn("MACOSX_DEPLOYMENT_TARGET", job_environment)
        self.assertNotIn("ARCHIVE_MACOS_DEPLOYMENT_TARGET", job_environment)

        published = self.preflight.split(
            "      - name: Download published GTK4 dependencies\n", 1
        )[1].split("\n      - name:", 1)[0]
        self.assertIn('curl --fail --location --show-error "$DEPENDENCIES_URL"', published)
        self.assertIn(
            'echo "$DEPENDENCIES_SHA256  $archive" | shasum -a 256 -c -',
            published,
        )

    def test_reusable_deployment_target_is_an_explicit_opt_in(self):
        workflow_call = self.preflight.split("  workflow_call:\n", 1)[1].split(
            "\npermissions:\n", 1)[0]
        target = workflow_call.split(
            "      dependencies_deployment_target:\n", 1)[1]
        self.assertIn("        default: ''\n", target)
        self.assertIn(
            'if test -n "$DEPENDENCIES_DEPLOYMENT_TARGET"; then',
            self.preflight,
        )
        self.assertIn(
            'if test -n "${ARCHIVE_MACOS_DEPLOYMENT_TARGET:-}"; then',
            self.preflight,
        )

    def test_internal_handoff_pins_the_archive_target(self):
        self.assertIn("dependencies_deployment_target: '26.5'", self.handoff)
        self.assertIn(
            "docs_branch: fix/gtk4-docs-integrated-prepr-20260912",
            self.handoff,
        )

    def test_documentation_branch_is_checked_against_commit_pin(self):
        self.assertIn('"$DOCS_BRANCH" "$DOCS_REF"', self.preflight)
        self.assertIn('"refs/heads/$DOCS_BRANCH"', self.preflight)
        self.assertIn('test "$branch_head" = "$DOCS_REF"', self.preflight)
        self.assertIn('git -C "$docs_source" rev-parse HEAD', self.preflight)

    def test_artifact_download_provenance_inputs_are_in_step_environment(self):
        step = self.preflight.split(
            "      - name: Download pinned GTK4 dependency artifact\n", 1
        )[1].split("\n      - name:", 1)[0]
        environment, script = step.split("        run: |\n", 1)
        for name in set(re.findall(r'\$(DEPENDENCIES_[A-Z_]+)', script)):
            self.assertIn(f"          {name}:", environment)

    def test_documentation_build_cannot_expand_dependency_closure(self):
        self.assertIn(
            '"$JHBUILD" --no-interact --exit-on-error buildone gnucash-docs',
            self.preflight,
        )
        self.assertNotIn('"$JHBUILD" build gnucash-docs', self.preflight)

    def test_gtk_osx_bootstrap_uses_a_single_moduleset(self):
        bootstrap = self.preflight.split(
            "      - name: Bootstrap GTK-OSX\n", 1
        )[1].split("\n      - name:", 1)[0]
        self.assertIn('DOCS_MODULESET= "$JHBUILD" bootstrap-gtk-osx', bootstrap)
        docs = self.preflight.split(
            "      - name: Build GnuCash documentation\n", 1
        )[1].split("\n      - name:", 1)[0]
        self.assertIn('"$JHBUILD" updateone gnucash-docs', docs)

    def test_bundler_uses_the_verified_jhbuild_install_prefix(self):
        self.assertIn(
            '"$GITHUB_WORKSPACE/gnucash-on-osx/verify-jhbuild-prefix.sh" \\\n'
            '            "$INSTALL_PREFIX"',
            self.preflight,
        )
        self.assertIn(
            '"$JHBUILD" run env HOME="$BUNDLE_HOME" gtk-mac-bundler',
            self.preflight,
        )

    def test_generated_bundle_has_runtime_and_mach_o_closure_gates(self):
        for contract in (
            'verify-macos-app-bundle.sh',
            'mach-o-minimum-system-version "$app/Contents/MacOS/Gnucash"',
            'bundle-minimum-system-version "$app/Contents"',
            'otool -L "$binary"',
            "grep -q 'libgtk-4' \"$links\"",
            "grep -q '/System/Library/Frameworks/WebKit.framework/' \"$links\"",
            '"$app/Contents/MacOS/Gnucash" --nofile',
        ):
            with self.subTest(contract=contract):
                self.assertIn(contract, self.preflight)


if __name__ == "__main__":
    unittest.main()
