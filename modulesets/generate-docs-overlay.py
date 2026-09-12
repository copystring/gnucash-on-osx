#!/usr/bin/env python3
"""Create a pinned GnuCash documentation module overlay for JHBuild."""

import argparse
import copy
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


REPOSITORY_RE = re.compile(
    r"[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*\Z"
)
COMMIT_RE = re.compile(r"[0-9a-f]{40}\Z")


def parse_arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base_moduleset", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("docs_repository")
    parser.add_argument("docs_ref")
    return parser.parse_args()


def validate_pin(repository, revision):
    if bool(repository) != bool(revision):
        raise ValueError("docs_repository and docs_ref must both be blank or supplied")
    if not repository:
        return False
    if not REPOSITORY_RE.fullmatch(repository):
        raise ValueError("docs_repository must be a GitHub owner/repository name")
    if not COMMIT_RE.fullmatch(revision):
        raise ValueError("docs_ref must be a full lowercase 40-character commit SHA")
    return True


def find_docs_module(moduleset):
    modules = [
        module
        for module in moduleset
        if module.tag == "cmake" and module.get("id") == "gnucash-docs"
    ]
    if len(modules) != 1:
        raise ValueError("base moduleset must contain exactly one cmake gnucash-docs module")
    return modules[0]


def create_overlay(base_moduleset, repository, revision):
    base_root = ET.parse(base_moduleset).getroot()
    docs_module = copy.deepcopy(find_docs_module(base_root))
    branches = [child for child in docs_module if child.tag == "branch"]
    if len(branches) != 1:
        raise ValueError("gnucash-docs must contain exactly one branch")

    old_branch = branches[0]
    position = list(docs_module).index(old_branch)
    docs_module.remove(old_branch)
    docs_module.insert(
        position,
        ET.Element(
            "branch",
            {
                "repo": "github",
                "module": f"{repository}.git",
                "tag": revision,
                "checkoutdir": "gnucash-docs",
            },
        ),
    )

    overlay = ET.Element("moduleset")
    ET.SubElement(
        overlay,
        "repository",
        {"type": "git", "name": "github", "href": "https://github.com/"},
    )
    overlay.append(docs_module)
    return ET.ElementTree(overlay)


def main():
    arguments = parse_arguments()
    try:
        pinned = validate_pin(arguments.docs_repository, arguments.docs_ref)
        if not pinned:
            if arguments.output.exists():
                raise ValueError(
                    f"refusing to use existing overlay without a documentation pin: "
                    f"{arguments.output}"
                )
            return 0
        overlay = create_overlay(
            arguments.base_moduleset,
            arguments.docs_repository,
            arguments.docs_ref,
        )
        ET.indent(overlay, space="  ")
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        with arguments.output.open("xb") as output:
            overlay.write(output, encoding="utf-8", xml_declaration=True)
    except FileExistsError:
        print(f"docs overlay: refusing to overwrite existing overlay: {arguments.output}",
              file=sys.stderr)
        return 2
    except (ET.ParseError, OSError, ValueError) as error:
        print(f"docs overlay: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
