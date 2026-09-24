#!/usr/bin/env python3

import argparse
import copy
import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "verify-github-actions-artifact.py"
HANDOFF = (Path(__file__).resolve().parents[1] / ".github" / "workflows" /
           "macos-gtk4-bundle-artifact.yml")
REFRESH = (Path(__file__).resolve().parents[1] / ".github" / "workflows" /
           "gtk4-reviewed-macos-refresh.yml")
SPEC = importlib.util.spec_from_file_location("verify_actions_artifact", SCRIPT)
verifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verifier)

REPOSITORY = "copystring/gnucash-on-osx"
WORKFLOW = ".github/workflows/gtk4-reviewed-macos-refresh.yml"
HEAD_SHA = "e00227c29767508419ec2c2c0551eb2173ae9ec6"
RUN_ID = 35833375037
ARTIFACT_NAME = "gnucash-future-gtk4-mac-dependencies"
DIGEST = "1" * 64
BUNDLE_CORE_REF = "3fa9caaa2c64151c458451b56a66c57259304f5f"
REFRESH_CORE_REF = "7820bd5891d09a3264128721a445837983624213"


def arguments():
    return argparse.Namespace(
        repository=REPOSITORY,
        run_id=str(RUN_ID),
        workflow=WORKFLOW,
        head_sha=HEAD_SHA,
        artifact_name=ARTIFACT_NAME,
    )


def fixtures():
    run = {
        "id": RUN_ID,
        "path": WORKFLOW,
        "head_sha": HEAD_SHA,
        "status": "completed",
        "conclusion": "success",
        "repository": {"id": 123, "full_name": REPOSITORY},
    }
    artifacts = {
        "total_count": 1,
        "artifacts": [{
            "id": 456,
            "name": ARTIFACT_NAME,
            "expired": False,
            "digest": f"sha256:{DIGEST}",
            "archive_download_url": (
                f"https://api.github.com/repos/{REPOSITORY}/actions/artifacts/456/zip"
            ),
            "workflow_run": {
                "id": RUN_ID,
                "repository_id": 123,
                "head_sha": HEAD_SHA,
            },
        }],
    }
    return run, artifacts


class ActionsArtifactVerifierTest(unittest.TestCase):
    def test_handoff_workflow_pins_verified_sources(self):
        workflow = HANDOFF.read_text(encoding="utf-8")
        for expected in (
            f"dependencies_run_id: '{RUN_ID}'",
            f"dependencies_workflow: {WORKFLOW}",
            f"dependencies_head_sha: {HEAD_SHA}",
            "dependencies_deployment_target: '26.5'",
            f"core_ref: {BUNDLE_CORE_REF}",
            "docs_ref: 824a138e8588264c971bb58ad9dacd34420a6bd4",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, workflow)

        refresh = REFRESH.read_text(encoding="utf-8")
        self.assertIn(f"gnucash_ref: {REFRESH_CORE_REF}", refresh)

    def test_accepts_exact_completed_successful_unexpired_artifact(self):
        run, artifacts = fixtures()
        self.assertEqual(
            verifier.validate(run, artifacts, arguments()),
            {
                "artifact_id": "456",
                "artifact_download_url": (
                    f"https://api.github.com/repos/{REPOSITORY}/actions/artifacts/456/zip"
                ),
                "artifact_sha256": DIGEST,
            },
        )

    def assert_rejected(self, mutation, message):
        run, artifacts = fixtures()
        mutation(run, artifacts)
        with self.assertRaisesRegex(ValueError, message):
            verifier.validate(run, artifacts, arguments())

    def test_rejects_wrong_repository(self):
        self.assert_rejected(
            lambda run, _: run["repository"].update(full_name="other/project"),
            "producer repository",
        )

    def test_rejects_wrong_run_id(self):
        run, artifacts = fixtures()
        expected = arguments()
        expected.run_id = str(RUN_ID + 1)
        with self.assertRaisesRegex(ValueError, "producer run ID"):
            verifier.validate(run, artifacts, expected)

    def test_rejects_wrong_workflow(self):
        self.assert_rejected(
            lambda run, _: run.update(path=".github/workflows/other.yml"),
            "producer workflow",
        )

    def test_rejects_wrong_head_sha(self):
        self.assert_rejected(
            lambda run, _: run.update(head_sha="2" * 40),
            "producer head SHA",
        )

    def test_rejects_incomplete_or_failed_run(self):
        for field, value, message in (
            ("status", "in_progress", "not completed"),
            ("conclusion", "failure", "successfully"),
        ):
            with self.subTest(field=field):
                self.assert_rejected(
                    lambda run, _, field=field, value=value: run.update(
                        {field: value}),
                    message,
                )

    def test_rejects_expired_artifact(self):
        self.assert_rejected(
            lambda _, artifacts: artifacts["artifacts"][0].update(expired=True),
            "expired",
        )

    def test_rejects_missing_or_duplicate_exact_name(self):
        self.assert_rejected(
            lambda _, artifacts: artifacts["artifacts"][0].update(name="other"),
            "exactly one artifact",
        )
        self.assert_rejected(
            lambda _, artifacts: (
                artifacts["artifacts"].append(
                    copy.deepcopy(artifacts["artifacts"][0])),
                artifacts.update(total_count=2),
            ),
            "exactly one artifact",
        )

    def test_rejects_artifact_from_another_run(self):
        self.assert_rejected(
            lambda _, artifacts: artifacts["artifacts"][0]["workflow_run"].update(
                id=RUN_ID + 1),
            "pinned workflow run",
        )

    def test_rejects_missing_digest(self):
        self.assert_rejected(
            lambda _, artifacts: artifacts["artifacts"][0].update(digest=None),
            "valid GitHub SHA-256 digest",
        )


if __name__ == "__main__":
    unittest.main()
