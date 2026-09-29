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
cd "$LUME"
# shellcheck disable=SC2086
xcodebuild test -project Lume.xcodeproj -scheme Lume -configuration Debug -destination "id=$SIM" \
  CODE_SIGNING_ALLOWED=NO -only-testing:LumeTests $SKIP
