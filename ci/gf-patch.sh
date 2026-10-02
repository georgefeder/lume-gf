#!/bin/sh
# Applies Lume GF's identity to a Lume checkout at build time (never committed into Lume's files).
# Own bundle ids, team and app group; our own iCloud container, key-value store and push (iCloud's change notices)
# in the app, none in the widgets; home-screen name "Lume GF".
# Usage (inside the checkout): sh gf-patch.sh <TEAM_ID>
set -eu
TEAM="${1:?usage: gf-patch.sh TEAM_ID}"
PBX="Lume.xcodeproj/project.pbxproj"; PB=/usr/libexec/PlistBuddy
UP_ID="com.bilipp.lume"; GF_ID="lv.georgefeder.lume"
UP_GROUP="group.com.bilipp.lume"; GF_GROUP="group.lv.georgefeder.lume"
# 1. bundle ids (app and widget extension) and team, all configurations
sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = ${UP_ID}/PRODUCT_BUNDLE_IDENTIFIER = ${GF_ID}/g" "$PBX"
sed -i '' "s/DEVELOPMENT_TEAM = [A-Z0-9]*;/DEVELOPMENT_TEAM = ${TEAM};/g" "$PBX"
# 2. iCloud and push in every entitlements file the project names (all targets and platforms): Lume's own go
#    everywhere; the app's files (under Lume/) get ours, the extensions (widgets) stay without
sed -nE 's/.*CODE_SIGN_ENTITLEMENTS(\[[^]]*\])?"? = "?([^";]+)"?;.*/\2/p' "$PBX" | sort -u | while IFS= read -r E; do
  [ -f "$E" ] || continue
  for K in aps-environment com.apple.developer.aps-environment \
           com.apple.developer.icloud-container-identifiers com.apple.developer.icloud-services \
           com.apple.developer.icloud-container-environment com.apple.developer.ubiquity-container-identifiers \
           com.apple.developer.ubiquity-kvstore-identifier; do
    $PB -c "Delete :$K" "$E" 2>/dev/null || true
  done
  case "$E" in Lume/*)
    $PB -c "Add :com.apple.developer.icloud-services array" -c "Add :com.apple.developer.icloud-services:0 string CloudKit" \
        -c "Add :com.apple.developer.icloud-container-identifiers array" \
        -c "Add :com.apple.developer.icloud-container-identifiers:0 string iCloud.${GF_ID}" \
        -c "Add :com.apple.developer.ubiquity-kvstore-identifier string ${TEAM}.${GF_ID}" \
        -c "Add :aps-environment string development" "$E" ;;
  esac
done
# 3. our app group, in every file that names Lume's (entitlements, Swift)
grep -rlF --exclude-dir=.git "$UP_GROUP" . | while IFS= read -r F; do sed -i '' "s/${UP_GROUP}/${GF_GROUP}/g" "$F"; done
# 4. home-screen name
plutil -replace CFBundleDisplayName -string "Lume GF" Lume/Info.plist
echo "gf-patch: identity applied (team ${TEAM})"
