#!/bin/sh
# Prints the id of an available simulator on the newest runtime of a platform (for xcodebuild -destination id=...):
# an iPhone for iOS (the default), an Apple TV for tvOS. Runtimes newer than the selected Xcode's simulator SDK are
# passed over (the Xcode 27 image also carries the next Xcode's beta runtimes). Usage: sh pick-simulator.sh [iOS|tvOS]
set -eu
PLATFORM="${1:-iOS}"
case "$PLATFORM" in iOS) DEVICE=iPhone; SDK=iphonesimulator ;; tvOS) DEVICE="Apple TV"; SDK=appletvsimulator ;;
  *) echo "pick-simulator: iOS or tvOS" >&2; exit 2 ;; esac
MAX=$(xcrun --sdk "$SDK" --show-sdk-version 2>/dev/null || echo 999)
xcrun simctl list devices available --json | PLATFORM="$PLATFORM" DEVICE="$DEVICE" MAX="$MAX" python3 -c '
import json, os, re, sys
platform, device = os.environ["PLATFORM"], os.environ["DEVICE"]
key = platform + "-"
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    return [int(n) for n in re.findall(r"\d+", runtime.split(key)[-1])] if key in runtime else []
newest = [int(n) for n in re.findall(r"\d+", os.environ["MAX"])] or [999]  # no SDK version: no limit
for runtime in sorted(devices, key=version, reverse=True):
    if key not in runtime or version(runtime) > newest:
        continue
    for d in devices[runtime]:
        if d["name"].startswith(device) and "Duo" not in d["name"]:  # the foldable gets its own shots
            print(d["udid"]); sys.exit(0)
sys.exit("pick-simulator: no available " + device + " simulator")'
