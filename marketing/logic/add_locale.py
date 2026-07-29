#!/usr/bin/env python3
"""
add_locale.py — create a new App Store locale on the editable version and stage its text.

The other scripts here can only PATCH a localization that already exists, which is the one thing
you never have when adding a language. This creates it.

Two different resources are involved, and mixing them up is the usual first mistake:

  appStoreVersionLocalizations   description, keywords, whatsNew, promotionalText, urls
  appInfoLocalizations           name, SUBTITLE, privacyPolicyUrl

So keywords and subtitle are staged through different endpoints even though App Store Connect
shows them on the same screen.

THE NAME FIELD IS NEVER WRITTEN. A new localization inherits the app name from the primary
language, which is exactly what we want — the name is frozen.

Usage:
  python3 add_locale.py --app-id 6794748918 --platform IOS --locale de-DE \\
      --keywords "a,b,c" --subtitle "..." [--description-file d.txt] [--dry-run]

Credentials come from the environment (see asc_client.py).
"""
import argparse
import sys

import asc_client as asc

EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_REVIEW"}


def editable_version(app_id, platform):
    r = asc.get(f"/v1/apps/{app_id}/appStoreVersions?filter[platform]={platform}&limit=50")
    for v in r.get("data", []):
        if v["attributes"]["appStoreState"] in EDITABLE:
            return v
    return None


def version_localization(version_id, locale):
    r = asc.get(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=100")
    for loc in r.get("data", []):
        if loc["attributes"]["locale"] == locale:
            return loc
    return None


def app_info(app_id):
    """The editable appInfo — subtitle and name hang off this, not off the version."""
    r = asc.get(f"/v1/apps/{app_id}/appInfos?limit=10")
    for info in r.get("data", []):
        state = info["attributes"].get("appStoreState") or info["attributes"].get("state")
        if state in EDITABLE or state is None:
            return info
    return (r.get("data") or [None])[0]


def app_info_localization(info_id, locale):
    r = asc.get(f"/v1/appInfos/{info_id}/appInfoLocalizations?limit=100")
    for loc in r.get("data", []):
        if loc["attributes"]["locale"] == locale:
            return loc
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app-id", required=True)
    ap.add_argument("--platform", required=True, choices=["IOS", "MAC_OS", "TV_OS"])
    ap.add_argument("--locale", required=True)
    ap.add_argument("--keywords")
    ap.add_argument("--subtitle")
    ap.add_argument("--description-file")
    ap.add_argument("--version-id", help="skip the /v1/apps lookup and use this "
                    "appStoreVersion id directly (Apple's /v1/apps resource "
                    "sometimes 500s while sub-resources still work)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if a.version_id:
        vid = a.version_id
        print(f"{a.platform} version id={vid} (given, /v1/apps lookup skipped)")
    else:
        version = editable_version(a.app_id, a.platform)
        if not version:
            sys.exit(f"no editable {a.platform} version for app {a.app_id}")
        vid = version["id"]
        print(f"{a.platform} version {version['attributes']['versionString']} "
              f"({version['attributes']['appStoreState']}) id={vid}")

    description = None
    if a.description_file:
        description = open(a.description_file).read().strip()

    # ── version localization: keywords (+ description, which Apple requires per locale) ──
    vloc = version_localization(vid, a.locale)
    attrs = {}
    if a.keywords:
        attrs["keywords"] = a.keywords
    if description:
        attrs["description"] = description

    if vloc:
        print(f"  versionLocalization {a.locale} exists (id={vloc['id']})")
        if attrs and not a.dry_run:
            asc.patch(f"/v1/appStoreVersionLocalizations/{vloc['id']}",
                      {"data": {"type": "appStoreVersionLocalizations",
                                "id": vloc["id"], "attributes": attrs}})
            print(f"  patched: {', '.join(attrs)}")
        elif attrs:
            print(f"  would patch: {', '.join(attrs)}")
    else:
        body = {"data": {"type": "appStoreVersionLocalizations",
                         "attributes": {"locale": a.locale, **attrs},
                         "relationships": {"appStoreVersion": {
                             "data": {"type": "appStoreVersions", "id": vid}}}}}
        if a.dry_run:
            print(f"  would CREATE versionLocalization {a.locale} with "
                  f"{', '.join(attrs) or '(no attributes)'}")
        else:
            r = asc.post("/v1/appStoreVersionLocalizations", body)
            print(f"  created versionLocalization {a.locale} id={r['data']['id']}")

    # ── appInfo localization: subtitle only. NEVER the name. ──
    if a.subtitle:
        try:
            info = app_info(a.app_id)
        except Exception as e:
            print(f"  ! subtitle skipped — appInfo lookup failed ({str(e).splitlines()[0][-24:]})")
            return
        if not info:
            print("  ! subtitle skipped — no appInfo found")
            return
        iloc = app_info_localization(info["id"], a.locale)
        if iloc:
            print(f"  appInfoLocalization {a.locale} exists (id={iloc['id']})")
            if not a.dry_run:
                asc.patch(f"/v1/appInfoLocalizations/{iloc['id']}",
                          {"data": {"type": "appInfoLocalizations", "id": iloc["id"],
                                    "attributes": {"subtitle": a.subtitle}}})
                print("  patched: subtitle")
            else:
                print("  would patch: subtitle")
        else:
            body = {"data": {"type": "appInfoLocalizations",
                             "attributes": {"locale": a.locale, "subtitle": a.subtitle},
                             "relationships": {"appInfo": {
                                 "data": {"type": "appInfos", "id": info["id"]}}}}}
            if a.dry_run:
                print(f"  would CREATE appInfoLocalization {a.locale} with subtitle")
            else:
                r = asc.post("/v1/appInfoLocalizations", body)
                print(f"  created appInfoLocalization {a.locale} id={r['data']['id']}")


if __name__ == "__main__":
    main()
