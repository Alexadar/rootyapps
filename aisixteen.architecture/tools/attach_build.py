#!/usr/bin/env python3
"""
attach_build.py — wait for an uploaded build to finish processing, then attach it to the
App Store version that already exists on the record.

Deliberately narrow. It does exactly two things:

    1. polls until the newest build for a platform leaves PROCESSING;
    2. PATCHes that build onto the matching appStoreVersion.

It does NOT create a version, submit for review, set a price, set territory availability,
choose a category, set an age rating, or touch TestFlight groups. Every one of those is the
owner's decision, and none of them is reversible by re-running a script.

Credentials come from the environment only (ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH), the same
as marketing/logic/asc_client.py, so nothing sensitive lives in this file.

    python3 tools/attach_build.py --platform IOS
    python3 tools/attach_build.py --platform MAC_OS --version 1.0
"""
import argparse
import json
import os
import sys
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "marketing", "logic"))
from asc_client import token, BASE  # noqa: E402

APP_ID = "6475354624"          # AISixteen Architecture
BUNDLE_ID = "oleksandr.aisixteen.architecture"


def request(method, path, body=None, tok=None):
    data = json.dumps(body).encode() if body is not None else None
    req = Request(BASE + path, data=data, method=method,
                  headers={"Authorization": "Bearer " + tok,
                           "Content-Type": "application/json"})
    try:
        with urlopen(req) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except HTTPError as error:
        detail = error.read().decode()
        raise SystemExit(f"{method} {path} -> {error.code}\n{detail}")


def newest_build(tok, platform, version):
    """The most recent build for a platform, or None."""
    query = (f"/v1/builds?filter[app]={APP_ID}"
             f"&filter[preReleaseVersion.platform]={platform}"
             f"&sort=-uploadedDate&limit=5"
             f"&fields[builds]=version,processingState,uploadedDate,expired")
    for build in request("GET", query, tok=tok)["data"]:
        if build["attributes"].get("expired"):
            continue
        return build
    return None


def version_id(tok, platform, version):
    versions = request("GET",
                       f"/v1/apps/{APP_ID}/appStoreVersions?limit=50"
                       f"&fields[appStoreVersions]=versionString,platform,appStoreState",
                       tok=tok)["data"]
    for entry in versions:
        attributes = entry["attributes"]
        if attributes["platform"] == platform and attributes["versionString"] == version:
            return entry["id"], attributes["appStoreState"]
    available = ", ".join(f"{v['attributes']['platform']} {v['attributes']['versionString']}"
                          for v in versions)
    raise SystemExit(f"No {platform} version {version} on the record. Present: {available}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", required=True, choices=["IOS", "MAC_OS", "VISION_OS"])
    parser.add_argument("--version", default="1.0")
    # Processing usually takes 10–30 minutes; a build cannot be attached before it finishes.
    parser.add_argument("--timeout", type=int, default=3600)
    parser.add_argument("--poll", type=int, default=60)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    tok = token()
    deadline = time.time() + args.timeout
    build = None

    while time.time() < deadline:
        tok = token()                       # the JWT expires in 20 minutes; polling can outlast it
        build = newest_build(tok, args.platform, args.version)
        if build is None:
            print(f"  {args.platform}: no build uploaded yet …")
        else:
            state = build["attributes"]["processingState"]
            number = build["attributes"]["version"]
            print(f"  {args.platform}: build {number} is {state}")
            if state == "VALID":
                break
            if state in ("FAILED", "INVALID"):
                raise SystemExit(f"{args.platform} build {number} finished as {state} — not attaching.")
        time.sleep(args.poll)
    else:
        raise SystemExit(f"{args.platform}: still processing after {args.timeout}s. "
                         "Re-run this script; nothing has been changed.")

    version, state = version_id(tok, args.platform, args.version)
    print(f"  {args.platform}: version {args.version} is {state} (id {version})")

    if args.dry_run:
        print(f"  dry run — would attach build {build['id']} to version {version}")
        return

    request("PATCH", f"/v1/appStoreVersions/{version}/relationships/build",
            body={"data": {"type": "builds", "id": build["id"]}}, tok=tok)
    print(f"  ✓ attached build {build['attributes']['version']} to {args.platform} {args.version}")
    print("    (attached only — NOT submitted, NOT released)")


if __name__ == "__main__":
    main()
