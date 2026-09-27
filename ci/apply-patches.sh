#!/bin/sh
# Applies our changes (patches/*.patch, in name order) to a Lume checkout. A patch that no longer applies to a new
# Lume release stops the build here, before anything is archived or uploaded.
# Usage: sh apply-patches.sh <our repo dir> <Lume checkout dir>
set -eu
OURS="${1:?usage: apply-patches.sh OURS_DIR LUME_DIR}"; LUME="${2:?usage: apply-patches.sh OURS_DIR LUME_DIR}"
n=0
for P in "$OURS"/patches/*.patch; do
  [ -e "$P" ] || continue
  if ! git -C "$LUME" apply --3way --whitespace=nowarn "$P"; then
    echo "apply-patches: $(basename "$P") does not apply to this Lume release" >&2; exit 1
  fi
  echo "apply-patches: $(basename "$P") applied"; n=$((n + 1))
done
echo "apply-patches: $n patch(es) applied"
