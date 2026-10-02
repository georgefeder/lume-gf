#!/bin/sh
# Runs Lume's whole unit test target (LumeTests, including Lume GF's tests copied in by add-sources.sh) on an iOS
# Simulator (Debug, unsigned). Suites in app-tests-skip.txt (intended differences, each with its reason) are skipped;
# suites in app-tests-alone.txt (timing tests the parallel run starves) run on their own afterwards, without rebuilding.
# Usage: sh run-app-tests.sh <Lume checkout dir>
set -eu
LUME="${1:?usage: run-app-tests.sh LUME_DIR}"; CI=$(cd "$(dirname "$0")" && pwd)
SIM=$(sh "$CI/pick-simulator.sh")
SKIP=""
while IFS= read -r LINE; do
  SUITE=$(printf '%s' "${LINE%%#*}" | tr -d ' ')
  [ -n "$SUITE" ] && SKIP="$SKIP -skip-testing:LumeTests/$SUITE"
done < "$CI/app-tests-skip.txt"
ALONE=""; ONLY=""
while IFS= read -r LINE; do
  SUITE=$(printf '%s' "${LINE%%#*}" | tr -d ' ')
  [ -n "$SUITE" ] && { ALONE="$ALONE -skip-testing:LumeTests/$SUITE"; ONLY="$ONLY -only-testing:LumeTests/$SUITE"; }
done < "$CI/app-tests-alone.txt"
# Lume GF's patched Swift packages (apply-dep-patches.sh), when the workflow set them up
SPMARGS=""
[ -n "${GF_SPM:-}" ] && SPMARGS="-clonedSourcePackagesDirPath $GF_SPM -disableAutomaticPackageResolution"
RESULT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/lume-app-tests-$$.xcresult"
cd "$LUME"
STATUS=0
# shellcheck disable=SC2086
xcodebuild test -project Lume.xcodeproj -scheme Lume -configuration Debug -destination "id=$SIM" \
  CODE_SIGNING_ALLOWED=NO $SPMARGS -resultBundlePath "$RESULT" -only-testing:LumeTests $SKIP $ALONE || STATUS=$?
# a test process that dies leaves its remaining tests "failed (0.000 seconds)"; the crash report says why
# xcodebuild says which Swift Testing test failed, the result bundle says why
[ "$STATUS" -eq 0 ] || { python3 "$CI/failure-summary.py" "$RESULT" || true; python3 "$CI/crash-summary.py" 3 || true; }
if [ -n "$ONLY" ]; then
  ARESULT="${RESULT%.xcresult}-alone.xcresult"; ASTATUS=0
  # shellcheck disable=SC2086
  xcodebuild test-without-building -project Lume.xcodeproj -scheme Lume -configuration Debug -destination "id=$SIM" \
    CODE_SIGNING_ALLOWED=NO $SPMARGS -resultBundlePath "$ARESULT" $ONLY || ASTATUS=$?
  [ "$ASTATUS" -eq 0 ] \
    || { python3 "$CI/failure-summary.py" "$ARESULT" || true; python3 "$CI/crash-summary.py" 3 || true; }
  [ "$STATUS" -ne 0 ] || STATUS=$ASTATUS
fi
exit "$STATUS"
