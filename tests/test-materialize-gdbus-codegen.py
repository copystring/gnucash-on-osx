#!/usr/bin/env python3

import hashlib
import importlib.util
from pathlib import Path
import unittest


REPOSITORY = Path(__file__).resolve().parent.parent
SCRIPT = REPOSITORY / "materialize-gdbus-codegen.py"
SPEC = importlib.util.spec_from_file_location("materialize_gdbus_codegen", SCRIPT)
MATERIALIZER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MATERIALIZER)


class MaterializeGdbusCodegenTests(unittest.TestCase):
    def test_materializes_only_upstream_template_placeholders(self):
        template = b"#!@PYTHON@\npath = '@DATADIR@'\n"
        output = MATERIALIZER.materialize(
            template, hashlib.sha256(template).hexdigest(),
            "/prefix/bin/python3", "/prefix/share")
        self.assertEqual(
            output, b"#!/prefix/bin/python3\npath = '/prefix/share'\n")

    def test_rejects_wrong_source_hash(self):
        with self.assertRaisesRegex(ValueError, "template SHA-256 mismatch"):
            MATERIALIZER.materialize(
                b"#!@PYTHON@\n@DATADIR@\n", "0" * 64,
                "/prefix/bin/python3", "/prefix/share")

    def test_rejects_unknown_template_placeholder(self):
        template = b"#!@PYTHON@\n@DATADIR@\n@UNKNOWN@\n"
        with self.assertRaisesRegex(ValueError, "unsubstituted placeholders"):
            MATERIALIZER.materialize(
                template, hashlib.sha256(template).hexdigest(),
                "/prefix/bin/python3", "/prefix/share")


if __name__ == "__main__":
    unittest.main()
