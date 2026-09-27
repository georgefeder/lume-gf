# Tests for asc_dev_certs.py. Run: python3 -m unittest discover -s ci -p 'test_*.py'
# Uses a throwaway P-256 key generated here (same PKCS#8 format as Apple's .p8 files); no network.
import base64, hashlib, json, os, subprocess, tempfile, unittest
import asc_dev_certs as adc


def unb64(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def raw_to_der(raw):
    def integer(b):
        b = b.lstrip(b"\x00") or b"\x00"
        if b[0] & 0x80:
            b = b"\x00" + b
        return b"\x02" + bytes([len(b)]) + b
    body = integer(raw[:32]) + integer(raw[32:])
    return b"\x30" + bytes([len(body)]) + body


class Key:
    def __enter__(self):
        self.dir = tempfile.TemporaryDirectory()
        d = self.dir.name
        self.key, self.pub = os.path.join(d, "AuthKey_TEST.p8"), os.path.join(d, "pub.pem")
        ec = subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout"],
                            capture_output=True, check=True).stdout
        p8 = subprocess.run(["openssl", "pkcs8", "-topk8", "-nocrypt"], input=ec, capture_output=True, check=True).stdout
        with open(self.key, "wb") as f:
            f.write(p8)
        subprocess.run(["openssl", "ec", "-in", self.key, "-pubout", "-out", self.pub], capture_output=True, check=True)
        return self

    def verifies(self, msg, raw_sig):
        sig = os.path.join(self.dir.name, "sig.der")
        with open(sig, "wb") as f:
            f.write(raw_to_der(raw_sig))
        r = subprocess.run(["openssl", "dgst", "-sha256", "-verify", self.pub, "-signature", sig],
                           input=msg, capture_output=True)
        return r.returncode == 0

    def __exit__(self, *a):
        self.dir.cleanup()


def cert(id_, ctype, name, display=None):
    return {"type": "certificates", "id": id_,
            "attributes": {"certificateType": ctype, "name": name, "displayName": display}}


class JwtTest(unittest.TestCase):
    def test_token_is_es256_signed_with_the_key(self):
        with Key() as k:
            tok = adc.jwt(k.key, "KEY123", "issuer-uuid", now=1_700_000_000)
            head, body, sig = tok.split(".")
            raw = unb64(sig)
            self.assertEqual(len(raw), 64)
            self.assertTrue(k.verifies(f"{head}.{body}".encode(), raw))

    def test_token_claims_match_app_store_connect_rules(self):
        with Key() as k:
            head, body, _ = adc.jwt(k.key, "KEY123", "issuer-uuid", now=1_700_000_000).split(".")
        self.assertEqual(json.loads(unb64(head)), {"alg": "ES256", "kid": "KEY123", "typ": "JWT"})
        claims = json.loads(unb64(body))
        self.assertEqual(claims["iss"], "issuer-uuid")
        self.assertEqual(claims["aud"], "appstoreconnect-v1")
        self.assertEqual(claims["iat"], 1_700_000_000)
        self.assertLessEqual(claims["exp"] - claims["iat"], 1200)  # Apple rejects tokens valid > 20 min

    def test_der_signature_with_short_and_padded_integers(self):
        r = b"\x01" * 31                   # 31-byte r (leading zero byte dropped by DER)
        s = b"\x00" + b"\x80" + b"\x02" * 31  # 33-byte s (sign byte added by DER)
        der = b"\x30\x44" + b"\x02\x1f" + r + b"\x02\x21" + s
        self.assertEqual(adc.der_to_raw(der), b"\x00" + r + s[1:])


class SelectionTest(unittest.TestCase):
    def test_only_throwaway_development_certificates_are_selected(self):
        certs = [cert("a", "DEVELOPMENT", "Apple Development: Created via API", "Created via API"),
                 cert("b", "DEVELOPMENT", "Apple Development: Georgs Feders", "Georgs Feders"),
                 cert("c", "DISTRIBUTION", "Apple Distribution: Created via API", "Created via API"),
                 cert("d", "IOS_DEVELOPMENT", "iOS Development: Created via API"),
                 cert("e", "DISTRIBUTION", "Apple Distribution: Georgs Feders")]
        self.assertEqual(adc.throwaway(certs), ["a", "d"])


class FakeApi:
    def __init__(self, pages):
        self.pages, self.calls = pages, []

    def __call__(self, method, url, token):
        self.calls.append((method, url, token))
        return self.pages.pop(0) if method == "GET" else None


class RevokeTest(unittest.TestCase):
    def test_lists_every_page_and_revokes_only_throwaway_certificates(self):
        api = FakeApi([
            {"data": [cert("a", "DEVELOPMENT", "Apple Development: Created via API")],
             "links": {"next": "https://api.appstoreconnect.apple.com/v1/certificates?cursor=2"}},
            {"data": [cert("b", "DEVELOPMENT", "Apple Development: Georgs Feders"),
                      cert("c", "DEVELOPMENT", "Apple Development: Created via API")], "links": {}}])
        self.assertEqual(adc.revoke_throwaway("TOKEN", api), ["a", "c"])
        self.assertEqual([c[:2] for c in api.calls], [
            ("GET", "https://api.appstoreconnect.apple.com/v1/certificates?limit=200"),
            ("GET", "https://api.appstoreconnect.apple.com/v1/certificates?cursor=2"),
            ("DELETE", "https://api.appstoreconnect.apple.com/v1/certificates/a"),
            ("DELETE", "https://api.appstoreconnect.apple.com/v1/certificates/c")])
        self.assertTrue(all(c[2] == "TOKEN" for c in api.calls))

    def test_nothing_to_revoke(self):
        api = FakeApi([{"data": [], "links": {}}])
        self.assertEqual(adc.revoke_throwaway("TOKEN", api), [])
        self.assertEqual(len(api.calls), 1)


class IdCheckTest(unittest.TestCase):
    KEY, ISS = "ABCDE12345", "12345678-90ab-cdef-1234-567890abcdef"

    def test_well_formed_ids_have_no_problems(self):
        self.assertEqual(adc.id_problems(self.KEY, self.ISS), [])

    def test_empty_values(self):
        self.assertEqual(adc.id_problems("", ""), ["ASC_KEY_ID is empty", "ASC_ISSUER_ID is empty"])

    def test_spaces_or_line_breaks_around_a_value(self):
        self.assertEqual(adc.id_problems(self.KEY + "\n", " " + self.ISS),
                         ["ASC_KEY_ID has spaces or a line break around it",
                          "ASC_ISSUER_ID has spaces or a line break around it"])

    def test_swapped_values(self):
        self.assertEqual(adc.id_problems(self.ISS, self.KEY),
                         ["ASC_KEY_ID looks like an Issuer ID - the two are probably swapped",
                          "ASC_ISSUER_ID looks like a Key ID - the two are probably swapped"])

    def test_wrong_shape(self):
        self.assertEqual(adc.id_problems("abc", "nope"),
                         ["ASC_KEY_ID should be 10 capital letters/digits (it has 3 characters)",
                          "ASC_ISSUER_ID should look like 12345678-90ab-cdef-1234-567890abcdef (it has 4 characters)"])

    def test_fingerprint_is_the_start_of_the_sha256(self):
        self.assertEqual(adc.fingerprint(self.KEY), hashlib.sha256(self.KEY.encode()).hexdigest()[:8])


class CheckModeTest(unittest.TestCase):
    def test_check_only_reads_one_page_and_returns_the_total(self):
        api = FakeApi([{"data": [cert("a", "DEVELOPMENT", "Apple Development: Created via API")],
                        "meta": {"paging": {"total": 5, "limit": 1}}, "links": {}}])
        self.assertEqual(adc.check("TOKEN", api), 5)
        self.assertEqual([c[:2] for c in api.calls],
                         [("GET", "https://api.appstoreconnect.apple.com/v1/certificates?limit=1")])


if __name__ == "__main__":
    unittest.main()
