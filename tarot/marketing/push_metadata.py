#!/usr/bin/env python3
"""push_metadata.py — write marketing/aso/en/metadata.yaml into App Store Connect.

Staging only: text fields and categories on the DRAFT versions. It creates nothing, submits
nothing, and touches no price.

The write paths are not where you would guess, and getting them wrong 404s or silently writes to
the wrong scope (autoaso §6.6):

  description, keywords, promotionalText, supportUrl, marketingUrl
      -> PATCH /v1/appStoreVersionLocalizations/{id}   per VERSION, so once per platform
  subtitle, privacyPolicyUrl
      -> PATCH /v1/appInfoLocalizations/{id}           per APP INFO, shared across platforms
  primary/secondary category
      -> PATCH /v1/appInfos/{id} with a relationships body; the documented
         /relationships/primaryCategory endpoint returns 403 FORBIDDEN_ERROR

The name field is never written. A new localization inherits the app name from the primary
language, which is what we want; writing it per-locale is how an app gets renamed in one market.
"""
import sys, time, json, pathlib
import jwt, requests, yaml

KEY_ID = "55B6L3J65N"
ISSUER = "057ddafb-cb0e-4410-9e0a-00e24f6e1688"
KEY_PATH = pathlib.Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{KEY_ID}.p8"
BASE = "https://api.appstoreconnect.apple.com/v1"
META = pathlib.Path(__file__).parent / "aso/en/metadata.yaml"


def headers():
    tok = jwt.encode(
        {"iss": ISSUER, "exp": int(time.time()) + 900, "aud": "appstoreconnect-v1"},
        KEY_PATH.read_text(), algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"})
    return {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"}


def check(r, what):
    if r.status_code not in (200, 201, 204):
        print(f"  ✗ {what}: {r.status_code} {r.text[:400]}")
        return False
    print(f"  ✓ {what}")
    return True


def main():
    m = yaml.safe_load(META.read_text())
    app = m["app_id"]
    H = headers()

    # Field lengths are enforced by the API, but a 409 in the middle of a run is a worse way to
    # find out than a line here.
    assert len(m["subtitle"]) <= 30, f"subtitle {len(m['subtitle'])} > 30"
    assert len(m["keywords"]) <= 100, f"keywords {len(m['keywords'])} > 100"
    assert len(m["promotional_text"]) <= 170, f"promo {len(m['promotional_text'])} > 170"
    print(f"subtitle {len(m['subtitle'])}/30 · keywords {len(m['keywords'])}/100 · "
          f"promo {len(m['promotional_text'])}/170 · description {len(m['description'])}/4000")

    # ── per-version text, once per platform ──────────────────────────────────
    versions = requests.get(f"{BASE}/apps/{app}/appStoreVersions",
                            headers=H, params={"limit": 20}).json()["data"]
    for v in versions:
        plat = v["attributes"]["platform"]
        state = v["attributes"].get("appStoreState") or v["attributes"].get("appVersionState")
        print(f"\n{plat} {v['attributes']['versionString']} ({state})")
        locs = requests.get(f"{BASE}/appStoreVersions/{v['id']}/appStoreVersionLocalizations",
                            headers=H, params={"limit": 50}).json()["data"]
        loc = next((l for l in locs if l["attributes"]["locale"] == m["locale"]), None)
        if loc is None:
            r = requests.post(f"{BASE}/appStoreVersionLocalizations", headers=H, json={"data": {
                "type": "appStoreVersionLocalizations",
                "attributes": {"locale": m["locale"]},
                "relationships": {"appStoreVersion": {
                    "data": {"type": "appStoreVersions", "id": v["id"]}}}}})
            if not check(r, f"create {m['locale']} localization"):
                continue
            loc = r.json()["data"]
        r = requests.patch(f"{BASE}/appStoreVersionLocalizations/{loc['id']}", headers=H, json={
            "data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {
                "description": m["description"],
                "keywords": m["keywords"],
                "promotionalText": m["promotional_text"],
                "supportUrl": m["support_url"],
                "marketingUrl": m["marketing_url"],
            }}})
        check(r, "description / keywords / promo / urls")

        # Copyright lives on the version itself, not on the localization.
        r = requests.patch(f"{BASE}/appStoreVersions/{v['id']}", headers=H, json={
            "data": {"type": "appStoreVersions", "id": v["id"],
                     "attributes": {"copyright": m["copyright"]}}})
        check(r, "copyright")

    # ── app-level: subtitle, privacy URL, categories ─────────────────────────
    info = requests.get(f"{BASE}/apps/{app}/appInfos", headers=H).json()["data"][0]
    print(f"\nappInfo {info['id']}")
    locs = requests.get(f"{BASE}/appInfos/{info['id']}/appInfoLocalizations",
                        headers=H, params={"limit": 50}).json()["data"]
    loc = next((l for l in locs if l["attributes"]["locale"] == m["locale"]), None)
    if loc is None:
        r = requests.post(f"{BASE}/appInfoLocalizations", headers=H, json={"data": {
            "type": "appInfoLocalizations",
            "attributes": {"locale": m["locale"]},
            "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info["id"]}}}}})
        check(r, f"create {m['locale']} appInfoLocalization")
        loc = r.json()["data"]
    r = requests.patch(f"{BASE}/appInfoLocalizations/{loc['id']}", headers=H, json={
        "data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": {
            "subtitle": m["subtitle"],
            "privacyPolicyUrl": m["privacy_policy_url"],
        }}})
    check(r, "subtitle / privacy url")

    r = requests.patch(f"{BASE}/appInfos/{info['id']}", headers=H, json={
        "data": {"type": "appInfos", "id": info["id"], "relationships": {
            "primaryCategory": {"data": {"type": "appCategories", "id": m["primary_category"]}},
            "secondaryCategory": {"data": {"type": "appCategories", "id": m["secondary_category"]}},
        }}})
    check(r, f"categories {m['primary_category']} / {m['secondary_category']}")

    print("\nStaged. Nothing submitted; App Privacy is not on the API and stays a web-UI task.")


if __name__ == "__main__":
    main()
