#!/bin/sh
# Stops the tests when Lume has a setting (@AppStorage) that GFSettingsCatalog does not place (a new Lume release):
# such a setting would quietly stay on each device. Usage: sh settings-tripwire.sh <our repo dir> <Lume checkout dir>
set -euf
OURS="${1:?usage: settings-tripwire.sh OURS_DIR LUME_DIR}"; LUME="${2:?usage: settings-tripwire.sh OURS_DIR LUME_DIR}"
CATALOG="$OURS/app/Sync/GFSettingsCatalog.swift"
[ -f "$CATALOG" ] || { echo "settings-tripwire: $CATALOG missing"; exit 1; }
KEYS=$(grep -rhoE '@AppStorage\(("[^"]+"|[A-Za-z_][A-Za-z0-9_.]*)' --include='*.swift' "$LUME/Lume" 2>/dev/null \
       | sed -E 's/@AppStorage\(//' | sort -u)
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
