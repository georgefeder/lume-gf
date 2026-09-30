#!/bin/sh
# Waits for one job of a "Lume GF tests" run to finish, then prints its test lines (the TDD loop runs on CI):
# swift test's ✔/✘ lines, compile errors, xcodebuild's failed test cases and a count of passed tests per suite.
# Run it in the background. Usage: sh ci/wait-job.sh <run id> "<job name>"
set -u
RID="$1"; JOB="$2"; R=georgefeder/lume-gf; STATE=""; LOG=$(mktemp)
while :; do
  STATE=$(gh run view "$RID" -R "$R" --json jobs --jq ".jobs[] | select(.name==\"$JOB\") | .status+\" \"+(.conclusion//\"\")")
  case "$STATE" in completed*) break ;; esac
  sleep 20
done
ID=$(gh run view "$RID" -R "$R" --json jobs --jq ".jobs[] | select(.name==\"$JOB\") | .databaseId")
gh api --allow-escape-sequences "repos/$R/actions/jobs/$ID/logs" | sed 's/\x1b\[[0-9;]*m//g; s/^[0-9T:.-]*Z //' > "$LOG"
grep -E "✘|error:|Test run with|TEST (SUCCEEDED|FAILED)|test_[a-z_]+: |^ok |^FAIL |Test case '[^']*' failed|Expectation failed|^screenshots: |^failed: |^   [A-Za-z]" "$LOG" \
  | grep -v "^ *|" | tail -80
grep -E "Test case '.*' passed" "$LOG" | sed -E "s/.*Test case '(.*)' passed.*/\1/" | sort -u \
  | awk -F/ '{c[$1]++} END {for (s in c) printf "passed: %s %d\n", s, c[s]}' | sort
rm -f "$LOG"
echo "job: $STATE"
