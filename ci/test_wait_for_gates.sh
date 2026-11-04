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
[ -e "$JOBS/fail" ] && exit 1
[ -e "$JOBS/$name" ] && cat "$JOBS/$name"
exit 0
GH
chmod +x "$T/bin/gh"
run() { PATH="$T/bin:$PATH" JOBS="$T/jobs" GF_GATE_POLL=0.1 GITHUB_RUN_ID=1 GITHUB_REPOSITORY=r \
  AFTER="$1" sh "$CI/wait-for-gates.sh" 2>&1; }
reset() { rm -f "$T/jobs"/*; }

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

[ "$fails" -eq 0 ] && echo "test_wait_for_gates: all passed" || echo "test_wait_for_gates: $fails failed"
exit "$fails"
