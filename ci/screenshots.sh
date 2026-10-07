#!/bin/sh
# Screenshots of Lume GF's look, for review before TestFlight: builds Lume with our changes for the iPhone and Apple
# TV simulators with the demo switched in (-D GF_DEMO: made-up channels; never in a TestFlight build), starts it in
# each state and saves PNGs. Uses our patched Swift packages when GF_SPM is set (apply-dep-patches.sh).
# Usage: sh screenshots.sh <Lume checkout dir> <output dir>
set -eu
LUME="${1:?usage: screenshots.sh LUME_DIR OUT_DIR}"; OUT="${2:?usage: screenshots.sh LUME_DIR OUT_DIR}"
CI=$(cd "$(dirname "$0")" && pwd); LUME=$(cd "$LUME" && pwd); mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
DD="${GF_DERIVED_DATA:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/gf-derived}"; WAIT="${GF_SHOT_WAIT:-15}"
SETTLE="${GF_BOOT_SETTLE:-120}"; FILM="${GF_FILM_SECONDS:-9}"; REC_GRACE="${GF_REC_GRACE:-20}"
REC_PAUSE="${GF_REC_PAUSE:-5}"
LOGS="$OUT/logs"; mkdir -p "$LOGS"; DIED=0; FLASHED=0; NOFILM=0  # the app's own output, kept with the pictures
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

film() {  # $1 = simulator id, $2 = bundle id, $3 = name, rest = launch arguments; films the screen, keeps frames
  SIM="$1"; BID="$2"; NAME="$3"; shift 3
  for TRY in 1 2 3; do
    # the recorder right after the last one gave empty films (Lume 2.3 runs 37217369514, 37221326443): a pause first
    sleep "$REC_PAUSE"
    xcrun simctl terminate "$SIM" "$BID" >/dev/null 2>&1 || true
    SIMCTL_CHILD_TZ=Europe/London xcrun simctl launch --stdout="$LOGS/$NAME.out" --stderr="$LOGS/$NAME.err" \
      "$SIM" "$BID" -ui-testing "$@" >/dev/null
    xcrun simctl io "$SIM" recordVideo --codec=h264 --force "$LOGS/$NAME.mp4" >/dev/null 2>"$LOGS/$NAME.rec.txt" &
    REC=$!
    sleep "$FILM"
    kill -INT "$REC" 2>/dev/null || true
    # the simulator's recorder sometimes never finishes its file (an empty .mp4, and the job held until its time
    # limit): it gets REC_GRACE seconds, then is stopped, and the film is taken once more
    i=0
    while kill -0 "$REC" 2>/dev/null && [ "$i" -lt "$REC_GRACE" ]; do sleep 1; i=$((i + 1)); done
    kill -KILL "$REC" 2>/dev/null || true
    wait "$REC" 2>/dev/null || true
    [ -s "$LOGS/$NAME.mp4" ] && break
    WHY=$(tail -n 1 "$LOGS/$NAME.rec.txt" 2>/dev/null)
    echo "screenshots: film-$NAME: the simulator's recorder gave no film (try $TRY): $WHY"
  done
  if [ ! -s "$LOGS/$NAME.mp4" ]; then
    echo "screenshots: no film of $NAME"; NOFILM=1; return 0
  fi
  # every 1/15 s a small frame and its brightness (luma.csv): a flash shows as a dip
  if swift "$CI/video-frames.swift" "$LOGS/$NAME.mp4" "$OUT/film-$NAME" 15 >&2; then
    echo "screenshots: film-$NAME"
    python3 "$CI/film-check.py" "$OUT/film-$NAME" || FLASHED=1
  else
    echo "screenshots: film-$NAME: no frames"
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
shoot "$IOS" "$BID" iphone-guide-few-dark -GFDemo guide -GFDemoChannels 3
# Lume's Home, Movies and Series over made-up films and series (posters level at the top; Home's rows)
shoot "$IOS" "$BID" iphone-home-dark -GFDemo home
# Home's rows below the first screen are never drawn (Lume builds them as they scroll in): Recently Watched and
# Favorites switched off in Lume's own Home settings bring the recently added rows to the top
shoot "$IOS" "$BID" iphone-home-added-dark -GFDemo home -home.disabledSections.v1 favorites,recentlyWatched
shoot "$IOS" "$BID" iphone-movies-dark -GFDemo movies
shoot "$IOS" "$BID" iphone-series-dark -GFDemo series
# the continue banner over Home (another device played BBC One three minutes ago): at the top, centred
shoot "$IOS" "$BID" iphone-banner-dark -GFDemo banner
# a channel opened in light mode, filmed (Georgs saw the screen flash dark): system light, then Lume's own Light setting
xcrun simctl ui "$IOS" appearance light
film "$IOS" "$BID" iphone-open-light -GFDemo list -GFDemoMoves play
film "$IOS" "$BID" iphone-open-lightsetting -GFDemo list -GFDemoMoves play -app.appearance light
xcrun simctl ui "$IOS" appearance dark
shoot "$IOS" "$BID" iphone-guide-landscape-dark -GFDemo guide -GFDemoMoves landscape  # last: the iPhone stays sideways
xcrun simctl shutdown "$IOS" >/dev/null 2>&1 || true

TV=$(sh "$CI/pick-simulator.sh" tvOS 2>/dev/null) || TV=$(new_tv) \
  || { xcodebuild -downloadPlatform tvOS >&2; TV=$(new_tv); }
APP=$(build "$TV" appletvsimulator); BID=$(start "$TV" "$APP")
xcrun simctl ui "$TV" appearance dark >/dev/null 2>&1 || true
shoot "$TV" "$BID" tv-guide-channel -GFDemo guide
shoot "$TV" "$BID" tv-guide-programme -GFDemo guide -GFDemoMoves right
shoot "$TV" "$BID" tv-guide-bottom -GFDemo guide -GFDemoMoves down,down,down,down,down,down,down,down,down,down,down,right
# the second channel's six-hour programme after "No Programme", focused (Georgs' photo of build 9)
shoot "$TV" "$BID" tv-guide-long -GFDemo guide -GFDemoMoves right,down
shoot "$TV" "$BID" tv-home -GFDemo home
shoot "$TV" "$BID" tv-home-added -GFDemo home -home.disabledSections.v1 favorites,recentlyWatched
shoot "$TV" "$BID" tv-movies -GFDemo movies
shoot "$TV" "$BID" tv-banner -GFDemo banner  # top right, never focusable
shoot "$TV" "$BID" tv-list -GFDemo list
[ "$DIED" -eq 0 ] || python3 "$CI/crash-summary.py" 3 || true
echo "screenshots: done"
# the dark flash Georgs saw on opening a channel must not come back
[ "$FLASHED" -eq 0 ] || { echo "screenshots: the screen flashed when a channel opened (see film-*/luma.csv)"; exit 1; }
# a film the recorder never gave twice is a flash check not done
[ "$NOFILM" -eq 0 ] || { echo "screenshots: the simulator's recorder gave no film twice running (see above)"; exit 1; }
