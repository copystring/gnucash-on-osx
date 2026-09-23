#!/usr/bin/env python3

"""Validate a pinned GitHub Actions run and one of its artifacts."""

import argparse
import json
import re
from pathlib import Path


SHA_PATTERN = re.compile(r"[0-9a-f]{40}")
DIGEST_PATTERN = re.compile(r"sha256:([0-9a-f]{64})")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(run, artifacts, expected):
    require(str(run.get("id")) == str(expected.run_id),
            "producer run ID does not match the pinned run")
    repository = run.get("repository") or {}
    require(repository.get("full_name") == expected.repository,
            "producer repository does not match the pinned repository")
    require(run.get("path") == expected.workflow,
            "producer workflow does not match the pinned workflow")
    require(SHA_PATTERN.fullmatch(expected.head_sha or "") is not None,
            "expected producer head SHA must be 40 lowercase hexadecimal characters")
    require(run.get("head_sha") == expected.head_sha,
            "producer head SHA does not match the pinned commit")
    require(run.get("status") == "completed",
            "producer workflow run is not completed")
    require(run.get("conclusion") == "success",
            "producer workflow run did not complete successfully")

    listed = artifacts.get("artifacts", [])
    require(artifacts.get("total_count") == 1 and len(listed) == 1,
            "expected the pinned run to expose exactly one artifact")
    matching = [
        artifact for artifact in listed
        if artifact.get("name") == expected.artifact_name
    ]
    require(len(matching) == 1,
            "expected exactly one artifact with the pinned name")
    artifact = matching[0]
    require(isinstance(artifact.get("id"), int) and artifact["id"] > 0,
            "artifact is missing a valid ID")
    require(artifact.get("expired") is False,
            "pinned artifact is expired")

    workflow_run = artifact.get("workflow_run") or {}
    require(workflow_run.get("id") == run.get("id"),
            "artifact does not belong to the pinned workflow run")
    require(workflow_run.get("head_sha") == expected.head_sha,
            "artifact head SHA does not match the pinned commit")
    if repository.get("id") is not None:
        require(workflow_run.get("repository_id") == repository.get("id"),
                "artifact repository does not match the pinned producer")

    digest_match = DIGEST_PATTERN.fullmatch(artifact.get("digest") or "")
    require(digest_match is not None,
            "artifact is missing a valid GitHub SHA-256 digest")
    download_url = artifact.get("archive_download_url")
    expected_download_url = (
        f"https://api.github.com/repos/{expected.repository}/actions/artifacts/"
        f"{artifact['id']}/zip"
    )
    require(download_url == expected_download_url,
            "artifact download URL does not belong to the pinned producer")

    return {
        "artifact_id": str(artifact.get("id")),
        "artifact_download_url": download_url,
        "artifact_sha256": digest_match.group(1),
    }


def load_json(path):
    with Path(path).open(encoding="utf-8") as source:
        return json.load(source)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-json", required=True)
    parser.add_argument("--artifacts-json", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--workflow", required=True)
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--artifact-name", required=True)
    parser.add_argument("--github-output")
    arguments = parser.parse_args()

    outputs = validate(
        load_json(arguments.run_json),
        load_json(arguments.artifacts_json),
        arguments,
    )
    rendered = "".join(f"{key}={value}\n" for key, value in outputs.items())
    if arguments.github_output:
        with Path(arguments.github_output).open("a", encoding="utf-8") as output:
            output.write(rendered)
    else:
        print(rendered, end="")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"GitHub Actions artifact verification error: {error}")
        raise SystemExit(1)
