"""Tests for schema-check.py (unittest; run by the script tests)."""
import os, subprocess, sys, tempfile, unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "schema-check.py")
REQUIRED = """DEFINE SCHEMA

    RECORD TYPE CD_SyncedPlaylist (
        "___recordID" REFERENCE QUERYABLE,
        CD_entityName STRING QUERYABLE,
        CD_password ENCRYPTED STRING,
        CD_name STRING,
        GRANT READ TO "_world"
    );
"""


def run(required, production):
    d = tempfile.mkdtemp()
    a, b = os.path.join(d, "req.ckdb"), os.path.join(d, "prod.ckdb")
    open(a, "w").write(required)
    open(b, "w").write(production)
    return subprocess.run([sys.executable, SCRIPT, a, b], capture_output=True, text=True)


class SchemaCheckTests(unittest.TestCase):
    def test_production_with_everything_passes(self):
        self.assertEqual(run(REQUIRED, REQUIRED).returncode, 0)

    def test_production_with_more_passes(self):
        more = REQUIRED.replace("CD_name STRING,", "CD_name STRING,\n        CD_extra STRING,")
        self.assertEqual(run(REQUIRED, more).returncode, 0)

    def test_a_missing_field_fails_and_says_deploy(self):
        r = run(REQUIRED, REQUIRED.replace("        CD_name STRING,\n", ""))
        self.assertEqual(r.returncode, 1)
        self.assertIn("CD_SyncedPlaylist.CD_name", r.stdout)
        self.assertIn("Deploy Schema Changes", r.stdout)

    def test_a_missing_type_fails(self):
        r = run(REQUIRED, "DEFINE SCHEMA\n")
        self.assertEqual(r.returncode, 1)
        self.assertIn("CD_SyncedPlaylist", r.stdout)

    def test_a_field_of_another_type_fails(self):
        r = run(REQUIRED, REQUIRED.replace("CD_password ENCRYPTED STRING", "CD_password STRING"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("CD_password", r.stdout)


if __name__ == "__main__":
    unittest.main()
