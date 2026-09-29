#!/bin/sh
# Prints the id of an available simulator on the newest runtime of a platform (for xcodebuild -destination id=...):
# an iPhone for iOS (the default), an Apple TV for tvOS. Usage: sh pick-simulator.sh [iOS|tvOS]
set -eu
PLATFORM="${1:-iOS}"
case "$PLATFORM" in iOS) DEVICE=iPhone ;; tvOS) DEVICE="Apple TV" ;; *) echo "pick-simulator: iOS or tvOS" >&2; exit 2 ;; esac
xcrun simctl list devices available --json | PLATFORM="$PLATFORM" DEVICE="$DEVICE" python3 -c '
import json, os, re, sys
platform, device = os.environ["PLATFORM"], os.environ["DEVICE"]
key = platform + "-"
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    return [int(n) for n in re.findall(r"\d+", runtime.split(key)[-1])] if key in runtime else []
for runtime in sorted(devices, key=version, reverse=True):
    if key not in runtime:
        continue
    for d in devices[runtime]:
        if d["name"].startswith(device):
            print(d["udid"]); sys.exit(0)
sys.exit("pick-simulator: no available " + device + " simulator")'
