#!/bin/sh
# Uploads the signed archive to TestFlight (xcodebuild -exportArchive with the "upload" destination), trying again
# when the runner's network dropped: builds 104 and 105 lost theirs at the upload ("The Internet connection appears to
# be offline") and each needed a rerun by hand. A later try that App Store Connect answers with "already uploaded"
# means an earlier one got through before its connection broke: that is done, not failed. Any other error stops at
# once. Usage: sh upload-testflight.sh <xcodebuild -exportArchive arguments...>
# UPLOAD_TRIES (default 3) and UPLOAD_PAUSE (seconds between tries, default 30) for tests.
set -u
TRIES="${UPLOAD_TRIES:-3}"; PAUSE="${UPLOAD_PAUSE:-30}"
LOG=$(mktemp); trap 'rm -f "$LOG"' EXIT
n=1
while :; do
  if xcodebuild -exportArchive "$@" >"$LOG" 2>&1; then cat "$LOG"; exit 0; fi
  cat "$LOG"
  if [ "$n" -gt 1 ] && grep -qiE "redundant binary|already been uploaded|bundle version must be higher|has already been used" "$LOG"; then
    echo "upload-testflight: try $n found the build uploaded already (an earlier try got through)"; exit 0
  fi
  # the last one came with the network trouble too: build 105's iPhone signing, fine on its rerun
  if ! grep -qiE "Internet connection appears to be offline|network connection was lost|request timed out|could not connect to the server|connection reset|isn.t in the correct format" "$LOG"; then
    echo "upload-testflight: failed (not the network), no further try" >&2; exit 1
  fi
  [ "$n" -lt "$TRIES" ] || { echo "upload-testflight: the network dropped $n times, giving up" >&2; exit 1; }
  echo "upload-testflight: the network dropped (try $n of $TRIES), again in ${PAUSE}s"
  sleep "$PAUSE"; n=$((n + 1))
done
