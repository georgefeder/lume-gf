#!/bin/sh
# Waits for one job of a "Lume GF tests" run to finish, then prints its test lines (the TDD loop runs on CI).
# Run it in the background. Usage: sh ci/wait-job.sh <run id> "<job name>"
set -u
RID="$1"; JOB="$2"; R=georgefeder/lume-gf; STATE=""
while :; do
  STATE=$(gh run view "$RID" -R "$R" --json jobs --jq ".jobs[] | select(.name==\"$JOB\") | .status+\" \"+(.conclusion//\"\")")
  case "$STATE" in completed*) break ;; esac
  sleep 20
done
ID=$(gh run view "$RID" -R "$R" --json jobs --jq ".jobs[] | select(.name==\"$JOB\") | .databaseId")
gh api --allow-escape-sequences "repos/$R/actions/jobs/$ID/logs" | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -E "✔|✘|error:|Test run with|TEST (SUCCEEDED|FAILED)|test_[a-z_]+: |^ok |^FAIL " \
  | sed -E 's/^[0-9T:.-]*Z //' | tail -80
echo "job: $STATE"
