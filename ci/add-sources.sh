#!/bin/sh
# Copies Lume GF's own Swift files into a Lume checkout before building: the pure guide logic
# (guide/Sources/GuideCore) and the app-side code (app/Guide) into the app target, the app-side tests
# (app/GuideTests) into the test target. Lume's Xcode project picks up files in its folders by itself
# (file-system synchronized groups), so no project file is edited.
# Usage: sh add-sources.sh <our repo dir> <Lume checkout dir>
set -eu
OURS="${1:?usage: add-sources.sh OURS_DIR LUME_DIR}"; LUME="${2:?usage: add-sources.sh OURS_DIR LUME_DIR}"
APP="$LUME/Lume/Services/Sync/Guide"; TESTS="$LUME/LumeTests/Guide"
[ -d "$LUME/Lume/Services/Sync" ] || { echo "add-sources: Lume/Services/Sync missing - Lume moved its sync code" >&2; exit 1; }
[ -d "$LUME/LumeTests" ] || { echo "add-sources: LumeTests missing" >&2; exit 1; }
mkdir -p "$APP" "$TESTS"
copy() {  # $1 = destination folder, rest = files
  D="$1"; shift
  for F in "$@"; do
    [ -e "$F" ] || continue
    B=$(basename "$F")
    [ -e "$D/$B" ] && { echo "add-sources: $B already exists in $D" >&2; exit 1; }
    cp "$F" "$D/"
  done
}
copy "$APP" "$OURS"/guide/Sources/GuideCore/*.swift "$OURS"/app/Guide/*.swift
copy "$TESTS" "$OURS"/app/GuideTests/*.swift
n=$(find "$OURS/guide/Sources/GuideCore" "$OURS/app/Guide" -maxdepth 1 -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')
t=$(find "$OURS/app/GuideTests" -maxdepth 1 -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')
echo "add-sources: $n app file(s), $t test file(s) added"
