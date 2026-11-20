#!/usr/bin/env python3
"""The newest TestFlight crash reports testers shared ("Share with developer"), for the "Lume GF crashes" workflow.

Prints, per report: when, the build, the device model and iOS version, and from the crash log only the exception, the
termination reason and the crashed thread's frames. Never the tester's name, email or comment, and never the key, the
token or the ids (the workflow log of this public repository is public).

Usage: ASC_KEY_PATH=<.p8> ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id> python3 asc_crashes.py [COUNT]
"""
import json, os, re, sys, urllib.error, urllib.parse

from asc_dev_certs import API, http, id_problems, jwt

BUNDLE_ID = "lv.georgefeder.lume"
KEEP = re.compile(r"^(Exception Type|Exception Reason|Exception Codes|Termination Reason|Triggered by Thread|"
                  r"Crashed Thread|Hardware Model|OS Version|Version|Incident|Date/Time|Application Specific)")


def excerpt(log, frames=40):
    """The header lines that name the crash, the 'Application Specific Information' block, and the crashed thread.
    Both the classic text form and the JSON (.ips) form."""
    try:
        return excerpt_ips(log, frames)
    except (ValueError, KeyError, TypeError, IndexError):
        pass
    out, lines, i = [], log.splitlines(), 0
    while i < len(lines):
        line = lines[i]
        if KEEP.match(line):
            out.append(line)
            if line.startswith("Application Specific"):
                i += 1
                while i < len(lines) and lines[i].strip():
                    out.append(lines[i]); i += 1
                continue
        if re.match(r"^(Thread \d+ Crashed|Last Exception Backtrace)", line):
            out.append(line)
            n, i = 0, i + 1
            while i < len(lines) and lines[i].strip() and n < frames:
                out.append(lines[i]); i += 1; n += 1
            continue
        i += 1
    return "\n".join(out)


def excerpt_ips(log, frames):
    """A JSON crash report: a one-line header object, then the report object."""
    head, _, rest = log.partition("\n")
    header, report = json.loads(head), json.loads(rest)
    images = report.get("usedImages", [])
    out = [f"Version: {header.get('app_version')} ({header.get('build_version')})",
           f"OS: {header.get('os_version')}  Model: {report.get('modelCode')}"]
    exc = report.get("exception", {})
    out.append(f"Exception: {exc.get('type')} {exc.get('signal', '')} {exc.get('subtype', '')}".rstrip())
    term = report.get("termination", {})
    if term:
        out.append(f"Termination: {term.get('namespace')} {term.get('indicator', '')} "
                   f"{' '.join(term.get('reasons', []))}".rstrip())
    asi = report.get("asi")
    if asi:
        out.append(f"Application Specific: {json.dumps(asi)[:1500]}")

    def frame(f):
        img = images[f["imageIndex"]] if f.get("imageIndex", -1) < len(images) else {}
        return f"  {img.get('name', '?'):<28} {f.get('symbol', hex(f.get('imageOffset', 0)))}" \
               f"{' ' + f['sourceFile'] + ':' + str(f.get('sourceLine')) if f.get('sourceFile') else ''}"

    if report.get("lastExceptionBacktrace"):
        out.append("Last Exception Backtrace:")
        out += [frame(f) for f in report["lastExceptionBacktrace"][:frames]]
    for t in report.get("threads", []):
        if t.get("triggered"):
            out.append(f"Crashed thread {t.get('name') or t.get('queue') or ''}:")
            out += [frame(f) for f in t.get("frames", [])[:frames]]
    return "\n".join(out)


def main(argv):
    count = int(argv[1]) if len(argv) > 1 else 3
    key_id, issuer = os.environ.get("ASC_KEY_ID", ""), os.environ.get("ASC_ISSUER_ID", "")
    problems = id_problems(key_id, issuer)
    for p in problems:
        print(f"asc-crashes: {p}", file=sys.stderr)
    if problems:
        return 1
    try:
        token = jwt(os.environ["ASC_KEY_PATH"], key_id, issuer)
        apps = http("GET", f"{API}/apps?filter[bundleId]={urllib.parse.quote(BUNDLE_ID)}", token)["data"]
        if not apps:
            print("asc-crashes: no app with that bundle id", file=sys.stderr); return 1
        page = http("GET", f"{API}/apps/{apps[0]['id']}/betaFeedbackCrashSubmissions?limit={count}"
                           f"&sort=-createdDate&include=build", token)
        builds = {b["id"]: b["attributes"].get("version") for b in page.get("included", []) if b["type"] == "builds"}
        if not page["data"]:
            print("asc-crashes: no shared crash reports")
            return 0
        for sub in page["data"]:
            a = sub["attributes"]
            build = (sub.get("relationships", {}).get("build", {}).get("data") or {}).get("id")
            print(f"===== {a.get('createdDate')}  build {builds.get(build, '?')}  {a.get('deviceModel')} "
                  f"{a.get('osVersion')}  {a.get('deviceFamily') or ''}")
            try:
                log = http("GET", f"{API}/betaFeedbackCrashSubmissions/{sub['id']}/crashLog", token)
                print(excerpt(log["data"]["attributes"].get("logText") or ""))
            except urllib.error.HTTPError as e:
                print(f"(crash log not available: HTTP {e.code})")
    except KeyError as e:
        print(f"asc-crashes: {e.args[0]} missing", file=sys.stderr); return 1
    except urllib.error.HTTPError as e:
        print(f"asc-crashes: App Store Connect answered HTTP {e.code}: {e.read()[:300].decode(errors='replace')}",
              file=sys.stderr); return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
