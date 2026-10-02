#!/usr/bin/env python3
"""Is every record type and field our app writes in the production iCloud layout, with the same type? Production only
ever grows ("Deploy Schema Changes" in the CloudKit Console), so a missing one means the layout was not deployed yet.
Exit 1 with the missing ones. Usage: schema-check.py <required.ckdb> <production.ckdb>"""
import re, sys


def parse(text):
    types, current = {}, None
    for raw in text.splitlines():
        line = raw.strip()
        m = re.match(r'RECORD TYPE ("?[\w.]+"?) \($', line)
        if m:
            current = m.group(1).strip('"')
            types[current] = {}
            continue
        if line.startswith(");"):
            current = None
            continue
        if current is None or line.startswith("GRANT") or not line:
            continue
        m = re.match(r'("?[\w.]+"?)\s+(.+?),?$', line)
        if m:
            kind = re.sub(r"\s+(QUERYABLE|SORTABLE|SEARCHABLE)", "", m.group(2)).strip()
            types[current][m.group(1).strip('"')] = kind
    return types


required, production = parse(open(sys.argv[1]).read()), parse(open(sys.argv[2]).read())
missing = []
for record, fields in required.items():
    if record not in production:
        missing.append(record)
        continue
    for name, kind in fields.items():
        if production[record].get(name) != kind:
            missing.append("%s.%s (%s, production: %s)" % (record, name, kind, production[record].get(name)))
if missing:
    print("schema-check: missing in production:")
    for item in missing:
        print("  " + item)
    print("schema-check: open the CloudKit Console, container iCloud.lv.georgefeder.lume, and press "
          "Deploy Schema Changes (Georgs), then build again")
    sys.exit(1)
print("schema-check: production has every type and field (%d types)" % len(required))
