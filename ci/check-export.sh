#!/bin/sh
# Checks the exported, App Store-signed app before it is uploaded: Lume GF's bundle id and home-screen name, Georgs'
# team in the app id, no debug entitlement, our iCloud container, key-value store and production push in the app
# (never Lume's container), none of them in the extensions, and (iOS) the app group in the app and every extension.
# Usage: sh check-export.sh <export dir> <TEAM_ID> <iOS|tvOS>
set -u
USAGE="usage: check-export.sh EXPORT_DIR TEAM_ID iOS|tvOS"
DIR="${1:?$USAGE}"; TEAM="${2:?$USAGE}"; PLATFORM="${3:?$USAGE}"
PB=/usr/libexec/PlistBuddy; fail=0
bad() { echo "check-export: $*"; fail=1; }
IPA=$(find "$DIR" -maxdepth 1 -name "*.ipa" 2>/dev/null | head -1)
[ -n "$IPA" ] || { echo "check-export: no .ipa in $DIR"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
unzip -q "$IPA" -d "$T"
APP=$(find "$T/Payload" -maxdepth 1 -name "*.app" | head -1)
[ -n "$APP" ] || { echo "check-export: no app in $IPA"; exit 1; }
[ "$($PB -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null)" = "lv.georgefeder.lume" ] \
  || bad "bundle id is not lv.georgefeder.lume"
[ "$($PB -c 'Print :CFBundleDisplayName' "$APP/Info.plist" 2>/dev/null)" = "Lume GF" ] || bad "display name is not 'Lume GF'"
ents() { codesign -d --entitlements - --xml "$1" 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null; }
ents "$APP" | grep -A1 "<key>application-identifier</key>" | grep -q "<string>$TEAM.lv.georgefeder.lume</string>" \
  || bad "application-identifier is not $TEAM.lv.georgefeder.lume"
for B in "$APP" "$APP"/PlugIns/*.appex; do
  [ -d "$B" ] || continue
  N=$(basename "$B"); E=$(ents "$B")
  printf '%s\n' "$E" | grep -A1 "<key>get-task-allow</key>" | grep -q "<true/>" && bad "get-task-allow (debug) set in $N"
  if [ "$B" = "$APP" ]; then
    printf '%s\n' "$E" | grep -q "<string>iCloud.lv.georgefeder.lume</string>" || bad "our iCloud container missing in $N"
    printf '%s\n' "$E" | grep -q "iCloud.bilipp.Lume" && bad "Lume's container in $N"
    printf '%s\n' "$E" | grep -A1 "<key>aps-environment</key>" | grep -q "<string>production</string>" \
      || bad "push is not production in $N"
    printf '%s\n' "$E" | grep -A1 "<key>com.apple.developer.ubiquity-kvstore-identifier</key>" \
      | grep -q "<string>$TEAM.lv.georgefeder.lume</string>" || bad "our key-value store missing in $N"
  else
    printf '%s\n' "$E" | grep -qiE "aps-environment|icloud|ubiquity" && bad "push/iCloud entitlement in $N"
  fi
  if [ "$PLATFORM" = iOS ]; then
    printf '%s\n' "$E" | grep -q "<string>group.lv.georgefeder.lume</string>" || bad "app group missing in $N"
  fi
done
for T in guide.refresh guide.import; do
  $PB -c "Print :BGTaskSchedulerPermittedIdentifiers" "$APP/Info.plist" 2>/dev/null | grep -q "lv.georgefeder.lume.$T" \
    || bad "background task lv.georgefeder.lume.$T not declared"
done
V=$($PB -c 'Print :CFBundleVersion' "$APP/Info.plist" 2>/dev/null)
[ "$fail" -eq 0 ] && echo "check-export: OK - $(basename "$APP") lv.georgefeder.lume build $V, our iCloud$( [ "$PLATFORM" = iOS ] && echo ", app group in the app and its extensions")"
exit "$fail"
