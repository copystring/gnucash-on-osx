#!/usr/bin/env python3

import importlib.util
from pathlib import Path
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parent.parent
SCRIPT = REPOSITORY / "verify-gtk4-refresh-gir-closure.py"
SPEC = importlib.util.spec_from_file_location("verify_gtk4_refresh_gir_closure", SCRIPT)
VERIFIER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFIER)


class GirClosureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.prefix = Path(self.temporary.name)
        self.girs = self.prefix / "share" / "gir-1.0"
        self.typelibs = self.prefix / "lib" / "girepository-1.0"
        self.girs.mkdir(parents=True)
        self.typelibs.mkdir(parents=True)

    def tearDown(self):
        self.temporary.cleanup()

    def install_namespace(self, name, version, includes=()):
        include_xml = "".join(
            f'<include name="{include_name}" version="{include_version}"/>'
            for include_name, include_version in includes)
        identity = f"{name}-{version}"
        (self.girs / f"{identity}.gir").write_text(
            '<?xml version="1.0"?>'
            '<repository xmlns="http://www.gtk.org/introspection/core/1.0" version="1.2">'
            f'{include_xml}<namespace name="{name}" version="{version}"/>'
            '</repository>', encoding="utf-8")
        (self.typelibs / f"{identity}.typelib").write_bytes(b"compiled-fixture")

    def test_recursive_gir_and_typelib_closure(self):
        self.install_namespace("Root", "1.0", (("GObject", "2.0"),))
        self.install_namespace("GObject", "2.0", (("GLib", "2.0"),))
        self.install_namespace("GLib", "2.0")
        closure = VERIFIER.verify_closure(self.prefix, ("Root-1.0",))
        self.assertEqual(closure, {"Root-1.0", "GObject-2.0", "GLib-2.0"})

    def test_missing_transitive_gir_is_rejected(self):
        self.install_namespace("Root", "1.0", (("GObject", "2.0"),))
        with self.assertRaisesRegex(ValueError, "Missing GIR include: GObject-2.0.gir"):
            VERIFIER.verify_closure(self.prefix, ("Root-1.0",))

    def test_missing_compiled_typelib_is_rejected(self):
        self.install_namespace("Root", "1.0")
        (self.typelibs / "Root-1.0.typelib").unlink()
        with self.assertRaisesRegex(ValueError, "Missing compiled typelib: Root-1.0.typelib"):
            VERIFIER.verify_closure(self.prefix, ("Root-1.0",))

    def test_declared_namespace_must_match_filename(self):
        self.install_namespace("Other", "1.0")
        (self.girs / "Root-1.0.gir").write_bytes(
            (self.girs / "Other-1.0.gir").read_bytes())
        (self.typelibs / "Root-1.0.typelib").write_bytes(b"compiled-fixture")
        with self.assertRaisesRegex(ValueError, "GIR identity mismatch"):
            VERIFIER.verify_closure(self.prefix, ("Root-1.0",))


if __name__ == "__main__":
    unittest.main()
