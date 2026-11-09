#!/bin/sh
# Prints the LumeEngine tag that Lume's own release paired with this Lume checkout, so our build compiles against
# exactly the engine the developer released with. With RECORDER as the second argument, the LumeRecorder tag instead
# (Lume 2.4's recording kit); with CLOUD, the LumeCloud ref (Lume 3.0's Lume Cloud client). A Lume without the one
# asked for prints nothing.
# Up to Lume 3.0 the pairing was the default of ENGINE_REF / RECORDER_REF / CLOUD_REF in Lume's sideload release
# workflow. Lume 3.1 deleted that workflow (its releases carry source only), so a checkout without it reads
# ci/paired-refs.txt by the checkout's version (MARKETING_VERSION); a version not listed there yet takes the newest
# line's refs, with a warning: Lume kept its recorder at v0.1.1 while LumeRecorder tagged v0.3.1, so "each repo's
# newest tag" would be wrong.
# Usage: sh engine-ref.sh <path to the Lume checkout> [ENGINE|RECORDER|CLOUD]
set -eu
LUME="${1:?usage: engine-ref.sh LUME_DIR [ENGINE|RECORDER|CLOUD]}"
WHICH="${2:-ENGINE}"
F="$LUME/.github/workflows/sideload-release.yml"
if [ -f "$F" ]; then
  REF=$(sed -nE "s/.*${WHICH}_REF:.*'([^']+)'.*/\1/p" "$F" | head -1)
  if [ -z "$REF" ]; then
    [ "$WHICH" = ENGINE ] || exit 0
    echo "engine-ref: no ${WHICH}_REF default in $F - Lume changed its release workflow" >&2; exit 1
  fi
  echo "$REF"; exit 0
fi

PINS="$(cd "$(dirname "$0")" && pwd)/paired-refs.txt"
[ -f "$PINS" ] || { echo "engine-ref: $PINS missing" >&2; exit 1; }
PBX="$LUME/Lume.xcodeproj/project.pbxproj"
VERSION=$(sed -nE 's/.*MARKETING_VERSION = ([0-9][0-9.]*);.*/\1/p' "$PBX" 2>/dev/null | sort -u | tail -1)
[ -n "$VERSION" ] || { echo "engine-ref: no MARKETING_VERSION in $PBX - Lume changed its project" >&2; exit 1; }
LINE=$(grep -E "^v$VERSION( |$)" "$PINS" | head -1 || true)
if [ -z "$LINE" ]; then
  LINE=$(grep -E '^v[0-9]' "$PINS" | tail -1)
  [ -n "$LINE" ] || { echo "engine-ref: no release listed in $PINS" >&2; exit 1; }
  echo "::warning::engine-ref: Lume $VERSION is not in ci/paired-refs.txt; using ${LINE%% *}'s refs" >&2
fi
REF=$(printf '%s\n' "$LINE" | tr ' ' '\n' | sed -n "s/^${WHICH}=//p" | head -1)
if [ -z "$REF" ]; then
  [ "$WHICH" = ENGINE ] || exit 0
  echo "engine-ref: no ENGINE= for ${LINE%% *} in $PINS" >&2; exit 1
fi
echo "$REF"
