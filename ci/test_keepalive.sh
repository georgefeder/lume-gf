#!/bin/sh
# Test for the check workflow's keep-alive step: it commits only when the newest commit is more than 20 days old
# (the check runs every 6 hours; a commit starts a build). Needs git and ruby (for YAML).
# Usage: sh ci/test_keepalive.sh
CI=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fails=0
ruby -ryaml -e 'puts YAML.load_file(ARGV[0])["jobs"]["check"]["steps"].find { |s| s["name"] == "Keep-alive commit" }["run"]' \
  "$CI/../.github/workflows/lume-gf-check.yml" > "$T/step.sh" || { echo "FAIL keep-alive step not found"; exit 1; }
setup() {  # $1 = age of the newest commit in days
  rm -rf "$T/r" "$T/o.git"; git init -q --bare "$T/o.git"; git clone -q "$T/o.git" "$T/r" 2>/dev/null
  cd "$T/r" && git config user.name t && git config user.email t@t && echo x > f && git add f
  D=$(( $(date +%s) - $1 * 86400 ))
  GIT_AUTHOR_DATE="@$D" GIT_COMMITTER_DATE="@$D" git commit -q -m base && git push -q origin HEAD 2>/dev/null
}
count() { git -C "$T/o.git" rev-list --count HEAD; }
setup 3;  (cd "$T/r" && sh "$T/step.sh"); [ "$(count)" = 1 ] && echo "ok   3-day-old commit: no keep-alive" || { echo "FAIL 3 days: $(count) commits"; fails=1; }
setup 25; (cd "$T/r" && sh "$T/step.sh"); [ "$(count)" = 2 ] && echo "ok   25-day-old commit: one keep-alive pushed" || { echo "FAIL 25 days: $(count) commits"; fails=1; }
[ "$fails" -eq 0 ] && echo "test_keepalive: all passed"
exit $fails
