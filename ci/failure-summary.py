#!/usr/bin/env python3
"""Prints each failing test and its message from an Xcode result bundle — xcodebuild's own output only says which
Swift Testing test failed, not why. Used by run-app-tests.sh after a failed test run.
Usage: failure-summary.py <result.xcresult>   (or --json <file> with xcresulttool's summary, for the tests)"""
import json, subprocess, sys

if len(sys.argv) == 3 and sys.argv[1] == "--json":
    summary = json.load(open(sys.argv[2]))
else:
    try:
        out = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", sys.argv[1]],
                             capture_output=True, text=True, check=True).stdout
        summary = json.loads(out)
    except (subprocess.CalledProcessError, ValueError, IndexError) as error:
        print("failure-summary: no readable result bundle (%s)" % error)
        sys.exit(0)
failures = summary.get("testFailures") or []
if not failures:
    print("failure-summary: no test failures recorded")
for failure in failures:
    name = failure.get("testIdentifierString") or failure.get("testName") or "?"
    text = " ".join(str(failure.get("failureText", "")).split())
    print("failed: %s\n   %s" % (name, text[:1500]))
