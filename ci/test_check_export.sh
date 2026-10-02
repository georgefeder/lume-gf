#!/bin/sh
# Tests for check-export.sh on fake exported .ipa files (tiny macOS executables signed ad hoc with the entitlements an
# App Store export would carry). macOS only.
# Usage: sh ci/test_check_export.sh
set -u
CI=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); fails=0; TEAM=ABCDE12345
trap 'rm -rf "$T"' EXIT
printf 'int main(void){return 0;}\n' > "$T/m.c"; cc -o "$T/bin" "$T/m.c" || { echo "no C compiler"; exit 1; }
PB=/usr/libexec/PlistBuddy
ents() {  # $1 file, then flags: group, debug, appid=<value>
  f=$1; shift; $PB -c "Add :application-identifier string $TEAM.lv.georgefeder.lume" "$f" >/dev/null
  for a in "$@"; do case "$a" in
    group) $PB -c "Add :com.apple.security.application-groups array" \
                -c "Add :com.apple.security.application-groups:0 string group.lv.georgefeder.lume" "$f" >/dev/null ;;
    debug) $PB -c "Add :get-task-allow bool true" "$f" >/dev/null ;;
    push) $PB -c "Add :aps-environment string production" "$f" >/dev/null ;;
    icloud) $PB -c "Add :com.apple.developer.icloud-services array" -c "Add :com.apple.developer.icloud-services:0 string CloudKit" \
                -c "Add :com.apple.developer.icloud-container-identifiers array" \
                -c "Add :com.apple.developer.icloud-container-identifiers:0 string iCloud.lv.georgefeder.lume" \
                -c "Add :com.apple.developer.ubiquity-kvstore-identifier string $TEAM.lv.georgefeder.lume" "$f" >/dev/null ;;
    lumecloud) $PB -c "Add :com.apple.developer.icloud-container-identifiers:1 string iCloud.bilipp.Lume" "$f" >/dev/null ;;
    pushdev) $PB -c "Add :aps-environment string development" "$f" >/dev/null ;;
    appid=*) $PB -c "Set :application-identifier ${a#appid=}" "$f" >/dev/null ;;
  esac; done
}
ipa() {  # $1 name, $2 display name, $3 app entitlement flags (comma list), $4 extension flags ("none" = no extension)
  D="$T/$1"; A="$D/Payload/Lume.app"; mkdir -p "$A"; cp "$T/bin" "$A/Lume"
  $PB -c "Add :CFBundleIdentifier string lv.georgefeder.lume" -c "Add :CFBundleExecutable string Lume" \
      -c "Add :CFBundlePackageType string APPL" -c "Add :CFBundleDisplayName string $2" \
      -c "Add :CFBundleVersion string 7" "$A/Info.plist" >/dev/null
  case "$1" in *nobg) ;; *)
    $PB -c "Add :BGTaskSchedulerPermittedIdentifiers array" \
        -c "Add :BGTaskSchedulerPermittedIdentifiers:0 string lv.georgefeder.lume.guide.refresh" \
        -c "Add :BGTaskSchedulerPermittedIdentifiers:1 string lv.georgefeder.lume.guide.import" "$A/Info.plist" >/dev/null ;;
  esac
  if [ "$4" != none ]; then
    X="$A/PlugIns/LumeWidgets.appex"; mkdir -p "$X"; cp "$T/bin" "$X/LumeWidgets"
    $PB -c "Add :CFBundleIdentifier string lv.georgefeder.lume.LumeWidgets" -c "Add :CFBundleExecutable string LumeWidgets" \
        -c "Add :CFBundlePackageType string XPC!" "$X/Info.plist" >/dev/null
    ents "$D/x.plist" $(echo "$4" | tr ',' ' '); codesign -f -s - --entitlements "$D/x.plist" "$X" 2>/dev/null
  fi
  ents "$D/a.plist" $(echo "$3" | tr ',' ' '); codesign -f -s - --entitlements "$D/a.plist" "$A" 2>/dev/null
  mkdir -p "$D/export"; (cd "$D" && zip -qr "export/Lume GF.ipa" Payload); echo "$D/export"
}
expect() {  # $1 name, $2 0|1, $3 export dir, $4 platform, [$5 text]
  out=$(sh "$CI/check-export.sh" "$3" "$TEAM" "$4" 2>&1); rc=$?
  if [ "$rc" -eq "$2" ] && { [ -z "${5:-}" ] || printf '%s' "$out" | grep -qF "$5"; }; then echo "ok   $1"
  else echo "FAIL $1 (exit $rc, want $2${5:+, text '$5'})"; printf '%s\n' "$out" | sed 's/^/     /'; fails=$((fails + 1)); fi
}
expect "good iOS export passes" 0 "$(ipa good 'Lume GF' group,icloud,push group)" iOS "check-export: OK"
expect "app without the app group fails" 1 "$(ipa nogroup 'Lume GF' icloud,push group)" iOS "app group missing in Lume.app"
expect "widget extension without the app group fails" 1 "$(ipa xnogroup 'Lume GF' group,icloud,push -)" iOS "app group missing in LumeWidgets.appex"
expect "debug entitlement fails" 1 "$(ipa debug 'Lume GF' group,icloud,push,debug group)" iOS "get-task-allow"
expect "app without our container fails" 1 "$(ipa nocloud 'Lume GF' group,push group)" iOS "our iCloud container missing in Lume.app"
expect "Lume's container fails" 1 "$(ipa lumecloud 'Lume GF' group,icloud,lumecloud,push group)" iOS "Lume's container in Lume.app"
expect "development push fails" 1 "$(ipa pushdev 'Lume GF' group,icloud,pushdev group)" iOS "push is not production in Lume.app"
expect "iCloud in the widgets fails" 1 "$(ipa xcloud 'Lume GF' group,icloud,push group,icloud)" iOS "push/iCloud entitlement in LumeWidgets.appex"
expect "another team's app id fails" 1 "$(ipa appid 'Lume GF' group,icloud,push,appid=ZZZZZ99999.lv.georgefeder.lume group)" iOS "application-identifier"
expect "wrong home-screen name fails" 1 "$(ipa name 'Lume' group,icloud,push group)" iOS "display name"
expect "tvOS export without app group passes" 0 "$(ipa tv 'Lume GF' icloud,push none)" tvOS "check-export: OK"
mkdir -p "$T/none/export"
expect "no .ipa fails" 1 "$T/none/export" iOS "no .ipa"
expect "missing background task ids fails" 1 "$(ipa nobg 'Lume GF' group,icloud,push group)" iOS "background task"
[ "$fails" -eq 0 ] && echo "test_check_export: all passed" || echo "test_check_export: $fails failed"
exit "$fails"
