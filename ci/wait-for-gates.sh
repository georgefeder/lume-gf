#!/bin/sh
# Inside a build (GitHub Actions: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT): waits until this
# TestFlight leg may sign for the App Store and upload. The legs archive side by side with the tests and wait only
# here: for the tests job to pass (failed or cancelled: exit 1, nothing is uploaded), and for each job named in AFTER
# (one name per line) to finish, so two legs never ask Apple for the same profile at once.
# Usage: AFTER="iOS to TestFlight" sh ci/wait-for-gates.sh
set -u
TESTS="Tests before upload"; POLL=${GF_GATE_POLL:-20}
# a job's "status conclusion", "missing" when the run has no such job, "error" when GitHub could not be asked
state() {
  out=$(gh run view "$GITHUB_RUN_ID" -R "$GITHUB_REPOSITORY" --attempt "${GITHUB_RUN_ATTEMPT:-1}" --json jobs \
        --jq ".jobs[] | select(.name==\"$1\") | .status+\" \"+(.conclusion//\"\")" 2>/dev/null) || { echo error; return; }
  [ -n "$out" ] && echo "$out" || echo missing
}
while :; do
  s=$(state "$TESTS")
  case "$s" in
    "completed success") echo "wait-for-gates: the tests passed"; break ;;
    completed*) echo "wait-for-gates: the tests did not pass ($s): nothing is uploaded" >&2; exit 1 ;;
    missing) echo "wait-for-gates: this run has no \"$TESTS\" job: nothing is uploaded" >&2; exit 1 ;;
  esac
  sleep "$POLL"
done
printf '%s\n' "${AFTER:-}" | while IFS= read -r JOB; do
  [ -n "$JOB" ] || continue
  while :; do
    s=$(state "$JOB")
    case "$s" in
      completed*) echo "wait-for-gates: $JOB finished ($s)"; break ;;
      missing) echo "wait-for-gates: this run has no \"$JOB\" job"; break ;;
    esac
    sleep "$POLL"
  done
done
