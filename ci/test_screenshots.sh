#!/bin/sh
# Tests for screenshots.sh with fake xcodebuild, xcrun and plutil (no simulator needed). Usage: sh ci/test_screenshots.sh
set -u
CI=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fails=0
ok() { echo "ok   $1"; }; no() { echo "FAIL $1"; fails=$((fails + 1)); }
mkdir -p "$T/bin" "$T/Lume/Lume.xcodeproj"; LOG="$T/log"; : > "$LOG"; DEAD="$T/dead"; export LOG DEAD
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
[ "$1 $2" = "simctl io" ] && touch "$5"
if [ "$1 $2" = "simctl spawn" ]; then [ -e "$DEAD" ] || echo "123 0 UIKitApplication:lv.test.lume[1234]"; fi
exit 0
EOF
printf '#!/bin/sh\necho lv.test.lume\n' > "$T/bin/plutil"
chmod +x "$T/bin/xcodebuild" "$T/bin/xcrun" "$T/bin/plutil"
out=$(PATH="$T/bin:$PATH" GF_SHOT_WAIT=0 GF_BOOT_SETTLE=0 GF_DERIVED_DATA="$T/dd" GF_SPM="$T/spm" \
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
[ "$(grep -c "simctl launch " "$LOG")" -eq 10 ] && [ "$(grep "simctl launch " "$LOG" | grep -vc -- " -ui-testing ")" -eq 0 ] \
  && ok "every launch keeps iCloud off" || no "a launch without -ui-testing"
n=0
for f in iphone-guide-dark iphone-list-dark iphone-guide-light iphone-list-light iphone-guide-bottom-dark \
         iphone-guide-few-dark tv-guide-channel tv-guide-programme tv-guide-bottom tv-list; do
  if [ -f "$T/out/$f.png" ]; then n=$((n + 1)); else no "missing $f.png"; fi
done
[ "$n" -eq 10 ] && ok "ten screenshots" || no "screenshots ($n)"
grep -qE "exportArchive| archive " "$LOG" && no "must never archive or upload" || ok "never archives or uploads"
printf '%s' "$out" | grep -q "not running" && no "a running app must not be reported gone ($out)" || ok "a running app is photographed"
grep -qF -- "--stdout=" "$LOG" && ok "the app's own output is kept" || no "app output not kept"
# a freshly booted iPhone shows first-boot notices (the Apple Intelligence banner covered a picture once)
printf '%s' "$out" | grep -q "screenshots: letting the iPhone settle" && ok "the iPhone settles before its pictures" \
  || no "no settling after boot"
touch "$DEAD"; : > "$LOG"
out=$(HOME="$T/home" PATH="$T/bin:$PATH" GF_SHOT_WAIT=0 GF_BOOT_SETTLE=0 GF_DERIVED_DATA="$T/dd" \
  sh "$CI/screenshots.sh" "$T/Lume" "$T/out2" 2>&1)
printf '%s' "$out" | grep -q "iphone-guide-dark: the app was not running" && ok "an app that died is reported" \
  || no "a dead app goes unreported ($out)"
[ "$fails" -eq 0 ] && echo "test_screenshots: all passed" || echo "test_screenshots: $fails failed"
exit "$fails"
