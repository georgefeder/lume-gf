#!/bin/sh
# Prints the LumeEngine tag that Lume's own release workflow pairs with this Lume checkout (the default of ENGINE_REF),
# so our build compiles against exactly the engine the developer released with. With RECORDER as the second argument,
# the LumeRecorder tag instead (RECORDER_REF, Lume 2.4's recording kit); a Lume without one prints nothing.
# Usage: sh engine-ref.sh <path to the Lume checkout> [ENGINE|RECORDER]
set -eu
F="${1:?usage: engine-ref.sh LUME_DIR [ENGINE|RECORDER]}/.github/workflows/sideload-release.yml"
WHICH="${2:-ENGINE}"
[ -f "$F" ] || { echo "engine-ref: $F not found - Lume changed its release workflow" >&2; exit 1; }
REF=$(sed -nE "s/.*${WHICH}_REF:.*'([^']+)'.*/\1/p" "$F" | head -1)
if [ -z "$REF" ]; then
  [ "$WHICH" = RECORDER ] && exit 0
  echo "engine-ref: no ${WHICH}_REF default in $F - Lume changed its release workflow" >&2; exit 1
fi
echo "$REF"
