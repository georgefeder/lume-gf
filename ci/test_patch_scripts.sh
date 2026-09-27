#!/bin/sh
# Tests for gf-patch.sh / verify-patch.sh on a small fake Lume checkout (same file layout and project-file lines as
# Lume v2.1.0), including the upstream restructures that must stop the build. macOS only (PlistBuddy, plutil).
# Usage: sh ci/test_patch_scripts.sh
set -u
CI=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); fails=0; TEAM=ABCDE12345
trap 'rm -rf "$T"' EXIT
plist() {  # $1 file, rest: key value pairs (value "ARR:a,b" = array of strings)
  f=$1; shift
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n' > "$f"
  while [ $# -ge 2 ]; do
    printf '\t<key>%s</key>\n' "$1" >> "$f"
    case "$2" in
      ARR:*) printf '\t<array>\n' >> "$f"; echo "${2#ARR:}" | tr ',' '\n' | while read -r v; do printf '\t\t<string>%s</string>\n' "$v" >> "$f"; done; printf '\t</array>\n' >> "$f" ;;
      *) printf '\t<string>%s</string>\n' "$2" >> "$f" ;;
    esac
    shift 2
  done
  printf '</dict>\n</plist>\n' >> "$f"
}
fixture() {  # a fresh fake checkout in $T/$1
  L="$T/$1"; mkdir -p "$L/Lume.xcodeproj" "$L/Lume" "$L/LumeWidgets"
  cat > "$L/Lume.xcodeproj/project.pbxproj" <<'PBX'
		A1 /* Sideload */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "SIDE_LOAD $(inherited)";
			};
			name = Sideload;
		};
		A2 /* Sideload */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = Lume/Lume.entitlements;
				"CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]" = "Lume/Lume-iOS.entitlements";
				DEVELOPMENT_TEAM = CHG45F8MCL;
				PRODUCT_BUNDLE_IDENTIFIER = com.bilipp.lume;
			};
			name = Sideload;
		};
		A3 /* Sideload */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = LumeWidgets/LumeWidgets.entitlements;
				DEVELOPMENT_TEAM = CHG45F8MCL;
				PRODUCT_BUNDLE_IDENTIFIER = com.bilipp.lume.LumeWidgets;
			};
			name = Sideload;
		};
PBX
  plist "$L/Lume/Lume.entitlements" aps-environment development com.apple.developer.icloud-services ARR:CloudKit \
    com.apple.developer.icloud-container-identifiers ARR:iCloud.bilipp.Lume
  plist "$L/Lume/Lume-iOS.entitlements" aps-environment development com.apple.developer.aps-environment development \
    com.apple.developer.icloud-services ARR:CloudKit com.apple.developer.icloud-container-identifiers ARR:iCloud.bilipp.Lume \
    com.apple.security.application-groups ARR:group.com.bilipp.lume
  plist "$L/LumeWidgets/LumeWidgets.entitlements" com.apple.security.application-groups ARR:group.com.bilipp.lume
  plist "$L/Lume/Info.plist" CFBundleName Lume UIBackgroundModes ARR:audio,fetch,remote-notification
  printf 'enum Shared {\n    static let appGroupID = "group.com.bilipp.lume"\n}\n' > "$L/LumeWidgets/PlaybackActivityAttributes.swift"
  echo "$L"
}
expect() {  # $1 name, $2 0|1 expected verify exit, $3 checkout, [$4 text the output must contain]
  out=$(cd "$3" && sh "$CI/verify-patch.sh" "$TEAM" 2>&1); rc=$?
  if [ "$rc" -eq "$2" ] && { [ -z "${4:-}" ] || printf '%s' "$out" | grep -qF "$4"; }; then echo "ok   $1"
  else echo "FAIL $1 (exit $rc, want $2${4:+, text '$4'})"; printf '%s\n' "$out" | sed 's/^/     /'; fails=$((fails + 1)); fi
}
patched() { L=$(fixture "$1"); (cd "$L" && sh "$CI/gf-patch.sh" "$TEAM" >/dev/null) || echo "gf-patch failed in $1" >&2; echo "$L"; }

expect "unpatched checkout fails" 1 "$(fixture raw)" "upstream bundle id still in"
expect "patched checkout passes" 0 "$(patched base)" "identity OK"

L=$(patched clean)
for E in Lume/Lume.entitlements Lume/Lume-iOS.entitlements LumeWidgets/LumeWidgets.entitlements; do
  if grep -qiE "icloud|aps-environment" "$L/$E"; then echo "FAIL $E still has iCloud/push after gf-patch"; fails=$((fails + 1))
  else echo "ok   $E has no iCloud/push after gf-patch"; fi
done
L=$(patched iospush); /usr/libexec/PlistBuddy -c "Add :aps-environment string development" "$L/Lume/Lume-iOS.entitlements"
expect "push in the iPhone-only entitlements file fails" 1 "$L" "push entitlement still in Lume/Lume-iOS.entitlements"

L=$(fixture moved); printf 'let g = "group.com.bilipp.lume"\n' > "$L/Lume/AppGroup.swift"
(cd "$L" && sh "$CI/gf-patch.sh" "$TEAM" >/dev/null)
expect "app group moved to a new Swift file is rewritten" 0 "$L" "identity OK"
grep -q "group.lv.georgefeder.lume" "$L/Lume/AppGroup.swift" && echo "ok   new Swift file got our app group" \
  || { echo "FAIL new Swift file kept the upstream app group"; fails=$((fails + 1)); }

L=$(patched leftover); printf 'let g = "group.com.bilipp.lume"\n' > "$L/Lume/Late.swift"
expect "upstream app group left anywhere fails" 1 "$L" "Lume/Late.swift"

L=$(fixture tvents); plist "$L/Lume/Lume-tvOS.entitlements" com.apple.developer.icloud-services ARR:CloudKit aps-environment production
sed -i '' 's#"CODE_SIGN_ENTITLEMENTS\[sdk=iphoneos\*\]" = "Lume/Lume-iOS.entitlements";#&\
				"CODE_SIGN_ENTITLEMENTS[sdk=appletvos*]" = "Lume/Lume-tvOS.entitlements";#' "$L/Lume.xcodeproj/project.pbxproj"
(cd "$L" && sh "$CI/gf-patch.sh" "$TEAM" >/dev/null)
expect "new entitlements file named in the project is cleaned" 0 "$L" "identity OK"
grep -qiE "icloud|aps-environment" "$L/Lume/Lume-tvOS.entitlements" \
  && { echo "FAIL Lume-tvOS.entitlements still has iCloud/push after gf-patch"; fails=$((fails + 1)); } \
  || echo "ok   Lume-tvOS.entitlements has no iCloud/push after gf-patch"
L=$(patched tvleft); plist "$L/Lume/Lume-tvOS.entitlements" com.apple.developer.icloud-services ARR:CloudKit
sed -i '' 's#CODE_SIGN_ENTITLEMENTS = Lume/Lume.entitlements;#CODE_SIGN_ENTITLEMENTS = Lume/Lume-tvOS.entitlements;#' "$L/Lume.xcodeproj/project.pbxproj"
expect "iCloud in an entitlements file named in the project fails" 1 "$L" "iCloud entitlement still in Lume/Lume-tvOS.entitlements"

L=$(patched noteam); sed -i '' '/DEVELOPMENT_TEAM/d' "$L/Lume.xcodeproj/project.pbxproj"
expect "no DEVELOPMENT_TEAM line at all fails" 1 "$L" "no target is set to team"
L=$(patched nosideload); sed -i '' 's/name = Sideload;/name = Release;/' "$L/Lume.xcodeproj/project.pbxproj"
expect "Sideload configuration renamed fails" 1 "$L" "no configuration named Sideload"

[ "$fails" -eq 0 ] && echo "test_patch_scripts: all passed" || echo "test_patch_scripts: $fails failed"
exit "$fails"
