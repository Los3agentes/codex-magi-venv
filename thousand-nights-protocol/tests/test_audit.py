import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from audit_runtime import normalize, manifest_names, export


class AuditTests(unittest.TestCase):
    def test_normalization(self):
        self.assertEqual(normalize("PyYAML"), "pyyaml")
        self.assertEqual(normalize("my_package.name"), "my-package-name")

    def test_manifest(self):
        with tempfile.TemporaryDirectory() as t:
            f = Path(t) / "req.txt"
            f.write_text("# ignored\nNumPy\nscipy>=1.0\nfoo[bar]==1.2; python_version >= '3.12'\n", encoding="utf-8")
            self.assertEqual(manifest_names(f), ["NumPy", "scipy", "foo"])

    def test_export(self):
        with tempfile.TemporaryDirectory() as t:
            out = Path(t)
            f = out / "req.txt"
            f.write_text("pip\naaaaaa-nonexistent-package-xxxx\n", encoding="utf-8")
            r = export("before", out, f)
            self.assertEqual(r["manifest_entries"], 2)
            self.assertEqual(r["target_missing"], 1)
            self.assertTrue((out / "audit_before.json").exists())
            r = export("after", out, f)
            self.assertEqual(r["manifest_entries"], 2)
            self.assertTrue((out / "dependency_edges.csv").exists())
            self.assertTrue((out / "changes.json").exists())

if __name__ == "__main__":
    unittest.main()
