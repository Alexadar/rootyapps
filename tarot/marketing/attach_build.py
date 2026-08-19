#!/usr/bin/env python3
"""attach_build.py — attach the newest processed build to each draft version.

Staging, not submission: a build sitting on a PREPARE_FOR_SUBMISSION version is exactly where it
should sit until a human presses Submit. Assigning a build to an EXTERNAL TestFlight group is the
different thing — that triggers Beta App Review — and this script never does it.

Apple processes an upload for minutes after it lands, and a build in PROCESSING cannot be
attached. Run this until it reports both platforms attached; it is safe to re-run, since
attaching the build that is already attached is a no-op PATCH.
"""
import sys, time, pathlib
import jwt, requests

KEY_ID = "55B6L3J65N"
ISSUER = "057ddafb-cb0e-4410-9e0a-00e24f6e1688"
KEY_PATH = pathlib.Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{KEY_ID}.p8"
BASE = "https://api.appstoreconnect.apple.com/v1"
APP = "6802612778"


def headers():
    tok = jwt.encode(
        {"iss": ISSUER, "exp": int(time.time()) + 900, "aud": "appstoreconnect-v1"},
        KEY_PATH.read_text(), algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
    return {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"}


def main():
    H = headers()
    builds = requests.get(f"{BASE}/builds", headers=H, params={
        "filter[app]": APP, "limit": 50, "sort": "-uploadedDate",
        "include": "preReleaseVersion"}).json()
    by_platform = {}
    pre = {i["id"]: i for i in builds.get("included", []) if i["type"] == "preReleaseVersions"}
    for b in builds.get("data", []):
        rel = b.get("relationships", {}).get("preReleaseVersion", {}).get("data")
        p = pre.get(rel["id"], {}).get("attributes", {}) if rel else {}
        plat = p.get("platform", "?")
        by_platform.setdefault(plat, []).append((b, p.get("version")))

    if not by_platform:
        print("no builds visible yet — Apple is still ingesting the upload")
        return 1

    print("builds seen:")
    for plat, lst in by_platform.items():
        for b, train in lst[:3]:
            a = b["attributes"]
            print(f"  {plat:<7} train {train}  build {a.get('version')}  "
                  f"state={a.get('processingState')}  expires={a.get('expired')}")

    versions = requests.get(f"{BASE}/apps/{APP}/appStoreVersions",
                            headers=H, params={"limit": 20}).json()["data"]
    rc = 0
    for v in versions:
        plat = v["attributes"]["platform"]
        want = [b for b, _ in by_platform.get(plat, [])
                if b["attributes"].get("processingState") == "VALID"
                and not b["attributes"].get("expired")]
        if not want:
            states = [b["attributes"].get("processingState") for b, _ in by_platform.get(plat, [])]
            print(f"\n{plat}: no VALID build yet (states: {states or 'none'}) — re-run shortly")
            rc = 1
            continue
        build = want[0]
        r = requests.patch(f"{BASE}/appStoreVersions/{v['id']}", headers=H, json={
            "data": {"type": "appStoreVersions", "id": v["id"], "relationships": {
                "build": {"data": {"type": "builds", "id": build["id"]}}}}})
        ok = r.status_code in (200, 204)
        print(f"\n{plat}: attach build {build['attributes'].get('version')} -> "
              f"{'✓' if ok else '✗ ' + r.text[:300]}")
        if not ok:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
