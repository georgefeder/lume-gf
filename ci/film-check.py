#!/usr/bin/env python3
"""Reads a film's brightness (luma.csv from video-frames.swift) of the iPhone opening a channel in light mode and says
whether the screen flashed: went dark and came back light before the player took over (what Georgs saw on build 8).
Exit 1 on a flash. Usage: film-check.py <film dir>"""
import csv, os, sys

film = sys.argv[1]
lumas = [float(row["luma"]) for row in csv.DictReader(open(os.path.join(film, "luma.csv")))]
name = os.path.basename(film.rstrip("/"))
if not lumas:
    print("film-check: %s: no frames" % name)
    sys.exit(0)
went_dark = False
for luma in lumas:
    if luma < 0.3:
        went_dark = True
    elif luma > 0.5 and went_dark:
        print("film-check: %s: flash (dark, then light again before the player)" % name)
        sys.exit(1)
print("film-check: %s: no flash" % name)
