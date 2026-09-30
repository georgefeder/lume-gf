#!/bin/sh
# Copies Lume GF's own Swift files into a Lume checkout before building: the guide logic (guide/Sources/GuideCore,
# app/Guide) into Lume/Services/Sync/Guide, the look (guide/Sources/LookCore, app/Look) into Lume/Views/GFLook, and
# their tests (app/GuideTests, app/LookTests) into LumeTests/Guide and LumeTests/GFLook. Lume's Xcode project picks up
# files in its folders by itself (file-system synchronized groups), so no project file is edited. Everything lands in
# one module with Lume's own files, where a second file of the same name breaks the build: that stops here instead.
# Usage: sh add-sources.sh <our repo dir> <Lume checkout dir>
set -eu
OURS="${1:?usage: add-sources.sh OURS_DIR LUME_DIR}"; LUME="${2:?usage: add-sources.sh OURS_DIR LUME_DIR}"
[ -d "$LUME/Lume/Services/Sync" ] || { echo "add-sources: Lume/Services/Sync missing - Lume moved its sync code" >&2; exit 1; }
[ -d "$LUME/Lume/Views" ] || { echo "add-sources: Lume/Views missing - Lume moved its views" >&2; exit 1; }
[ -d "$LUME/LumeTests" ] || { echo "add-sources: LumeTests missing" >&2; exit 1; }
copy() {  # $1 = destination folder, rest = files
  D="$1"; shift; mkdir -p "$D"
  for F in "$@"; do
    [ -e "$F" ] || continue
    B=$(basename "$F")
    if [ -n "$(find "$LUME/Lume" "$LUME/LumeTests" -name "$B" -print | head -1)" ]; then
      echo "add-sources: $B already exists in the Lume checkout" >&2; exit 1
    fi
    cp "$F" "$D/"
  done
}
copy "$LUME/Lume/Services/Sync/Guide" "$OURS"/guide/Sources/GuideCore/*.swift "$OURS"/app/Guide/*.swift
copy "$LUME/LumeTests/Guide" "$OURS"/app/GuideTests/*.swift
copy "$LUME/Lume/Views/GFLook" "$OURS"/guide/Sources/LookCore/*.swift "$OURS"/app/Look/*.swift
copy "$LUME/LumeTests/GFLook" "$OURS"/app/LookTests/*.swift
count() { find "$@" -maxdepth 1 -name '*.swift' 2>/dev/null | wc -l | tr -d ' '; }
n=$(count "$OURS/guide/Sources/GuideCore" "$OURS/app/Guide" "$OURS/guide/Sources/LookCore" "$OURS/app/Look")
t=$(count "$OURS/app/GuideTests" "$OURS/app/LookTests")
echo "add-sources: $n app file(s), $t test file(s) added"
