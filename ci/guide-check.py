#!/usr/bin/env python3
"""Checks the screenshots for what Georgs saw before, so it cannot come back unnoticed. (Since Lume 2.4 the guide is
Lume's own on both devices, so the iPhone glass column's checks of build 9 are gone; their helpers stay below.)
For Georgs' notes of 2 Oct: posters in a row line up at the top (a title on two lines lifted its poster), and Home
shows Recently Watched and the recently added films and series (his Apple TV's Home showed only the sports row). Rows
below the first screen are never drawn, so the recently added rows are checked on a second picture of Home with
Recently Watched and Favorites switched off. The continue banner sits at the top of the screen, whole, centred on the
iPhone and in the right half on the Apple TV.
Positions come from the demo build's log lines ("GFDemo guide geometry:", "GFDemo focused programme:", in points on
screen), brightness from png-lines.swift. Exit 1 when a check fails. Usage: guide-check.py <screenshots dir>"""
import os, statistics, subprocess, sys

GEOMETRY = "GFDemo guide geometry:"
FOCUSED = "GFDemo focused programme:"
RAIL_CARD = "GFDemo rail card:"
BANNER = "GFDemo banner:"
BANNER_SHOTS = ("iphone-banner-dark", "tv-banner")
HOME_TOP = ("Recently Watched",)
HOME_ADDED = ("Recently Added Movies", "Recently Added Series")
HOME_SHOTS = {"iphone-home-dark": HOME_TOP, "tv-home": HOME_TOP,
              "iphone-home-added-dark": HOME_ADDED, "tv-home-added": HOME_ADDED}
POSTER_SHOTS = ("iphone-movies-dark", "iphone-series-dark", "iphone-home-dark", "iphone-home-added-dark",
                "tv-movies", "tv-home", "tv-home-added")


def parse_fields(text):
    fields = {}
    for part in text.split():
        if "=" in part:
            key, value = part.split("=", 1)
            try:
                fields[key] = float(value)
            except ValueError:
                pass
    return fields


def last_fields(log_path, prefix):
    """The fields of the last line starting with `prefix` in a log, or None."""
    found = None
    try:
        with open(log_path, errors="replace") as f:
            for line in f:
                if line.startswith(prefix):
                    found = line[len(prefix):]
    except OSError:
        return None
    return parse_fields(found) if found is not None else None


def rail_cards(log_path):
    """{row title: {card index: top on screen}} from the demo's "rail card" lines (the last line per card wins)."""
    rows = {}
    try:
        with open(log_path, errors="replace") as f:
            for line in f:
                if not line.startswith(RAIL_CARD):
                    continue
                parts = line[len(RAIL_CARD):].strip().split(" ", 3)
                if len(parts) < 4:
                    continue
                try:
                    index, top = int(parts[0]), float(parts[1])
                except ValueError:
                    continue
                rows.setdefault(parts[3], {})[index] = top
    except OSError:
        return {}
    return rows


def rows_level_ok(rows):
    if not rows:
        return False, "no rows of posters logged"
    crooked = []
    for title, cards in sorted(rows.items()):
        if len(cards) > 1 and max(cards.values()) - min(cards.values()) > 0.5:
            crooked.append("%s (%.1f points apart)" % (title, max(cards.values()) - min(cards.values())))
    if crooked:
        return False, "posters at different heights in: " + ", ".join(crooked)
    return True, "posters level in %d rows" % len(rows)


def home_rows_ok(rows, expected):
    missing = [title for title in expected if not rows.get(title)]
    if missing:
        return False, "Home is missing: " + ", ".join(missing)
    return True, "Home shows " + ", ".join(expected)


def banner_ok(b):
    """The continue banner from its log line: whole on screen in the top 30%, centred on the iPhone (equal gaps), in the
    right half on the Apple TV."""
    if not b or b.get("w", 0) <= 0 or b.get("screenW", 0) <= 0:
        return False, "no banner logged"
    left, right = b["x"], b["screenW"] - b["x"] - b["w"]
    detail = "x=%g y=%g w=%g h=%g on %gx%g" % (b["x"], b["y"], b["w"], b["h"], b["screenW"], b["screenH"])
    if left < 0 or right < 0 or b["y"] < 0:
        return False, "off the screen: " + detail
    if b["y"] + b["h"] > b["screenH"] * 0.3:
        return False, "not at the top: " + detail
    if b.get("tv"):
        if b["x"] < b["screenW"] / 2:
            return False, "not on the right: " + detail
    elif abs(left - right) > 2:
        return False, "not centred: " + detail
    return True, detail


def residual(values, half=20):
    """How far brightness strays from its own neighbourhood along a line: rows of tiles stray, a smooth backdrop
    (the Apple TV's gradient) does not."""
    if len(values) <= 2 * half:
        return 0.0
    total = 0.0
    window = sum(values[:2 * half + 1])
    for i in range(half, len(values) - half):
        if i > half:
            window += values[i + half] - values[i - half - 1]
        total += abs(values[i] - window / (2 * half + 1))
    return total / (len(values) - 2 * half)


def first_edge(values, threshold=8):
    """The first place along a line (from its start) where the brightness changes by more than `threshold`."""
    for i, value in enumerate(values):
        if abs(value - values[0]) > threshold:
            return i
    return None


def strip_ok(lines):
    brightest = max((max(line) for line in lines if line), default=None)
    darkest = min((min(line) for line in lines if line), default=None)
    if brightest is None:
        return False, "no pixels measured"
    if brightest - darkest > 12:
        return False, "programmes show beside the panel (brightness %d to %d)" % (darkest, brightest)
    return True, "only background beside the panel"


def under_ok(left_lines, control_lines):
    control = max((residual(line) for line in control_lines if line), default=0.0)
    if control < 3:
        return False, "no programmes right of the panel either (%.2f): the picture proves nothing" % control
    left = max((residual(line) for line in left_lines if line), default=None)
    if left is None:
        return False, "no pixels measured"
    if left > 1.5:
        return False, "programmes under the panel's left half (%.2f, beside it %.2f)" % (left, control)
    return True, "nothing under the panel's left half (%.2f, beside it %.2f)" % (left, control)


def first_row_ok(edges, fade, expected=None):
    found = [e for e in edges if e is not None]
    if not found:
        return False, "no row found below the ruler"
    top = statistics.median(found)
    if top < fade + 1:
        return False, "the first row starts %.1f points down, inside the %.0f-point fade" % (top, fade)
    if expected is not None and abs(top - expected) > 1.5:
        return False, "the first row starts %.1f points down, not %.0f" % (top, expected)
    return True, "the first row starts %.1f points down, below the %.0f-point fade" % (top, fade)


def focus_ok(before, inside, width):
    if width < 1000:
        return False, "the focus is not on the long programme (%.0f points wide)" % width
    if inside <= 150:
        return False, "the focused programme does not show its focus (brightness %d)" % inside
    if before >= 150:
        return False, "the focus glass spreads over the tile before it (brightness %d there)" % before
    return True, "the focused programme keeps to itself (%d before it, %d on it)" % (before, inside)


def _px(points, scale):
    return int(round(points * scale))


def strip_lines(g):
    """Vertical lines down the strip left of the panel (iPhone; the Apple TV's panel has none)."""
    s = g["scale"]
    width = g["panelMinX"] - g["guideX"]
    if width < 2:
        return []
    y0 = _px(g["guideY"] + g["room"] + g["rowSpacing"] / 2 + 2, s)
    y1 = _px(g["guideY"] + g["guideH"] * 0.7, s)
    xs = [g["guideX"] + 1, g["guideX"] + width / 2, g["panelMinX"] - 1]
    return [(_px(x, s), y0, _px(x, s), y1) for x in xs]


def under_lines(g):
    """Lines down the panel's left half, and control lines down the programmes right of it."""
    s = g["scale"]
    y0 = _px(g["guideY"] + g["room"] + 2, s)
    y1 = _px(g["guideY"] + g["guideH"] * 0.7, s)
    left = [g["panelMinX"] + f * (g["gone"] - g["panelMinX"]) for f in (0.2, 0.5, 0.85)]
    control = [g["clear"] + d for d in (40, 120, 200)]
    return ([(_px(x, s), y0, _px(x, s), y1) for x in left], [(_px(x, s), y0, _px(x, s), y1) for x in control])


def first_row_lines(g):
    """Short lines down from the top of the scroll area, right of the panel."""
    s = g["scale"]
    y0 = _px(g["guideY"] + 1, s)
    y1 = _px(g["guideY"] + g["room"] + g["rowSpacing"] + 40, s)
    return [(_px(g["clear"] + d, s), y0, _px(g["clear"] + d, s), y1) for d in (40, 120, 200)]


def focus_lines(f, scale):
    """Down the gap just left of the focused programme as drawn (grown), and down the programme itself: the brightest
    pixel of each line counts, so the programme's own text never decides it."""
    before = (_px(f["x"] - 3, scale), _px(f["y"] + 7, scale), _px(f["x"] - 3, scale), _px(f["y"] + f["h"] - 7, scale))
    inside = (_px(f["x"] + 30, scale), _px(f["y"] + 10, scale), _px(f["x"] + 30, scale),
              _px(f["y"] + f["h"] - 10, scale))
    return before, inside


def run_checks(out, sample):
    """[(check, ok, detail)]. `sample(png, lines)` gives the brightness along each line."""
    logs = os.path.join(out, "logs")
    results = []
    for shot in POSTER_SHOTS:
        results.append(("posters level (%s)" % shot,) + rows_level_ok(rail_cards(os.path.join(logs, shot + ".err"))))
    for shot, expected in HOME_SHOTS.items():
        results.append(("Home rows (%s)" % shot,)
                       + home_rows_ok(rail_cards(os.path.join(logs, shot + ".err")), expected))
    for shot in BANNER_SHOTS:
        results.append(("continue banner (%s)" % shot,)
                       + banner_ok(last_fields(os.path.join(logs, shot + ".err"), BANNER)))

    return results


def swift_sample(png, lines):
    """Brightness along each line, from png-lines.swift ([] per line when the picture cannot be read)."""
    if not os.path.exists(png) or not lines:
        return [[] for _ in lines]
    specs = ["%d,%d,%d,%d" % line for line in lines]
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "png-lines.swift")
    run = subprocess.run(["swift", script, png] + specs, capture_output=True, text=True)
    rows = run.stdout.splitlines() if run.returncode == 0 else []
    if len(rows) != len(lines):
        sys.stderr.write(run.stderr)
        return [[] for _ in lines]
    return [[int(v) for v in row.split()] for row in rows]


def main():
    results = run_checks(sys.argv[1], swift_sample)
    for check, ok, detail in results:
        print("guide-check: %s: %s (%s)" % (check, "ok" if ok else "FAIL", detail))
    return 0 if all(ok for _, ok, _ in results) else 1


if __name__ == "__main__":
    sys.exit(main())
