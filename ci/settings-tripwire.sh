#!/bin/sh
# Stops the tests when Lume has a setting (@AppStorage) that GFSettingsCatalog does not place (a new Lume release):
# such a setting would quietly stay on each device. Usage: sh settings-tripwire.sh <our repo dir> <Lume checkout dir>
set -euf
OURS="${1:?usage: settings-tripwire.sh OURS_DIR LUME_DIR}"; LUME="${2:?usage: settings-tripwire.sh OURS_DIR LUME_DIR}"
CATALOG="$OURS/app/Sync/GFSettingsCatalog.swift"
[ -f "$CATALOG" ] || { echo "settings-tripwire: $CATALOG missing"; exit 1; }
# A file's own shorthand is read as what it stands for: Lume 3.1's AetherEngine and Hue settings name their keys
# `Keys.probeSizeKey` after `private typealias Keys = PlayerSettings.Aether` (another file: `= PlayerSettings.Hue`)
keys_in() {
  F="$1"
  grep -oE '@AppStorage\(("[^"]+"|[A-Za-z_][A-Za-z0-9_.]*)' "$F" | sed -E 's/@AppStorage\(//' | while IFS= read -r K; do
    HEAD=${K%%.*}
    FULL=$(grep -oE "typealias $HEAD = [A-Za-z_][A-Za-z0-9_.]*" "$F" | head -1 | sed -E 's/.* = //')
    if [ -n "$FULL" ] && [ "$HEAD" != "$K" ]; then echo "$FULL.${K#*.}"; else echo "$K"; fi
  done
}
KEYS=$(grep -rlF '@AppStorage(' --include='*.swift' "$LUME/Lume" 2>/dev/null | while IFS= read -r F; do keys_in "$F"; done \
       | sort -u)
[ -n "$KEYS" ] || { echo "settings-tripwire: no @AppStorage under $LUME/Lume - Lume moved its settings"; exit 1; }
# every name the catalog spells out, whole (SortStorageKey.liveContent does not place SortStorageKey.live)
NAMES=$(grep -oE '"[^"]+"|[A-Za-z_][A-Za-z0-9_.]*' "$CATALOG" | sort -u)
missing=0
for KEY in $KEYS; do
  printf '%s\n' "$NAMES" | grep -qxF -- "$KEY" \
    || { echo "settings-tripwire: $KEY is not placed in GFSettingsCatalog"; missing=1; }
done
[ "$missing" -eq 0 ] && echo "settings-tripwire: every Lume setting is placed"
exit "$missing"
