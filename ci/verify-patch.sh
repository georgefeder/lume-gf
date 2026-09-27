#!/bin/sh
# Fails unless this Lume checkout carries Lume GF's identity. Run inside the checkout after gf-patch.sh, before
# archiving, so a Lume release that moved or renamed something stops the build instead of producing a wrong app.
# Usage: sh verify-patch.sh <TEAM_ID>
set -u
TEAM="${1:?usage: verify-patch.sh TEAM_ID}"
PBX="Lume.xcodeproj/project.pbxproj"; PB=/usr/libexec/PlistBuddy; fail=0
bad() { echo "verify-patch: $*"; fail=1; }
grep -q "com.bilipp.lume" "$PBX" && bad "upstream bundle id still in $PBX"
grep -q "PRODUCT_BUNDLE_IDENTIFIER = lv.georgefeder.lume;" "$PBX" || bad "app bundle id lv.georgefeder.lume missing"
grep -q "PRODUCT_BUNDLE_IDENTIFIER = lv.georgefeder.lume.LumeWidgets;" "$PBX" || bad "widget bundle id missing"
grep "DEVELOPMENT_TEAM = " "$PBX" | grep -vq "DEVELOPMENT_TEAM = $TEAM;" && bad "a target still has another team"
grep -q 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "SIDE_LOAD' "$PBX" || bad "Sideload configuration lost its SIDE_LOAD flag"
for E in Lume/Lume.entitlements Lume/Lume-iOS.entitlements; do
  [ -f "$E" ] || { bad "$E missing (Lume moved its entitlements)"; continue; }
  grep -q "icloud" "$E" && bad "iCloud entitlement still in $E"
  grep -q "aps-environment" "$E" && bad "push entitlement still in $E"
done
for F in Lume/Lume-iOS.entitlements LumeWidgets/LumeWidgets.entitlements LumeWidgets/PlaybackActivityAttributes.swift; do
  [ -f "$F" ] || { bad "$F missing"; continue; }
  grep -q "group.com.bilipp.lume" "$F" && bad "upstream app group still in $F"
done
grep -q "group.lv.georgefeder.lume" Lume/Lume-iOS.entitlements || bad "our app group missing in Lume-iOS.entitlements"
[ "$($PB -c 'Print :CFBundleDisplayName' Lume/Info.plist 2>/dev/null)" = "Lume GF" ] || bad "display name is not 'Lume GF'"
$PB -c "Print :UIBackgroundModes" Lume/Info.plist 2>/dev/null | grep -q "remote-notification" && bad "remote-notification background mode still set"
[ "$fail" -eq 0 ] && echo "verify-patch: Lume GF identity OK"
exit "$fail"
