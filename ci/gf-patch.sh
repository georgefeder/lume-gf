#!/bin/sh
# Applies Lume GF's identity to a Lume checkout at build time (never committed into Lume's files).
# Own bundle ids, team and app group; no push and no iCloud (they belong to the developer's account; the Sideload
# configuration's SIDE_LOAD flag already keeps CloudKit off); home-screen name "Lume GF".
# Usage (inside the checkout): sh gf-patch.sh <TEAM_ID>
set -eu
TEAM="${1:?usage: gf-patch.sh TEAM_ID}"
PBX="Lume.xcodeproj/project.pbxproj"; PB=/usr/libexec/PlistBuddy
UP_ID="com.bilipp.lume"; GF_ID="lv.georgefeder.lume"
UP_GROUP="group.com.bilipp.lume"; GF_GROUP="group.lv.georgefeder.lume"
# 1. bundle ids (app and widget extension) and team, all configurations
sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = ${UP_ID}/PRODUCT_BUNDLE_IDENTIFIER = ${GF_ID}/g" "$PBX"
sed -i '' "s/DEVELOPMENT_TEAM = [A-Z0-9]*;/DEVELOPMENT_TEAM = ${TEAM};/g" "$PBX"
# 2. no push, no iCloud
for E in Lume/Lume.entitlements Lume/Lume-iOS.entitlements; do
  for K in aps-environment com.apple.developer.aps-environment \
           com.apple.developer.icloud-container-identifiers com.apple.developer.icloud-services; do
    $PB -c "Delete :$K" "$E" 2>/dev/null || true
  done
done
# 3. our app group (entitlements and the one Swift file that names it)
sed -i '' "s/${UP_GROUP}/${GF_GROUP}/g" Lume/Lume-iOS.entitlements LumeWidgets/LumeWidgets.entitlements \
  LumeWidgets/PlaybackActivityAttributes.swift
# 4. no remote-notification background mode (no push entitlement any more)
i=0
while V=$($PB -c "Print :UIBackgroundModes:$i" Lume/Info.plist 2>/dev/null); do
  if [ "$V" = "remote-notification" ]; then $PB -c "Delete :UIBackgroundModes:$i" Lume/Info.plist; break; fi
  i=$((i + 1))
done
# 5. home-screen name
plutil -replace CFBundleDisplayName -string "Lume GF" Lume/Info.plist
echo "gf-patch: identity applied (team ${TEAM})"
