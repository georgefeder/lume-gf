#!/bin/sh
# Fails unless this Lume checkout carries Lume GF's identity (ids, team, app group, our iCloud in the app only). Run
# inside the checkout after gf-patch.sh, before archiving, so a Lume release that moved or renamed something stops
# the build instead of producing a wrong app.
# Usage: sh verify-patch.sh <TEAM_ID>
set -u
TEAM="${1:?usage: verify-patch.sh TEAM_ID}"
PBX="Lume.xcodeproj/project.pbxproj"; PB=/usr/libexec/PlistBuddy; fail=0
bad() { echo "verify-patch: $*"; fail=1; }
grep -q "com.bilipp.lume" "$PBX" && bad "upstream bundle id still in $PBX"
grep -q "PRODUCT_BUNDLE_IDENTIFIER = lv.georgefeder.lume;" "$PBX" || bad "app bundle id lv.georgefeder.lume missing"
grep -q "PRODUCT_BUNDLE_IDENTIFIER = lv.georgefeder.lume.LumeWidgets;" "$PBX" || bad "widget bundle id missing"
grep -q "DEVELOPMENT_TEAM = $TEAM;" "$PBX" || bad "no target is set to team $TEAM"
grep "DEVELOPMENT_TEAM = " "$PBX" | grep -vq "DEVELOPMENT_TEAM = $TEAM;" && bad "a target still has another team"
grep -q "name = Sideload;" "$PBX" || bad "no configuration named Sideload any more"
grep -q 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "SIDE_LOAD' "$PBX" || bad "Sideload configuration lost its SIDE_LOAD flag"
# every entitlements file the project names (all targets and platforms)
ENTS=$(sed -nE 's/.*CODE_SIGN_ENTITLEMENTS(\[[^]]*\])?"? = "?([^";]+)"?;.*/\2/p' "$PBX" | sort -u)
[ -n "$ENTS" ] || bad "no entitlements files named in $PBX"
ours=0; cloud=0
while IFS= read -r E; do
  [ -n "$E" ] || continue
  [ -f "$E" ] || { bad "$E missing (named in the project)"; continue; }
  grep -q "iCloud.bilipp.Lume" "$E" && bad "Lume's container still in $E"
  case "$E" in
    Lume/*)
      [ "$($PB -c 'Print :com.apple.developer.icloud-container-identifiers:0' "$E" 2>/dev/null)" = "iCloud.lv.georgefeder.lume" ] \
        || bad "our iCloud container missing in $E"
      $PB -c "Print :com.apple.developer.icloud-services" "$E" 2>/dev/null | grep -q CloudKit || bad "CloudKit missing in $E"
      [ "$($PB -c 'Print :com.apple.developer.ubiquity-kvstore-identifier' "$E" 2>/dev/null)" = "$TEAM.lv.georgefeder.lume" ] \
        || bad "our key-value store missing in $E"
      $PB -c "Print :aps-environment" "$E" >/dev/null 2>&1 || bad "push entitlement missing in $E"
      cloud=1 ;;
    *) grep -qiE "icloud|ubiquity|aps-environment" "$E" && bad "iCloud entitlement in the widgets ($E)" ;;
  esac
  grep -q "group.lv.georgefeder.lume" "$E" && ours=1
done <<EOF
$ENTS
EOF
[ "$ours" -eq 1 ] || bad "our app group group.lv.georgefeder.lume is in no entitlements file"
[ "$cloud" -eq 1 ] || bad "no app entitlements file under Lume/ any more (Lume moved them)"
LEFT=$(grep -rlF --exclude-dir=.git "group.com.bilipp.lume" . | sed 's#^\./##' | tr '\n' ' ')
[ -z "$LEFT" ] || bad "upstream app group still in: $LEFT"
[ "$($PB -c 'Print :CFBundleDisplayName' Lume/Info.plist 2>/dev/null)" = "Lume GF" ] || bad "display name is not 'Lume GF'"
$PB -c "Print :UIBackgroundModes" Lume/Info.plist 2>/dev/null | grep -q "remote-notification" \
  || bad "remote-notification background mode missing (iCloud's change notices need it)"
[ "$fail" -eq 0 ] && echo "verify-patch: Lume GF identity OK"
exit "$fail"
