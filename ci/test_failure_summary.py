"""Tests for failure-summary.py (unittest; run by the build workflow's script tests)."""
import json, os, subprocess, sys, tempfile, unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "failure-summary.py")


def run(summary):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(summary, f)
    try:
        return subprocess.run([sys.executable, SCRIPT, "--json", f.name], capture_output=True, text=True).stdout
    finally:
        os.unlink(f.name)


class FailureSummaryTests(unittest.TestCase):
    def test_prints_each_failing_test_with_its_message(self):
        out = run({"result": "Failed", "testFailures": [
            {"testName": "zap()", "testIdentifierString": "GFZapTests/zap()", "targetName": "LumeTests",
             "failureText": "Expectation failed: oldClosed.time <= nextOpened.time"}]})
        self.assertIn("GFZapTests/zap()", out)
        self.assertIn("Expectation failed: oldClosed.time <= nextOpened.time", out)

    def test_says_so_when_nothing_failed(self):
        self.assertIn("no test failures", run({"result": "Passed", "testFailures": []}))

    def test_long_messages_are_cut(self):
        out = run({"testFailures": [{"testName": "t()", "failureText": "x" * 5000}]})
        self.assertLess(len(out), 2500)


if __name__ == "__main__":
    unittest.main()
