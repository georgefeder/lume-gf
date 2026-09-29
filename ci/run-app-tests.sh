#!/bin/sh
# Runs Lume's whole unit test target (LumeTests, including Lume GF's tests copied in by add-sources.sh) on an iOS
# Simulator (Debug, unsigned). Suites in app-tests-skip.txt (intended differences, each with its reason) are skipped.
# Usage: sh run-app-tests.sh <Lume checkout dir>
set -eu
LUME="${1:?usage: run-app-tests.sh LUME_DIR}"; CI=$(cd "$(dirname "$0")" && pwd)
SIM=$(sh "$CI/pick-simulator.sh")
SKIP=""
while IFS= read -r LINE; do
  SUITE=$(printf '%s' "${LINE%%#*}" | tr -d ' ')
  [ -n "$SUITE" ] && SKIP="$SKIP -skip-testing:LumeTests/$SUITE"
done < "$CI/app-tests-skip.txt"
# Lume GF's patched Swift packages (apply-dep-patches.sh), when the workflow set them up
SPMARGS=""
[ -n "${GF_SPM:-}" ] && SPMARGS="-clonedSourcePackagesDirPath $GF_SPM -disableAutomaticPackageResolution"
cd "$LUME"
STATUS=0
# shellcheck disable=SC2086
xcodebuild test -project Lume.xcodeproj -scheme Lume -configuration Debug -destination "id=$SIM" \
  CODE_SIGNING_ALLOWED=NO $SPMARGS -only-testing:LumeTests $SKIP || STATUS=$?
# a test process that dies leaves its remaining tests "failed (0.000 seconds)"; the crash report says why
[ "$STATUS" -eq 0 ] || python3 "$CI/crash-summary.py" 3
exit "$STATUS"
