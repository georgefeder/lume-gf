#!/bin/sh
# Tests for wait-for-gates.sh with a fake gh that answers from files (one job's state per file, changed while it
# waits). Usage: sh ci/test_wait_for_gates.sh
CI=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fails=0
ok() { echo "ok   $1"; }; no() { echo "FAIL $1"; fails=$((fails + 1)); }
mkdir -p "$T/bin" "$T/jobs"
cat > "$T/bin/gh" <<'GH'
#!/bin/sh
# the job's name is in the --jq filter: select(.name=="NAME")
name=$(printf '%s' "$*" | sed -n 's/.*select(.name=="\([^"]*\)").*/\1/p')
attempt=$(printf '%s' "$*" | sed -n 's/.*--attempt \([0-9]*\).*/\1/p')
[ -e "$JOBS/fail" ] && exit 1
if [ -d "$JOBS/a$attempt" ]; then [ -e "$JOBS/a$attempt/$name" ] && cat "$JOBS/a$attempt/$name"; exit 0; fi
[ -e "$JOBS/$name" ] && cat "$JOBS/$name"
exit 0
GH
chmod +x "$T/bin/gh"
run() { PATH="$T/bin:$PATH" JOBS="$T/jobs" GF_GATE_POLL=0.1 GITHUB_RUN_ID=1 GITHUB_REPOSITORY=r \
  GITHUB_RUN_ATTEMPT=${ATTEMPT:-1} GF_GATE_ERRORS=${ERRORS:-15} GF_AFTER_LIMIT=${LIMIT:-3600} \
  AFTER="$1" sh "$CI/wait-for-gates.sh" 2>&1; }
reset() { rm -rf "$T/jobs"/*; }

reset; echo "completed success" > "$T/jobs/Tests before upload"
out=$(run "") && ok "passes once the tests passed" || no "passed tests ($out)"

reset; echo "completed failure" > "$T/jobs/Tests before upload"
out=$(run "") && no "failed tests let it upload ($out)" || ok "failed tests stop the upload"
printf '%s' "$out" | grep -q "nothing is uploaded" && ok "says nothing is uploaded" || no "message ($out)"

reset; echo "completed cancelled" > "$T/jobs/Tests before upload"
run "" >/dev/null && no "cancelled tests let it upload" || ok "cancelled tests stop the upload"

reset
out=$(run "") && no "a run without the tests job uploads ($out)" || ok "no tests job: no upload"

# still running, then passing: it waits, then the other leg's upload, then goes on
reset; echo "in_progress " > "$T/jobs/Tests before upload"; echo "in_progress " > "$T/jobs/iOS to TestFlight"
( sleep 1; echo "completed success" > "$T/jobs/Tests before upload"; sleep 1
  echo "completed success" > "$T/jobs/iOS to TestFlight" ) &
start=$(date +%s); out=$(run "iOS to TestFlight"); status=$?; took=$(( $(date +%s) - start )); wait
[ "$status" = 0 ] && [ "$took" -ge 2 ] && ok "waits for the tests, then for the other leg" || no "waiting ($status, ${took}s: $out)"
printf '%s' "$out" | grep -q "iOS to TestFlight finished (completed success)" && ok "names the leg it waited for" \
  || no "leg message ($out)"

# the other leg failed: this one still uploads (its own build is fine)
reset; echo "completed success" > "$T/jobs/Tests before upload"; echo "completed failure" > "$T/jobs/iOS to TestFlight"
run "iOS to TestFlight" >/dev/null && ok "the other leg failing does not stop this one" || no "other leg failed"

# GitHub not answering for a moment: it keeps waiting rather than going on
reset; touch "$T/jobs/fail"; echo "completed success" > "$T/jobs/Tests before upload"
( sleep 1; rm -f "$T/jobs/fail" ) &
start=$(date +%s); run "" >/dev/null; status=$?; took=$(( $(date +%s) - start )); wait
[ "$status" = 0 ] && [ "$took" -ge 1 ] && ok "a moment without GitHub is waited out" || no "gh errors ($status, ${took}s)"

# two jobs of the name (a match on more than one): never a pass
reset; printf 'completed success\ncompleted failure\n' > "$T/jobs/Tests before upload"
run "" >/dev/null && no "two matching jobs let it upload" || ok "two matching jobs: no upload"

# only the failed legs run again (attempt 2 without the tests): the tests of attempt 1, the same commit, count
reset; mkdir -p "$T/jobs/a2" "$T/jobs/a1"; echo "completed success" > "$T/jobs/a1/Tests before upload"
ATTEMPT=2 run "" >/dev/null && ok "a leg run again finds the tests of the attempt before" || no "re-run of a leg"
reset; mkdir -p "$T/jobs/a2" "$T/jobs/a1"; echo "completed failure" > "$T/jobs/a1/Tests before upload"
ATTEMPT=2 run "" >/dev/null && no "re-run uploads after failed tests" || ok "a leg run again after failed tests: no upload"
# the tests run again too: this attempt's count, not the old failure
reset; mkdir -p "$T/jobs/a2" "$T/jobs/a1"; echo "completed failure" > "$T/jobs/a1/Tests before upload"
echo "completed success" > "$T/jobs/a2/Tests before upload"
ATTEMPT=2 run "" >/dev/null && ok "tests run again and passing count" || no "tests re-run"

# GitHub never answering: given up, nothing uploaded
reset; touch "$T/jobs/fail"
ERRORS=3 run "" >/dev/null && no "no answer let it upload" || ok "GitHub not answering: no upload"

# the other leg still queued an hour on (only one runner free): it goes on, with a warning
reset; echo "completed success" > "$T/jobs/Tests before upload"; echo "queued " > "$T/jobs/iOS to TestFlight"
out=$(LIMIT=1 run "iOS to TestFlight") && printf '%s' "$out" | grep -q "going on" && ok "a leg queued behind it is not waited for for ever" \
  || no "other leg queued ($out)"

[ "$fails" -eq 0 ] && echo "test_wait_for_gates: all passed" || echo "test_wait_for_gates: $fails failed"
exit "$fails"
