#!/bin/sh
# Tests for settings-tripwire.sh on a fake catalog and a fake Lume checkout. Usage: sh ci/test_settings_tripwire.sh
set -u
CI=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fails=0
ok() { echo "ok   $1"; }; no() { echo "FAIL $1"; fails=$((fails + 1)); }
mkdir -p "$T/ours/app/Sync" "$T/lume/Lume/Views/Home" "$T/lume/Lume/Views/Player"
CATALOG="$T/ours/app/Sync/GFSettingsCatalog.swift"
cat > "$T/lume/Lume/Views/Home/HomeView.swift" <<'EOF'
    @AppStorage(HomeLayoutSettings.sectionOrderKey) private var order = ""
EOF
cat > "$T/lume/Lume/Views/Player/QuickSwitch.swift" <<'EOF'
    @AppStorage("tv.quickSwitch.hintShown.v1") private var hintShown = false
EOF
trip() { out=$(sh "$CI/settings-tripwire.sh" "$T/ours" "$T/lume" 2>&1); code=$?; }

printf '%s\n' 'static let perKind: [String] = [HomeLayoutSettings.sectionOrderKey]' > "$CATALOG"
trip
[ "$code" -eq 1 ] && ok "a Lume setting the catalog does not place stops the tests" || no "exit $code ($out)"
printf '%s' "$out" | grep -q "tv.quickSwitch.hintShown.v1" && ok "and is named" || no "not named ($out)"
printf '%s' "$out" | grep -q "HomeLayoutSettings.sectionOrderKey" && no "a placed setting named ($out)" \
  || ok "a placed setting is not named"

printf '%s\n' 'static let perKind: [String] = [HomeLayoutSettings.sectionOrderKey]' \
  'static let deviceOnly: [String] = ["tv.quickSwitch.hintShown.v1"]' > "$CATALOG"
trip
[ "$code" -eq 0 ] && ok "every setting placed passes" || no "every setting placed must pass (exit $code, $out)"

# a name that only appears inside a longer one is not placed
cat > "$T/lume/Lume/Views/Home/Sort.swift" <<'EOF'
    @AppStorage(SortStorageKey.live) private var sort = ""
EOF
printf '%s\n' 'static let everywhere: [String] = [SortStorageKey.liveContent]' \
  'static let perKind: [String] = [HomeLayoutSettings.sectionOrderKey]' \
  'static let deviceOnly: [String] = ["tv.quickSwitch.hintShown.v1"]' > "$CATALOG"
trip
[ "$code" -eq 1 ] && printf '%s' "$out" | grep -q "SortStorageKey.live " \
  && ok "a setting named only inside a longer name is not placed" || no "part of a longer name counted (exit $code, $out)"
rm "$T/lume/Lume/Views/Home/Sort.swift"

rm "$CATALOG"; trip
[ "$code" -ne 0 ] && printf '%s' "$out" | grep -q "GFSettingsCatalog.swift" && ok "a missing catalog fails" \
  || no "missing catalog (exit $code, $out)"
printf '%s\n' 'x' > "$CATALOG"; rm -r "$T/lume/Lume/Views"; trip
[ "$code" -ne 0 ] && printf '%s' "$out" | grep -q "Lume moved" && ok "no setting found at all fails (Lume moved them)" \
  || no "an empty Lume passed (exit $code, $out)"

[ "$fails" -eq 0 ] && echo "test_settings_tripwire: all passed" || echo "test_settings_tripwire: $fails failed"
exit "$fails"
