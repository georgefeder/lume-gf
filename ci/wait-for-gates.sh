#!/bin/sh
# Inside a build (GitHub Actions: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT): waits until this
# TestFlight leg may sign for the App Store and upload. The legs archive side by side with the tests and wait only
# here: for the tests job to pass (failed, cancelled, missing, or GitHub not answering for five minutes: exit 1,
# nothing is uploaded), and for each job named in AFTER (one name per line) to finish, so two legs never ask Apple for
# the same profile at once; that wait gives up after GF_AFTER_LIMIT seconds (an hour), so a leg holding the only free
# runner never waits for one queued behind it. The tests are those of this run (the same commit): of this attempt, or
# of the last attempt that ran them when only the failed legs were run again.
# Usage: AFTER="iOS to TestFlight" sh ci/wait-for-gates.sh
set -u
TESTS="Tests before upload"; POLL=${GF_GATE_POLL:-20}; ERRORS=${GF_GATE_ERRORS:-15}; LIMIT=${GF_AFTER_LIMIT:-3600}
ATTEMPT=${GITHUB_RUN_ATTEMPT:-1}
# a job's "status conclusion" in attempt $2, "missing" when it has no such job, "error" when GitHub could not be asked
state() {
  out=$(gh run view "$GITHUB_RUN_ID" -R "$GITHUB_REPOSITORY" --attempt "$2" --json jobs \
        --jq ".jobs[] | select(.name==\"$1\") | .status+\" \"+(.conclusion//\"\")" 2>/dev/null) || { echo error; return; }
  [ -n "$out" ] && echo "$out" || echo missing
}
# the tests' state in the newest attempt, down to the first, that has the tests job
tests_state() {
  a=$ATTEMPT
  while [ "$a" -ge 1 ]; do
    s=$(state "$TESTS" "$a")
    [ "$s" = missing ] || { echo "$s"; return; }
    a=$((a - 1))
  done
  echo missing
}
errors=0
while :; do
  s=$(tests_state)
  case "$s" in
    "completed success") echo "wait-for-gates: the tests passed"; break ;;
    completed*) echo "wait-for-gates: the tests did not pass ($s): nothing is uploaded" >&2; exit 1 ;;
    missing) echo "wait-for-gates: this run has no \"$TESTS\" job: nothing is uploaded" >&2; exit 1 ;;
    error)
      errors=$((errors + 1))
      [ "$errors" -lt "$ERRORS" ] || { echo "wait-for-gates: GitHub did not answer: nothing is uploaded" >&2; exit 1; } ;;
    *) errors=0 ;;
  esac
  sleep "$POLL"
done
start=$(date +%s)
printf '%s\n' "${AFTER:-}" | while IFS= read -r JOB; do
  [ -n "$JOB" ] || continue
  while :; do
    s=$(state "$JOB" "$ATTEMPT")
    case "$s" in
      completed*) echo "wait-for-gates: $JOB finished ($s)"; break ;;
      missing) echo "wait-for-gates: this run has no \"$JOB\" job"; break ;;
    esac
    if [ $(( $(date +%s) - start )) -ge "$LIMIT" ]; then
      echo "::warning::wait-for-gates: $JOB still not finished after $LIMIT s ($s); going on"
      break
    fi
    sleep "$POLL"
  done
done
