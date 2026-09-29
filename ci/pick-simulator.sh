#!/bin/sh
# Prints the id of an available iPhone simulator on the newest iOS runtime (for xcodebuild -destination id=...).
set -eu
xcrun simctl list devices available --json | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    return [int(n) for n in re.findall(r"\d+", runtime.split("iOS-")[-1])] if "iOS-" in runtime else []
for runtime in sorted(devices, key=version, reverse=True):
    if "iOS-" not in runtime:
        continue
    for device in devices[runtime]:
        if device["name"].startswith("iPhone"):
            print(device["udid"]); sys.exit(0)
sys.exit("pick-simulator: no available iPhone simulator")'
