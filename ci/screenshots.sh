#!/bin/sh
# Screenshots of Lume GF's look, for review before TestFlight: builds Lume with our changes for the iPhone and Apple
# TV simulators with the demo switched in (-D GF_DEMO: made-up channels; never in a TestFlight build), starts it in
# each state and saves PNGs. Uses our patched Swift packages when GF_SPM is set (apply-dep-patches.sh).
# Usage: sh screenshots.sh <Lume checkout dir> <output dir>
set -eu
LUME="${1:?usage: screenshots.sh LUME_DIR OUT_DIR}"; OUT="${2:?usage: screenshots.sh LUME_DIR OUT_DIR}"
CI=$(cd "$(dirname "$0")" && pwd); LUME=$(cd "$LUME" && pwd); mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
DD="${GF_DERIVED_DATA:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/gf-derived}"; WAIT="${GF_SHOT_WAIT:-15}"
SETTLE="${GF_BOOT_SETTLE:-120}"
LOGS=$(mktemp -d); DIED=0
SPMARGS=""
[ -n "${GF_SPM:-}" ] && SPMARGS="-clonedSourcePackagesDirPath $GF_SPM -disableAutomaticPackageResolution"

build() {  # $1 = simulator id, $2 = products folder; prints the built .app
  # shellcheck disable=SC2086
  xcodebuild build -project "$LUME/Lume.xcodeproj" -scheme Lume -configuration Debug -destination "id=$1" \
    -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO 'OTHER_SWIFT_FLAGS=$(inherited) -D GF_DEMO' $SPMARGS -quiet >&2
  find "$DD/Build/Products/Debug-$2" -maxdepth 1 -name '*.app' | head -1
}

start() {  # $1 = simulator id, $2 = app; prints the bundle id
  xcrun simctl boot "$1" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$1" -b >/dev/null
  xcrun simctl install "$1" "$2"
  plutil -extract CFBundleIdentifier raw -o - "$2/Info.plist"
}

shoot() {  # $1 = simulator id, $2 = bundle id, $3 = file name, rest = launch arguments
  SIM="$1"; BID="$2"; NAME="$3"; shift 3
  xcrun simctl terminate "$SIM" "$BID" >/dev/null 2>&1 || true
  # -ui-testing: Lume keeps iCloud off (an unsigned build crashes on it at launch), as Lume's own UI tests do
  SIMCTL_CHILD_TZ=Europe/London xcrun simctl launch --stdout="$LOGS/$NAME.out" --stderr="$LOGS/$NAME.err" \
    "$SIM" "$BID" -ui-testing "$@" >/dev/null
  sleep "$WAIT"
  xcrun simctl io "$SIM" screenshot "$OUT/$NAME.png" >/dev/null
  # a picture of the home screen is no picture of Lume: say so, with the app's last words
  if xcrun simctl spawn "$SIM" launchctl list 2>/dev/null | grep -q "UIKitApplication:$BID"; then
    echo "screenshots: $NAME.png"
  else
    echo "screenshots: $NAME: the app was not running"; DIED=1
    tail -n 25 "$LOGS/$NAME.err" "$LOGS/$NAME.out" 2>/dev/null | sed 's/^/   /'
  fi
}

new_tv() {  # an Apple TV simulator on the newest tvOS runtime; prints its id
  RT=$(xcrun simctl list runtimes --json | python3 -c 'import json, sys
r = [x for x in json.load(sys.stdin)["runtimes"] if x.get("platform") == "tvOS" and x.get("isAvailable")]
print(r[-1]["identifier"] if r else "")')
  [ -n "$RT" ] || return 1
  xcrun simctl create "GF Apple TV" "com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K" "$RT"
}

IOS=$(sh "$CI/pick-simulator.sh" iOS)
APP=$(build "$IOS" iphonesimulator); BID=$(start "$IOS" "$APP")
# a freshly booted iPhone shows first-boot notices (the Apple Intelligence banner covered a picture once)
echo "screenshots: letting the iPhone settle ($SETTLE s)"; sleep "$SETTLE"
for LOOK in dark light; do
  xcrun simctl ui "$IOS" appearance "$LOOK"
  shoot "$IOS" "$BID" "iphone-guide-$LOOK" -GFDemo guide
  shoot "$IOS" "$BID" "iphone-list-$LOOK" -GFDemo list
done
xcrun simctl ui "$IOS" appearance dark
shoot "$IOS" "$BID" iphone-guide-bottom-dark -GFDemo guide -GFDemoMoves end
shoot "$IOS" "$BID" iphone-guide-few-dark -GFDemo guide -GFDemoChannels 3
xcrun simctl shutdown "$IOS" >/dev/null 2>&1 || true

TV=$(sh "$CI/pick-simulator.sh" tvOS 2>/dev/null) || TV=$(new_tv) \
  || { xcodebuild -downloadPlatform tvOS >&2; TV=$(new_tv); }
APP=$(build "$TV" appletvsimulator); BID=$(start "$TV" "$APP")
xcrun simctl ui "$TV" appearance dark >/dev/null 2>&1 || true
shoot "$TV" "$BID" tv-guide-channel -GFDemo guide
shoot "$TV" "$BID" tv-guide-programme -GFDemo guide -GFDemoMoves right
shoot "$TV" "$BID" tv-guide-bottom -GFDemo guide -GFDemoMoves down,down,down,down,down,down,down,down,down,down,down,right
shoot "$TV" "$BID" tv-list -GFDemo list
[ "$DIED" -eq 0 ] || python3 "$CI/crash-summary.py" 3 || true
echo "screenshots: done"
