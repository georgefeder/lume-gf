#!/usr/bin/env python3
"""Checks the guide screenshots for what Georgs saw on build 9, so it cannot come back unnoticed:
  - iPhone: nothing but background in the strip left of the glass panel (bits of programmes showed there);
  - both: with the channel column hidden (-GFDemoNoPanel), no programmes under the panel's left half (a real Apple
    TV's glass bent them into view along its left edge; the simulator's glass is too frosted to show it, so the
    column goes and what is left under it is measured);
  - both: the first row starts below the top fade (it sat where the fade starts);
  - Apple TV: a focused six-hour programme keeps to itself ("No Pr..." showed through the focus glass over it).
Positions come from the demo build's log lines ("GFDemo guide geometry:", "GFDemo focused programme:", in points on
screen), brightness from png-lines.swift. Exit 1 when a check fails. Usage: guide-check.py <screenshots dir>"""
import os, statistics, subprocess, sys

GEOMETRY = "GFDemo guide geometry:"
FOCUSED = "GFDemo focused programme:"


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


def first_row_ok(edges, fade):
    found = [e for e in edges if e is not None]
    if not found:
        return False, "no row found below the ruler"
    top = statistics.median(found)
    if top < fade + 1:
        return False, "the first row starts %.1f points down, inside the %.0f-point fade" % (top, fade)
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


def run_checks(out, sample):
    """[(check, ok, detail)]. `sample(png, lines)` gives the brightness along each line."""
    logs = os.path.join(out, "logs")
    results = []

    def geometry(shot):
        return last_fields(os.path.join(logs, shot + ".err"), GEOMETRY)

    def png(shot):
        return os.path.join(out, shot + ".png")

    shot = "iphone-guide-dark"
    g = geometry(shot)
    if g is None:
        results.append(("beside the panel (%s)" % shot, False, "no guide geometry logged"))
    else:
        lines = strip_lines(g)
        results.append(("beside the panel (%s)" % shot,) + (strip_ok(sample(png(shot), lines)) if lines
                                                             else (False, "no strip left of the panel")))

    for shot in ("iphone-guide-under-dark", "tv-guide-under"):
        g = geometry(shot)
        if g is None:
            results.append(("under the panel (%s)" % shot, False, "no guide geometry logged"))
            continue
        left, control = under_lines(g)
        measured = sample(png(shot), left + control)
        results.append(("under the panel (%s)" % shot,) + under_ok(measured[:len(left)], measured[len(left):]))

    for shot in ("iphone-guide-dark", "tv-guide-channel"):
        g = geometry(shot)
        if g is None:
            results.append(("first row (%s)" % shot, False, "no guide geometry logged"))
            continue
        lines = first_row_lines(g)
        edges = []
        for (x0, y0, _, _), values in zip(lines, sample(png(shot), lines)):
            i = first_edge(values) if values else None
            edges.append(None if i is None else (y0 + i) / g["scale"] - g["guideY"])
        results.append(("first row (%s)" % shot,) + first_row_ok(edges, g["fade"]))

    shot = "tv-guide-long"
    g = geometry(shot)
    f = last_fields(os.path.join(logs, shot + ".err"), FOCUSED)
    if g is None or f is None:
        results.append(("focused long programme (%s)" % shot, False, "no geometry or focus logged"))
    else:
        s = g["scale"]
        y = _px(f["y"] + f["h"] / 2, s)
        points = [(_px(f["x"] - 8, s), y, _px(f["x"] - 8, s), y), (_px(f["x"] + 30, s), y, _px(f["x"] + 30, s), y)]
        measured = sample(png(shot), points)
        if not all(measured):
            results.append(("focused long programme (%s)" % shot, False, "no pixels measured"))
        else:
            results.append(("focused long programme (%s)" % shot,)
                           + focus_ok(measured[0][0], measured[1][0], f["w"]))
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
