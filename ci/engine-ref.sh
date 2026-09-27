#!/bin/sh
# Prints the LumeEngine tag that Lume's own release workflow pairs with this Lume checkout (the default of ENGINE_REF),
# so our build compiles against exactly the engine the developer released with.
# Usage: sh engine-ref.sh <path to the Lume checkout>
set -eu
F="${1:?usage: engine-ref.sh LUME_DIR}/.github/workflows/sideload-release.yml"
[ -f "$F" ] || { echo "engine-ref: $F not found - Lume changed its release workflow" >&2; exit 1; }
REF=$(sed -nE "s/.*ENGINE_REF:.*'([^']+)'.*/\1/p" "$F" | head -1)
[ -n "$REF" ] || { echo "engine-ref: no ENGINE_REF default in $F - Lume changed its release workflow" >&2; exit 1; }
echo "$REF"
