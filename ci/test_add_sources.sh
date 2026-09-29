#!/bin/sh
# Tests for add-sources.sh on a fake repo and a fake Lume checkout. Usage: sh ci/test_add_sources.sh
set -u
CI=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fails=0
ok() { echo "ok   $1"; }; no() { echo "FAIL $1"; fails=$((fails + 1)); }
mkdir -p "$T/ours/guide/Sources/GuideCore" "$T/ours/app/Guide" "$T/ours/app/GuideTests" \
         "$T/lume/Lume/Services/Sync" "$T/lume/LumeTests"
echo "// a" > "$T/ours/guide/Sources/GuideCore/A.swift"; echo "// b" > "$T/ours/app/Guide/B.swift"
echo "// t" > "$T/ours/app/GuideTests/TTests.swift"; touch "$T/ours/app/Guide/.keep"
out=$(sh "$CI/add-sources.sh" "$T/ours" "$T/lume" 2>&1) && ok "copies into a Lume checkout" || no "copies ($out)"
[ -f "$T/lume/Lume/Services/Sync/Guide/A.swift" ] && [ -f "$T/lume/Lume/Services/Sync/Guide/B.swift" ] \
  && ok "app files land in Lume/Services/Sync/Guide" || no "app files missing"
[ -f "$T/lume/LumeTests/Guide/TTests.swift" ] && ok "tests land in LumeTests/Guide" || no "tests missing"
[ ! -e "$T/lume/Lume/Services/Sync/Guide/.keep" ] && ok "only .swift files are copied" || no ".keep copied"
printf '%s' "$out" | grep -q "2 app file(s), 1 test file(s)" && ok "reports the counts" || no "counts ($out)"
sh "$CI/add-sources.sh" "$T/ours" "$T/lume" >/dev/null 2>&1 && no "a second copy (name clash) must fail" \
  || ok "a name clash fails"
rm -rf "$T/lume2"; mkdir -p "$T/lume2/LumeTests"
sh "$CI/add-sources.sh" "$T/ours" "$T/lume2" >/dev/null 2>&1 && no "missing Lume/Services/Sync must fail" \
  || ok "a moved sync folder fails"
[ "$fails" -eq 0 ] && echo "test_add_sources: all passed" || echo "test_add_sources: $fails failed"
exit "$fails"
