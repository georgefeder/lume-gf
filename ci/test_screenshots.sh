#!/bin/sh
# Tests for screenshots.sh with fake xcodebuild, xcrun and plutil (no simulator needed). Usage: sh ci/test_screenshots.sh
set -u
CI=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fails=0
ok() { echo "ok   $1"; }; no() { echo "FAIL $1"; fails=$((fails + 1)); }
mkdir -p "$T/bin" "$T/Lume/Lume.xcodeproj"; LOG="$T/log"; : > "$LOG"; DEAD="$T/dead"; FLASH="$T/flash"
STUCK="$T/stuck"; STUCK_ONCE="$T/stuck-once"  # the simulator's recorder never finishing its file (always, or once)
export LOG DEAD FLASH STUCK STUCK_ONCE
cat > "$T/bin/xcodebuild" <<'EOF'
#!/bin/sh
echo "xcodebuild $*" >> "$LOG"
dd=""; dest=""; prev=""
for a in "$@"; do
  [ "$prev" = "-derivedDataPath" ] && dd="$a"; [ "$prev" = "-destination" ] && dest="$a"; prev="$a"
done
case "$dest" in *TV-1*) sub=appletvsimulator ;; *) sub=iphonesimulator ;; esac
[ -n "$dd" ] && mkdir -p "$dd/Build/Products/Debug-$sub/Lume.app"
exit 0
EOF
cat > "$T/bin/xcrun" <<'EOF'
#!/bin/sh
echo "xcrun $*" >> "$LOG"
[ "$2" = launch ] && echo "launch TZ=$SIMCTL_CHILD_TZ" >> "$LOG"
if [ "$1 $2 $3" = "simctl list devices" ]; then
  echo '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-0":[{"name":"iPhone 17","udid":"IPHONE-1"}],'
  echo '"com.apple.CoreSimulator.SimRuntime.tvOS-26-0":[{"name":"Apple TV 4K (3rd generation)","udid":"TV-1"}]}}'
fi
if [ "$1 $2 $4" = "simctl io recordVideo" ]; then
  for a; do f="$a"; done
  if [ -e "$STUCK" ] || { [ -e "$STUCK_ONCE" ] && rm -f "$STUCK_ONCE"; }; then
    : > "$f"; trap '' INT; i=0; while [ "$i" -lt 120 ]; do sleep 1; i=$((i + 1)); done; exit 0
  fi
  echo film > "$f"; exit 0
fi
[ "$1 $2" = "simctl io" ] && touch "$5"
if [ "$1 $2" = "simctl spawn" ]; then [ -e "$DEAD" ] || echo "123 0 UIKitApplication:lv.test.lume[1234]"; fi
exit 0
EOF
printf '#!/bin/sh\necho lv.test.lume\n' > "$T/bin/plutil"
cat > "$T/bin/swift" <<'EOF'
#!/bin/sh
echo "swift $*" >> "$LOG"
mkdir -p "$3" && echo "frame,seconds,luma" > "$3/luma.csv"
if [ -e "$FLASH" ]; then printf '0,0,0.94\n1,0.1,0.09\n2,0.2,0.53\n3,0.3,0.01\n' >> "$3/luma.csv"; fi
EOF
chmod +x "$T/bin/xcodebuild" "$T/bin/xcrun" "$T/bin/plutil" "$T/bin/swift"
out=$(PATH="$T/bin:$PATH" GF_SHOT_WAIT=0 GF_BOOT_SETTLE=0 GF_FILM_SECONDS=0 GF_DERIVED_DATA="$T/dd" GF_SPM="$T/spm" \
  sh "$CI/screenshots.sh" "$T/Lume" "$T/out" 2>&1) && ok "runs through" || no "runs through ($out)"
grep -qF 'OTHER_SWIFT_FLAGS=$(inherited) -D GF_DEMO' "$LOG" && ok "builds the demo" || no "GF_DEMO missing"
grep -qF -- "-clonedSourcePackagesDirPath $T/spm -disableAutomaticPackageResolution" "$LOG" \
  && ok "builds with our patched packages" || no "patched packages not used"
grep -qF "simctl ui IPHONE-1 appearance dark" "$LOG" && grep -qF "simctl ui IPHONE-1 appearance light" "$LOG" \
  && ok "iPhone in dark and light mode" || no "appearances"
grep -qE "simctl launch .*IPHONE-1 lv.test.lume -ui-testing -GFDemo list" "$LOG" && ok "starts the demo list" || no "list launch"
grep -qE "simctl launch .*TV-1 lv.test.lume -ui-testing -GFDemo guide -GFDemoMoves right" "$LOG" \
  && ok "moves the Apple TV focus" || no "tv moves"
grep -qF "launch TZ=Europe/London" "$LOG" && ok "the app runs on UK time" || no "time zone"
# unsigned builds crash on iCloud at launch; Lume keeps iCloud off under -ui-testing (as its own UI tests do)
[ "$(grep -c "simctl launch " "$LOG")" -eq 23 ] && [ "$(grep "simctl launch " "$LOG" | grep -vc -- " -ui-testing ")" -eq 0 ] \
  && ok "every launch keeps iCloud off" || no "a launch without -ui-testing"
n=0
for f in iphone-guide-dark iphone-list-dark iphone-guide-light iphone-list-light iphone-guide-bottom-dark \
         iphone-guide-few-dark iphone-guide-under-dark iphone-home-dark iphone-home-added-dark iphone-movies-dark \
         iphone-series-dark iphone-guide-landscape-dark tv-guide-channel tv-guide-programme tv-guide-bottom \
         tv-guide-under tv-guide-long tv-home tv-home-added tv-movies tv-list; do
  if [ -f "$T/out/$f.png" ]; then n=$((n + 1)); else no "missing $f.png"; fi
done
[ "$n" -eq 21 ] && ok "twenty-one screenshots" || no "screenshots ($n)"
# for guide-check.py: the guides without the channel column (what the programmes leave under the panel), and the
# Apple TV focused on a six-hour programme after a gap (Georgs' photo of build 9)
grep -qE "simctl launch .*IPHONE-1 lv.test.lume -ui-testing -GFDemo guide -GFDemoNoPanel 1$" "$LOG" \
  && grep -qE "simctl launch .*TV-1 lv.test.lume -ui-testing -GFDemo guide -GFDemoNoPanel 1$" "$LOG" \
  && ok "the guides are photographed without the channel column" || no "no pictures without the column"
# Lume's Home, Movies and Series screens over made-up films and series (Georgs, 2 Oct: posters at different heights,
# the Apple TV's Home showing only the sports row)
grep -qE "simctl launch .*IPHONE-1 lv.test.lume -ui-testing -GFDemo home$" "$LOG" \
  && grep -qE "simctl launch .*IPHONE-1 lv.test.lume -ui-testing -GFDemo movies$" "$LOG" \
  && grep -qE "simctl launch .*IPHONE-1 lv.test.lume -ui-testing -GFDemo series$" "$LOG" \
  && grep -qE "simctl launch .*TV-1 lv.test.lume -ui-testing -GFDemo home$" "$LOG" \
  && grep -qE "simctl launch .*TV-1 lv.test.lume -ui-testing -GFDemo movies$" "$LOG" \
  && ok "Home, Movies and Series are photographed" || no "no pictures of Home, Movies or Series"
# Home's rows below the first screen are never drawn, so a second Home with Recently Watched and Favorites switched off
# (Lume's own Home settings) brings the recently added rows to the top
grep -qE "simctl launch .*IPHONE-1 lv.test.lume -ui-testing -GFDemo home -home.disabledSections.v1 favorites,recentlyWatched$" "$LOG" \
  && grep -qE "simctl launch .*TV-1 lv.test.lume -ui-testing -GFDemo home -home.disabledSections.v1 favorites,recentlyWatched$" "$LOG" \
  && ok "Home is photographed with the recently added rows on top" || no "no picture of the recently added rows"
grep -qE "simctl launch .*TV-1 lv.test.lume -ui-testing -GFDemo guide -GFDemoMoves right,down$" "$LOG" \
  && ok "the Apple TV is photographed focused on the long programme" || no "no picture of the long programme"
grep -qE "simctl launch .*IPHONE-1 lv.test.lume -ui-testing -GFDemo guide -GFDemoMoves landscape" "$LOG" \
  && ok "the iPhone guide is photographed in landscape" || no "no landscape picture"
# the iPhone opening a channel in light mode is filmed (Georgs saw it flash dark), with and without Lume's Light setting
grep -qF "simctl io IPHONE-1 recordVideo" "$LOG" \
  && grep -qE "simctl launch .*IPHONE-1 lv.test.lume -ui-testing -GFDemo list -GFDemoMoves play$" "$LOG" \
  && grep -qE "simctl launch .*IPHONE-1 lv.test.lume -ui-testing -GFDemo list -GFDemoMoves play -app.appearance light" "$LOG" \
  && ok "opening a channel in light mode is filmed" || no "no film of a channel opening"
[ -f "$T/out/film-iphone-open-light/luma.csv" ] && [ -f "$T/out/film-iphone-open-lightsetting/luma.csv" ] \
  && ok "the films' frames and brightness are kept" || no "film frames missing"
printf '%s' "$out" | grep -q "film-check: film-iphone-open-light: " && ok "each film is checked for a flash" \
  || no "films not checked"
grep -qE "exportArchive| archive " "$LOG" && no "must never archive or upload" || ok "never archives or uploads"
printf '%s' "$out" | grep -q "not running" && no "a running app must not be reported gone ($out)" || ok "a running app is photographed"
grep -qF -- "--stdout=$T/out/logs/iphone-guide-dark.out" "$LOG" && ok "the app's own output is kept with the pictures" \
  || no "app output not kept with the pictures"
# a freshly booted iPhone shows first-boot notices (the Apple Intelligence banner covered a picture once)
printf '%s' "$out" | grep -q "screenshots: letting the iPhone settle" && ok "the iPhone settles before its pictures" \
  || no "no settling after boot"
# a film that flashes fails the job (after all pictures are taken)
FLASH="$T/flash"; export FLASH; touch "$FLASH"
out=$(PATH="$T/bin:$PATH" GF_SHOT_WAIT=0 GF_BOOT_SETTLE=0 GF_FILM_SECONDS=0 GF_DERIVED_DATA="$T/dd" \
  sh "$CI/screenshots.sh" "$T/Lume" "$T/out3" 2>&1) && no "a flash must fail the job" || ok "a flash fails the job"
[ -f "$T/out3/tv-list.png" ] && ok "every picture is still taken" || no "pictures missing after a flash"
rm -f "$FLASH"
# the simulator's recorder sometimes never finishes its file (run 37028529816: an empty .mp4, the job held for two
# hours): the film is taken once more; twice empty fails the job after every picture, so no flash check is skipped
shots() {  # $1 = output dir; runs screenshots.sh, gives up after 60 s; prints its output, exit code in $1.rc
  rm -f "$1.rc"
  ( PATH="$T/bin:$PATH" GF_SHOT_WAIT=0 GF_BOOT_SETTLE=0 GF_FILM_SECONDS=0 GF_REC_GRACE=1 GF_DERIVED_DATA="$T/dd" \
      sh "$CI/screenshots.sh" "$T/Lume" "$1" > "$1.txt" 2>&1; echo $? > "$1.rc" ) > /dev/null 2>&1 &
  i=0; while [ ! -e "$1.rc" ] && [ "$i" -lt 60 ]; do sleep 1; i=$((i + 1)); done
  cat "$1.txt" 2>/dev/null
}
touch "$STUCK_ONCE"; out=$(shots "$T/out4")
if [ ! -e "$T/out4.rc" ]; then no "a recorder that never finishes holds the job"
else
  [ "$(cat "$T/out4.rc")" -eq 0 ] && ok "a recorder stuck once: the film is taken again" || no "stuck once ($out)"
  printf '%s' "$out" | grep -q "film-iphone-open-light: the simulator's recorder gave no film (try 1)" \
    && [ -f "$T/out4/film-iphone-open-light/luma.csv" ] && ok "the second take is checked" || no "second take ($out)"
fi
touch "$STUCK"; out=$(shots "$T/out5"); rm -f "$STUCK"
if [ ! -e "$T/out5.rc" ]; then no "a recorder that never finishes holds the job (twice)"
else
  [ "$(cat "$T/out5.rc")" -ne 0 ] && printf '%s' "$out" | grep -q "screenshots: no film of iphone-open-light" \
    && ok "a recorder that gives no film twice fails the job" || no "no film twice ($out)"
  [ -f "$T/out5/tv-list.png" ] && ok "every picture is still taken without a film" || no "pictures missing without a film"
fi
touch "$DEAD"; : > "$LOG"
out=$(HOME="$T/home" PATH="$T/bin:$PATH" GF_SHOT_WAIT=0 GF_BOOT_SETTLE=0 GF_FILM_SECONDS=0 GF_DERIVED_DATA="$T/dd" \
  sh "$CI/screenshots.sh" "$T/Lume" "$T/out2" 2>&1)
printf '%s' "$out" | grep -q "iphone-guide-dark: the app was not running" && ok "an app that died is reported" \
  || no "a dead app goes unreported ($out)"
[ "$fails" -eq 0 ] && echo "test_screenshots: all passed" || echo "test_screenshots: $fails failed"
exit "$fails"
