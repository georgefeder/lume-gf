#!/bin/sh
# Tests for apply-patches.sh, called the way the workflows call it: relative paths from the job's folder
# ("sh gf/ci/apply-patches.sh gf Lume"). Usage: sh ci/test_apply_patches.sh
set -u
CI=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fails=0
ok() { echo "ok   $1"; }; no() { echo "FAIL $1"; fails=$((fails + 1)); }
mkdir -p "$T/gf/patches" "$T/gf/ci" && cp "$CI/apply-patches.sh" "$T/gf/ci/"
git init -q "$T/Lume" && printf 'one\n' > "$T/Lume/a.txt" && git -C "$T/Lume" add a.txt \
  && git -C "$T/Lume" -c user.name=t -c user.email=t@t commit -q -m base
printf 'two\n' > "$T/Lume/a.txt" && git -C "$T/Lume" diff > "$T/gf/patches/0001-test.patch" && git -C "$T/Lume" checkout -q a.txt
out=$(cd "$T" && sh gf/ci/apply-patches.sh gf Lume 2>&1) && ok "relative paths apply" || no "relative paths apply ($out)"
[ "$(cat "$T/Lume/a.txt")" = "two" ] && ok "the patch changed the file" || no "file unchanged"
printf 'nope\n' > "$T/gf/patches/0002-bad.patch"
(cd "$T" && sh gf/ci/apply-patches.sh gf Lume >/dev/null 2>&1) && no "a broken patch must fail" || ok "a broken patch fails"
[ "$fails" -eq 0 ] && echo "test_apply_patches: all passed" || echo "test_apply_patches: $fails failed"
exit "$fails"
