#!/usr/bin/env python3
"""
ads_client.py — minimal Apple Ads (Campaign Management API v5) client.

Sibling of `asc_client.py`, but the auth is a DIFFERENT scheme and that is the whole reason this
file exists rather than a flag on the ASC client:

    App Store Connect : sign a JWT, send it as the bearer token. One hop.
    Apple Ads         : sign a JWT as a *client secret*, exchange it at Apple's OAuth endpoint for
                        a short-lived access token, and send THAT. Two hops.

Credentials come from the ENVIRONMENT ONLY, so this file is safe to commit (see .env.example):

    ADS_CLIENT_ID           SEARCHADS.<uuid>   — returned when you upload the public key
    ADS_TEAM_ID             SEARCHADS.<uuid>   — likewise
    ADS_KEY_ID              <uuid>             — likewise; becomes the JWT `kid`
    ADS_PRIVATE_KEY_PATH    path to the EC P-256 private key in the gitignored keys/ dir
    ADS_ORG_ID              optional — discovered by `me()` on first use and cached in-process

Getting those three IDs is a one-time browser task and cannot be automated: an Account Admin
assigns an API role under Account Settings > User Management, then that user uploads the public key
under Account Settings > API. There is no API for creating API access.

Verified against Apple's documentation on 2026-08-03.
Requires PyJWT + cryptography (the `fantastic` conda env).
"""
import os, time, json
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import jwt

BASE = "https://api.searchads.apple.com/api/v5"
TOKEN_URL = "https://appleid.apple.com/auth/oauth2/token"
AUDIENCE = "https://appleid.apple.com"
SCOPE = "searchadsorg"

# Apple caps the client secret at 180 days. Ours is minted per process and lives for minutes —
# a long-lived secret on disk is a credential to leak, and there is no benefit to it here.
_CLIENT_SECRET_TTL = 600

_token_cache = {"access_token": None, "expires_at": 0.0}
_org_cache = {"org_id": None}


def _creds():
    vals = {n: os.environ.get(n) for n in
            ("ADS_CLIENT_ID", "ADS_TEAM_ID", "ADS_KEY_ID", "ADS_PRIVATE_KEY_PATH")}
    missing = [n for n, v in vals.items() if not v]
    if missing:
        raise SystemExit(
            "Missing env credentials: " + ", ".join(missing) + "\n"
            "Set them in .env (see .env.example), then:  set -a; . ./.env; set +a\n"
            "The three IDs come from ads.apple.com > Account Settings > API after uploading\n"
            "keys/apple-ads-public-key.pem.")
    return vals


def client_secret() -> str:
    """The ES256 JWT that Apple's OAuth endpoint accepts in place of a password."""
    c = _creds()
    with open(c["ADS_PRIVATE_KEY_PATH"], "r") as f:
        private_key = f.read()
    now = int(time.time())
    payload = {
        "sub": c["ADS_CLIENT_ID"],      # who the secret represents
        "aud": AUDIENCE,
        "iss": c["ADS_TEAM_ID"],        # who issued it
        "iat": now,
        "exp": now + _CLIENT_SECRET_TTL,
    }
    return jwt.encode(payload, private_key, algorithm="ES256",
                      headers={"alg": "ES256", "kid": c["ADS_KEY_ID"]})


def token() -> str:
    """A bearer access token, cached until shortly before it expires (Apple's TTL is 3600s)."""
    if _token_cache["access_token"] and time.time() < _token_cache["expires_at"]:
        return _token_cache["access_token"]

    c = _creds()
    form = urlencode({
        "grant_type": "client_credentials",
        "client_id": c["ADS_CLIENT_ID"],
        "client_secret": client_secret(),
        "scope": SCOPE,
    }).encode()
    req = Request(TOKEN_URL, data=form, method="POST",
                  headers={"Host": "appleid.apple.com",
                           "Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urlopen(req) as resp:
            payload = json.loads(resp.read())
    except HTTPError as e:
        detail = e.read().decode(errors="replace")
        # `invalid_client` here nearly always means the JWT claims are wrong — sub/iss swapped, a
        # stale kid, or a key that is not the pair whose public half Apple holds. It does not mean
        # the account lacks access.
        raise RuntimeError(f"token exchange -> {e.code}\n{detail}") from None

    _token_cache["access_token"] = payload["access_token"]
    _token_cache["expires_at"] = time.time() + int(payload.get("expires_in", 3600)) - 60
    return _token_cache["access_token"]


def org_id() -> str:
    """The orgId every request needs. Discovered once, then cached."""
    if _org_cache["org_id"]:
        return _org_cache["org_id"]
    env = os.environ.get("ADS_ORG_ID")
    if env:
        _org_cache["org_id"] = env
        return env
    _org_cache["org_id"] = str(me()["data"]["parentOrgId"])
    return _org_cache["org_id"]


def request(method, path, body=None, params=None, with_context=True):
    """`path` may be absolute or start with /… (relative to the v5 base)."""
    url = path if path.startswith("http") else BASE + path
    if params:
        url += ("&" if "?" in url else "?") + urlencode(params)

    hdrs = {"Authorization": f"Bearer {token()}"}
    # Required on everything EXCEPT the two bootstrap calls — which is precisely why one of them
    # has to be how you discover the value in the first place.
    if with_context:
        hdrs["X-AP-Context"] = f"orgId={org_id()}"

    data = None
    if body is not None:
        data = json.dumps(body).encode()
        hdrs["Content-Type"] = "application/json"

    req = Request(url, data=data, headers=hdrs, method=method)
    try:
        with urlopen(req) as resp:
            payload = resp.read()
            return json.loads(payload) if payload else {}
    except HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise RuntimeError(f"{method} {url} -> {e.code}\n{detail}") from None


def get(path, params=None):      return request("GET", path, params=params)
def post(path, body):            return request("POST", path, body)
def put(path, body):             return request("PUT", path, body)
def delete(path):                return request("DELETE", path)


# ── the two endpoints that do not take X-AP-Context ───────────────────────────

def me():
    """Get Me Details — returns userId and parentOrgId. The orgId bootstrap."""
    return request("GET", "/me", with_context=False)


def acls():
    """Get User ACL — every org this API user can act on, with its roles."""
    return request("GET", "/acls", with_context=False)


if __name__ == "__main__":
    # Read-only smoke test: proves the credentials work end to end and prints what you can reach.
    # Spends nothing and creates nothing.
    print("1. client secret … ", end="", flush=True)
    client_secret(); print("signed")

    print("2. access token  … ", end="", flush=True)
    token(); print("ok (cached %ds)" % int(_token_cache["expires_at"] - time.time()))

    print("3. Get Me Details… ", end="", flush=True)
    d = me()["data"]
    print(f"userId={d.get('userId')} parentOrgId={d.get('parentOrgId')}")

    print("4. Get User ACL  … ", end="", flush=True)
    rows = acls().get("data", [])
    print(f"{len(rows)} org(s)")
    for r in rows:
        print(f"     orgId={r.get('orgId')}  {r.get('orgName')!r}  roles={r.get('roleNames')}  "
              f"currency={r.get('currency')}")
    print("\nPut ADS_ORG_ID in .env to skip the discovery call on every run.")
