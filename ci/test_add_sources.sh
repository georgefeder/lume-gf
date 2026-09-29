#!/bin/sh
# Tests for add-sources.sh on a fake repo and a fake Lume checkout. Usage: sh ci/test_add_sources.sh
set -u
CI=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fails=0
ok() { echo "ok   $1"; }; no() { echo "FAIL $1"; fails=$((fails + 1)); }
mkdir -p "$T/ours/guide/Sources/GuideCore" "$T/ours/guide/Sources/LookCore" "$T/ours/app/Guide" \
         "$T/ours/app/GuideTests" "$T/ours/app/Look" "$T/ours/app/LookTests" \
         "$T/lume/Lume/Services/Sync" "$T/lume/Lume/Views" "$T/lume/LumeTests"
echo "// a" > "$T/ours/guide/Sources/GuideCore/A.swift"; echo "// b" > "$T/ours/app/Guide/B.swift"
echo "// t" > "$T/ours/app/GuideTests/TTests.swift"; touch "$T/ours/app/Guide/.keep"
echo "// l" > "$T/ours/guide/Sources/LookCore/GFL.swift"; echo "// v" > "$T/ours/app/Look/GFV.swift"
echo "// lt" > "$T/ours/app/LookTests/GFLTests.swift"; touch "$T/ours/app/Look/.keep"
out=$(sh "$CI/add-sources.sh" "$T/ours" "$T/lume" 2>&1) && ok "copies into a Lume checkout" || no "copies ($out)"
[ -f "$T/lume/Lume/Services/Sync/Guide/A.swift" ] && [ -f "$T/lume/Lume/Services/Sync/Guide/B.swift" ] \
  && ok "guide files land in Lume/Services/Sync/Guide" || no "guide files missing"
[ -f "$T/lume/LumeTests/Guide/TTests.swift" ] && ok "guide tests land in LumeTests/Guide" || no "guide tests missing"
[ -f "$T/lume/Lume/Views/GFLook/GFL.swift" ] && [ -f "$T/lume/Lume/Views/GFLook/GFV.swift" ] \
  && ok "look files land in Lume/Views/GFLook" || no "look files missing"
[ -f "$T/lume/LumeTests/GFLook/GFLTests.swift" ] && ok "look tests land in LumeTests/GFLook" || no "look tests missing"
[ ! -e "$T/lume/Lume/Services/Sync/Guide/.keep" ] && [ ! -e "$T/lume/Lume/Views/GFLook/.keep" ] \
  && ok "only .swift files are copied" || no ".keep copied"
printf '%s' "$out" | grep -q "4 app file(s), 2 test file(s)" && ok "reports the counts" || no "counts ($out)"
sh "$CI/add-sources.sh" "$T/ours" "$T/lume" >/dev/null 2>&1 && no "a second copy (name clash) must fail" \
  || ok "a name clash fails"
mkdir -p "$T/lume3/Lume/Services/Sync" "$T/lume3/Lume/Views/Player" "$T/lume3/LumeTests"
echo "// Lume's own" > "$T/lume3/Lume/Views/Player/GFV.swift"
sh "$CI/add-sources.sh" "$T/ours" "$T/lume3" >/dev/null 2>&1 && no "a file name Lume already uses must fail" \
  || ok "a file name Lume already uses fails"
mkdir -p "$T/lume2/LumeTests" "$T/lume2/Lume/Views"
sh "$CI/add-sources.sh" "$T/ours" "$T/lume2" >/dev/null 2>&1 && no "missing Lume/Services/Sync must fail" \
  || ok "a moved sync folder fails"
mkdir -p "$T/lume4/Lume/Services/Sync" "$T/lume4/LumeTests"
sh "$CI/add-sources.sh" "$T/ours" "$T/lume4" >/dev/null 2>&1 && no "missing Lume/Views must fail" \
  || ok "a moved views folder fails"
[ "$fails" -eq 0 ] && echo "test_add_sources: all passed" || echo "test_add_sources: $fails failed"
exit "$fails"
