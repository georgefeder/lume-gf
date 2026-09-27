#!/usr/bin/env python3
"""App Store Connect key check, and clean-up of throwaway "Apple Development: Created via API" certificates.

--check (used by the build before and after the upload, and by the "Lume GF key check" workflow) asks App Store
Connect whether it accepts the key and how many certificates the team has; the same count before and after the upload
shows that the build created none. It revokes nothing.

Without --check it revokes development certificates named "Created via API". The build does not use this any more (it
archives unsigned, 27 Sep 2026); it is kept for the case that a build ever signs its archive with Xcode's development
signing again: on a fresh GitHub runner Xcode then creates such a certificate through the API on every run, its private
key dies with the runner, and the next run can fail with "already has an Apple Development signing certificate for this
machine". It never touches distribution certificates or development certificates made by Xcode on a Mac (those carry
the person's name).

Usage: ASC_KEY_PATH=<.p8> ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id> python3 asc_dev_certs.py [--check]
--check only asks App Store Connect whether it accepts the key (revokes nothing) and prints short fingerprints of the
two ids, to compare with the values on the key's page without showing them.
Needs only python3 and openssl. Never prints the key, the token or the ids.
"""
import base64, hashlib, json, os, re, subprocess, sys, time, urllib.error, urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
DEV_TYPES = ("DEVELOPMENT", "IOS_DEVELOPMENT", "MAC_APP_DEVELOPMENT")
MARK = "Created via API"
KEY_ID = re.compile(r"[A-Z0-9]{10}")
ISSUER = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")


def id_problems(key_id, issuer):
    """What is visibly wrong with the two ids (empty, spaces, swapped, wrong shape); never repeats the values."""
    out = []
    for name, v, own, other, want, other_name in (
            ("ASC_KEY_ID", key_id, KEY_ID, ISSUER, "be 10 capital letters/digits", "an Issuer ID"),
            ("ASC_ISSUER_ID", issuer, ISSUER, KEY_ID, "look like 12345678-90ab-cdef-1234-567890abcdef", "a Key ID")):
        if not v:
            out.append(f"{name} is empty")
        elif v != v.strip():
            out.append(f"{name} has spaces or a line break around it")
        elif other.fullmatch(v):
            out.append(f"{name} looks like {other_name} - the two are probably swapped")
        elif not own.fullmatch(v):
            out.append(f"{name} should {want} (it has {len(v)} characters)")
    return out


def fingerprint(value):
    return hashlib.sha256(value.encode()).hexdigest()[:8]


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def der_to_raw(der):
    """ECDSA signature DER SEQUENCE {INTEGER r, INTEGER s} -> 64 bytes r||s, the form ES256 tokens carry.
    A P-256 signature is under 128 bytes, so the SEQUENCE length is a single byte."""
    i, out = 2, b""
    for _ in range(2):
        n = der[i + 1]
        out += der[i + 2:i + 2 + n].lstrip(b"\x00").rjust(32, b"\x00")
        i += 2 + n
    return out


def jwt(key_path, key_id, issuer, now=None):
    """App Store Connect API token (ES256, valid 10 minutes)."""
    now = int(time.time() if now is None else now)
    head = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    body = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}).encode())
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path], input=f"{head}.{body}".encode(),
                         capture_output=True, check=True).stdout
    return f"{head}.{body}.{b64url(der_to_raw(der))}"


def throwaway(certs):
    """Ids of the development certificates Xcode created through the API (named "Created via API")."""
    return [c["id"] for c in certs
            if c["attributes"].get("certificateType") in DEV_TYPES
            and MARK in f'{c["attributes"].get("name") or ""} {c["attributes"].get("displayName") or ""}']


def http(method, url, token):
    req = urllib.request.Request(url, method=method, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        body = r.read()
    return json.loads(body) if body else None


def revoke_throwaway(token, api=http):
    certs, url = [], f"{API}/certificates?limit=200"
    while url:
        page = api("GET", url, token)
        certs += page["data"]
        url = page.get("links", {}).get("next")
    ids = throwaway(certs)
    for cid in ids:
        api("DELETE", f"{API}/certificates/{cid}", token)
    return ids


def check(token, api=http):
    """Read-only: one certificates page; returns how many certificates the key can see."""
    page = api("GET", f"{API}/certificates?limit=1", token)
    return page.get("meta", {}).get("paging", {}).get("total", len(page["data"]))


def main(argv):
    key_id, issuer = os.environ.get("ASC_KEY_ID", ""), os.environ.get("ASC_ISSUER_ID", "")
    if "--check" in argv:
        print(f"asc-dev-certs: fingerprints ASC_KEY_ID {fingerprint(key_id)}, ASC_ISSUER_ID {fingerprint(issuer)}")
    problems = id_problems(key_id, issuer)
    for p in problems:
        print(f"asc-dev-certs: {p}", file=sys.stderr)
    if problems:
        return 1
    try:
        token = jwt(os.environ["ASC_KEY_PATH"], key_id, issuer)
        if "--check" in argv:
            print(f"asc-dev-certs: App Store Connect accepts the key ({check(token)} certificates visible)")
            return 0
        ids = revoke_throwaway(token)
    except KeyError as e:
        print(f"asc-dev-certs: {e.args[0]} is not set", file=sys.stderr); return 1
    except subprocess.CalledProcessError:
        print("asc-dev-certs: openssl could not sign with the key file", file=sys.stderr); return 1
    except urllib.error.HTTPError as e:
        print(f"asc-dev-certs: App Store Connect answered HTTP {e.code}: {e.read()[:300].decode(errors='replace')}",
              file=sys.stderr)
        if e.code == 401:
            print("asc-dev-certs: the key was refused - ASC_KEY_ID and ASC_ISSUER_ID must be the values on the key's "
                  "page (App Store Connect > Users and Access > Integrations) and ASC_KEY_P8 that key's file",
                  file=sys.stderr)
        return 1
    except urllib.error.URLError as e:
        print(f"asc-dev-certs: App Store Connect not reachable ({e.reason})", file=sys.stderr); return 1
    except Exception as e:  # timeouts, unexpected answers: one line instead of a traceback
        print(f"asc-dev-certs: failed ({type(e).__name__})", file=sys.stderr); return 1
    print(f"asc-dev-certs: revoked {len(ids)} throwaway development certificate(s) {' '.join(ids)}".rstrip())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
