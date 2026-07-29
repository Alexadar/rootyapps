#!/usr/bin/env python3
"""
asc_client.py — minimal App Store Connect API client (auth + media upload helpers).

Credentials are read from the ENVIRONMENT ONLY — nothing sensitive is hard-coded here,
so this file is safe to commit:

    ASC_KEY_ID      e.g. 55B6L3J65N
    ASC_ISSUER_ID   e.g. 057ddafb-....
    ASC_KEY_PATH    path to the .p8 private key (keep it in the gitignored keys/ dir)

The JWT and the private key are never printed. Requires PyJWT + cryptography
(available in the `fantastic` conda env).
"""
import os, time, json, hashlib
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import jwt

BASE = "https://api.appstoreconnect.apple.com"


def _creds():
    key_id = os.environ.get("ASC_KEY_ID")
    issuer = os.environ.get("ASC_ISSUER_ID")
    key_path = os.environ.get("ASC_KEY_PATH")
    missing = [n for n, v in (("ASC_KEY_ID", key_id), ("ASC_ISSUER_ID", issuer),
                              ("ASC_KEY_PATH", key_path)) if not v]
    if missing:
        raise SystemExit(f"Missing env credentials: {', '.join(missing)} "
                         "(set them before running; never commit the .p8).")
    return key_id, issuer, key_path


def token():
    key_id, issuer, key_path = _creds()
    with open(key_path, "r") as f:
        private_key = f.read()
    payload = {"iss": issuer, "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256",
                      headers={"alg": "ES256", "kid": key_id, "typ": "JWT"})


def request(method, path, body=None, headers=None, raw=False):
    """JSON API request. `path` may be absolute or start with /v1/…"""
    url = path if path.startswith("http") else BASE + path
    data = None
    hdrs = {"Authorization": f"Bearer {token()}"}
    if body is not None:
        data = json.dumps(body).encode()
        hdrs["Content-Type"] = "application/json"
    if headers:
        hdrs.update(headers)
    req = Request(url, data=data, headers=hdrs, method=method)
    try:
        with urlopen(req) as resp:
            payload = resp.read()
            return None if raw else (json.loads(payload) if payload else {})
    except HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise RuntimeError(f"{method} {url} -> {e.code}\n{detail}") from None


def get(path):    return request("GET", path)
def post(path, body): return request("POST", path, body)
def patch(path, body): return request("PATCH", path, body)
def delete(path): return request("DELETE", path, raw=True)


def upload_asset(operations, data: bytes):
    """Execute the `uploadOperations` returned by a reservation (PUT each chunk)."""
    for op in operations:
        chunk = data[op["offset"]: op["offset"] + op["length"]]
        hdrs = {h["name"]: h["value"] for h in (op.get("requestHeaders") or [])}
        req = Request(op["url"], data=chunk, headers=hdrs, method=op["method"])
        try:
            with urlopen(req) as _:
                pass
        except HTTPError as e:
            raise RuntimeError(f"upload chunk failed: {e.code} {e.read().decode(errors='replace')}") from None


def md5_hex(data: bytes) -> str:
    return hashlib.md5(data).hexdigest()
