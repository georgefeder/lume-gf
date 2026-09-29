#!/usr/bin/env python3
"""Prints the gist of the newest crash reports (.ips) on this Mac: process, exception, termination reason and the top
of the crashed thread. Used by run-app-tests.sh after a failed test run. Usage: crash-summary.py [max reports]"""
import glob, json, os, sys
limit = int(sys.argv[1]) if len(sys.argv) > 1 else 3
paths = sorted(glob.glob(os.path.expanduser("~/Library/Logs/DiagnosticReports/*.ips")), key=os.path.getmtime, reverse=True)
if not paths:
    print("crash-summary: no crash reports")
for path in paths[:limit]:
    text = open(path, errors="replace").read()
    header, _, body = text.partition("\n")
    try:
        report = json.loads(body)
    except ValueError:
        print("crash-summary: %s (unreadable)" % os.path.basename(path)); continue
    print("== %s: %s" % (os.path.basename(path), report.get("procName") or json.loads(header).get("app_name")))
    print("   exception:", json.dumps(report.get("exception")))
    if report.get("termination"): print("   termination:", json.dumps(report.get("termination"))[:400])
    if report.get("asi"): print("   info:", json.dumps(report.get("asi"))[:600])
    images = report.get("usedImages") or []
    threads = report.get("threads") or []
    fault = report.get("faultingThread", 0)
    if fault < len(threads):
        for frame in threads[fault].get("frames", [])[:18]:
            image = images[frame["imageIndex"]].get("name", "?") if frame.get("imageIndex", -1) < len(images) else "?"
            print("   %-22s %s" % (image[:22], frame.get("symbol", "?")[:150]))
