#!/bin/sh
# Resolves Lume's Swift packages into a folder of our own and applies Lume GF's patches to them
# (deps/<Package>/*.patch, made against the commit in deps/<Package>/REVISION). Every later xcodebuild must use that
# folder with automatic resolution off (-clonedSourcePackagesDirPath <dir> -disableAutomaticPackageResolution), or it
# would fetch a clean copy. A Lume release that moves to another commit of a patched package stops the build here,
# before anything is built. Usage: sh apply-dep-patches.sh <our repo dir> <Lume checkout dir> <packages dir>
set -eu
USAGE="usage: apply-dep-patches.sh OURS_DIR LUME_DIR PACKAGES_DIR"
OURS=$(cd "${1:?$USAGE}" && pwd); LUME=$(cd "${2:?$USAGE}" && pwd); SPM="${3:?$USAGE}"
mkdir -p "$SPM"; SPM=$(cd "$SPM" && pwd)
(cd "$LUME" && xcodebuild -resolvePackageDependencies -project Lume.xcodeproj -scheme Lume \
  -clonedSourcePackagesDirPath "$SPM") >/dev/null
n=0
for D in "$OURS"/deps/*/; do
  [ -d "$D" ] || continue
  PKG=$(basename "$D"); CO="$SPM/checkouts/$PKG"
  [ -d "$CO" ] || { echo "apply-dep-patches: $PKG is not among Lume's packages" >&2; exit 1; }
  WANT=$(tr -d ' \n' < "$D/REVISION"); HAVE=$(git -C "$CO" rev-parse HEAD)
  [ "$WANT" = "$HAVE" ] || { echo "apply-dep-patches: Lume now uses $PKG $HAVE; our patches are for $WANT" >&2; exit 1; }
  for P in "$D"*.patch; do
    [ -e "$P" ] || continue
    git -C "$CO" apply --whitespace=nowarn "$P" \
      || { echo "apply-dep-patches: $(basename "$P") does not apply to $PKG" >&2; exit 1; }
    echo "apply-dep-patches: $PKG/$(basename "$P") applied"; n=$((n + 1))
  done
done
echo "apply-dep-patches: $n patch(es) applied"
