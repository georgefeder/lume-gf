#!/bin/sh
# Runs Lume GF's app-side tests and Lume's own guide tests on an iOS Simulator (Debug, unsigned).
# Usage: sh run-app-tests.sh <Lume checkout dir>
set -eu
LUME="${1:?usage: run-app-tests.sh LUME_DIR}"; CI=$(cd "$(dirname "$0")" && pwd)
SIM=$(sh "$CI/pick-simulator.sh")
ONLY=""
while IFS= read -r SUITE; do [ -n "$SUITE" ] && ONLY="$ONLY -only-testing:LumeTests/$SUITE"; done < "$CI/app-tests.txt"
cd "$LUME"
# shellcheck disable=SC2086
xcodebuild test -project Lume.xcodeproj -scheme Lume -configuration Debug -destination "id=$SIM" \
  CODE_SIGNING_ALLOWED=NO $ONLY
