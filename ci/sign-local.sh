#!/bin/sh
# Signs the app in an unsigned archive locally (ad hoc) with its entitlements.
# Lume GF archives unsigned, like Lume's own release builds: a normally signed archive would need a development
# certificate made on the runner and, for tvOS, a registered Apple TV, and Xcode refuses ad hoc signing for iOS/tvOS
# builds. The upload step re-signs everything with Apple's cloud-managed distribution certificate and keeps the
# entitlements it finds, so they are put back here (an unsigned archive has none: no app group).
# Usage: sh sign-local.sh <archive> <app entitlements> [<extension name>=<entitlements> ...]
set -eu
USAGE="usage: sign-local.sh ARCHIVE APP_ENTITLEMENTS [EXTENSION=ENTITLEMENTS ...]"
ARCHIVE="${1:?$USAGE}"; APP_ENT="${2:?$USAGE}"; shift 2
APP=$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name "*.app" 2>/dev/null | head -1)
[ -n "$APP" ] && [ -d "$APP" ] || { echo "sign-local: no app in $ARCHIVE" >&2; exit 1; }
[ -f "$APP_ENT" ] || { echo "sign-local: app entitlements '$APP_ENT' not found" >&2; exit 1; }
sign() { codesign --force --sign - --timestamp=none "$@"; }
# 1. frameworks and libraries, innermost first; identifier = the framework's bundle id (as Lume's
#    fix-ksplayer-frameworks.sh does when it signs them, because the upload keeps the identifier)
find "$APP" -depth \( -name "*.framework" -o -name "*.dylib" \) | while IFS= read -r F; do
  B=""; [ -d "$F" ] && B=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$F/Info.plist" 2>/dev/null || true)
  if [ -n "$B" ]; then sign --identifier "$B" "$F"; else sign "$F"; fi
done
# 2. app extensions, each with the entitlements named for it (a new extension in a Lume release stops the build here)
for X in "$APP"/PlugIns/*.appex; do
  [ -d "$X" ] || continue
  N=$(basename "$X" .appex); E=""
  for M in "$@"; do [ "${M%%=*}" = "$N" ] && E="${M#*=}"; done
  [ -n "$E" ] && [ -f "$E" ] || { echo "sign-local: no entitlements given for extension $N" >&2; exit 1; }
  sign --entitlements "$E" "$X"
done
# 3. the app itself
sign --entitlements "$APP_ENT" "$APP"
echo "sign-local: $(basename "$APP") signed locally with $(basename "$APP_ENT")${*:+ ($*)}"
