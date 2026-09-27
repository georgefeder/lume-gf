#!/bin/sh
# Tests for sign-local.sh on a fake archive (tiny macOS executables stand in for the app, a framework and the widget
# extension; codesign treats them the same way). macOS only.
# Usage: sh ci/test_sign_local.sh
set -u
CI=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); fails=0
trap 'rm -rf "$T"' EXIT
printf 'int main(void){return 0;}\n' > "$T/m.c"; cc -o "$T/bin" "$T/m.c" || { echo "no C compiler"; exit 1; }
info() {  # $1 plist, $2 bundle id, $3 executable, $4 package type
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $2" -c "Add :CFBundleExecutable string $3" \
    -c "Add :CFBundlePackageType string $4" "$1" >/dev/null
}
ent() {  # $1 file, $2 app group
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups array" \
    -c "Add :com.apple.security.application-groups:0 string $2" "$1" >/dev/null
}
archive() {  # fresh fake archive in $T/$1; prints the app path
  A="$T/$1/LumeGF.xcarchive/Products/Applications/Lume.app"
  mkdir -p "$A/Frameworks/Foo.framework" "$A/PlugIns/LumeWidgets.appex"
  cp "$T/bin" "$A/Lume"; cp "$T/bin" "$A/Frameworks/Foo.framework/Foo"; cp "$T/bin" "$A/PlugIns/LumeWidgets.appex/LumeWidgets"
  info "$A/Info.plist" lv.georgefeder.lume Lume APPL
  info "$A/Frameworks/Foo.framework/Info.plist" com.kintan.ksplayer.Foo-x Foo FMWK
  info "$A/PlugIns/LumeWidgets.appex/Info.plist" lv.georgefeder.lume.LumeWidgets LumeWidgets XPC!
  echo "$A"
}
ent "$T/app.entitlements" group.lv.georgefeder.lume; ent "$T/widgets.entitlements" group.lv.georgefeder.lume
ok() { echo "ok   $1"; }; no() { echo "FAIL $1"; fails=$((fails + 1)); }
has_group() { codesign -d --entitlements - --xml "$1" 2>/dev/null | grep -q "group.lv.georgefeder.lume"; }

A=$(archive good)
if sh "$CI/sign-local.sh" "$T/good/LumeGF.xcarchive" "$T/app.entitlements" "LumeWidgets=$T/widgets.entitlements" >/dev/null; then ok "signs a complete archive"; else no "signs a complete archive"; fi
has_group "$A" && ok "app carries the app group" || no "app carries the app group"
has_group "$A/PlugIns/LumeWidgets.appex" && ok "widget extension carries the app group" || no "widget extension carries the app group"
codesign -dv "$A/Frameworks/Foo.framework" 2>&1 | grep -q "^Identifier=com.kintan.ksplayer.Foo-x$" \
  && ok "framework signed with its bundle id" || no "framework signed with its bundle id"
codesign --verify --deep --strict "$A" 2>/dev/null && ok "whole app verifies" || no "whole app verifies"

archive noext >/dev/null
out=$(sh "$CI/sign-local.sh" "$T/noext/LumeGF.xcarchive" "$T/app.entitlements" 2>&1) && no "extension without entitlements fails" \
  || { printf '%s' "$out" | grep -q "no entitlements given for extension LumeWidgets" && ok "extension without entitlements fails" || no "extension without entitlements fails (message: $out)"; }
archive noent >/dev/null
out=$(sh "$CI/sign-local.sh" "$T/noent/LumeGF.xcarchive" "$T/missing.entitlements" "LumeWidgets=$T/widgets.entitlements" 2>&1) \
  && no "missing app entitlements file fails" || ok "missing app entitlements file fails"
mkdir -p "$T/empty/LumeGF.xcarchive/Products/Applications"
out=$(sh "$CI/sign-local.sh" "$T/empty/LumeGF.xcarchive" "$T/app.entitlements" 2>&1) && no "archive without an app fails" \
  || ok "archive without an app fails"

[ "$fails" -eq 0 ] && echo "test_sign_local: all passed" || echo "test_sign_local: $fails failed"
exit "$fails"
