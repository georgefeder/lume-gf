#!/bin/sh
# Tests for run-app-tests.sh with fake xcodebuild and xcrun (no simulator needed). Usage: sh ci/test_run_app_tests.sh
set -u
CI=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fails=0
ok() { echo "ok   $1"; }; no() { echo "FAIL $1"; fails=$((fails + 1)); }
mkdir -p "$T/bin" "$T/Lume"; LOG="$T/log"; FAILRUN="$T/failrun"; export LOG FAILRUN
cat > "$T/bin/xcrun" <<'EOF'
#!/bin/sh
echo '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-0":[{"name":"iPhone 17","udid":"IPHONE-1"}]}}'
EOF
cat > "$T/bin/xcodebuild" <<'EOF'
#!/bin/sh
echo "xcodebuild $*" >> "$LOG"
case "$*" in *test-without-building*) run=alone ;; *) run=main ;; esac
# $FAILRUN names the run that fails ("main" or "alone")
[ -e "$FAILRUN" ] && [ "$(cat "$FAILRUN")" = "$run" ] && exit 65
exit 0
EOF
chmod +x "$T/bin/xcrun" "$T/bin/xcodebuild"
run() { : > "$LOG"; PATH="$T/bin:$PATH" RUNNER_TEMP="$T" HOME="$T/home" sh "$CI/run-app-tests.sh" "$T/Lume" >/dev/null 2>&1; }

run && ok "all tests passing passes" || no "all passing must pass"
MAIN=$(grep -v "test-without-building" "$LOG"); ALONE=$(grep "test-without-building" "$LOG")
printf '%s' "$MAIN" | grep -q -- "-only-testing:LumeTests " \
  && printf '%s' "$MAIN" | grep -q -- "-skip-testing:LumeTests/WatchProgressBufferTests" \
  && ok "the whole target runs, the skip list skipped" || no "main run ($MAIN)"
# GFZapTests times a channel change to the second; in the parallel run the switch alone waited ~30 s (runs 37028529816,
# 37037167206), so it runs on its own after the rest
printf '%s' "$MAIN" | grep -q -- "-skip-testing:LumeTests/GFZapTests" && ok "the timing test is left out of the parallel run" \
  || no "GFZapTests still in the parallel run"
printf '%s' "$ALONE" | grep -q -- "-only-testing:LumeTests/GFZapTests" \
  && ! printf '%s' "$ALONE" | grep -q -- "-only-testing:LumeTests " && ok "the timing test runs on its own, without rebuilding" \
  || no "no run of GFZapTests on its own ($ALONE)"
[ "$(grep -n "" "$LOG" | grep "test-without-building" | cut -d: -f1)" = 2 ] && ok "after the parallel run" || no "order"
grep -q "^GFZapTests " "$CI/app-tests-alone.txt" && grep "^GFZapTests " "$CI/app-tests-alone.txt" | grep -q "#" \
  && ok "the suites run on their own are listed with a reason" || no "app-tests-alone.txt"

echo main > "$FAILRUN"
run && no "a failing parallel run must fail" || ok "a failing parallel run fails"
grep -q "test-without-building" "$LOG" && ok "the timing test still runs after a failing parallel run" \
  || no "no run on its own after a failure"
echo alone > "$FAILRUN"
run && no "a failing timing test must fail" || ok "a failing timing test fails"
rm -f "$FAILRUN"

[ "$fails" -eq 0 ] && echo "test_run_app_tests: all passed" || echo "test_run_app_tests: $fails failed"
exit "$fails"
