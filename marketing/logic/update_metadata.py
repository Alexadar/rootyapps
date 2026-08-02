#!/usr/bin/env python3
"""
update_metadata.py — patch the editable App Store version's localized text
(description / keywords / promotionalText / whatsNew / marketingUrl / supportUrl)
for a platform + locale.

Credentials come from the environment (see asc_client.py). Nothing sensitive is stored here.

Usage:
  python3 update_metadata.py --app-id 6782659268 --platform IOS --locale en-US \
      [--description-file d.txt] [--whats-new-file w.txt] [--keywords "a,b,c"] \
      [--promo "..."] [--marketing-url URL] [--support-url URL] [--dry-run]

Only the fields you pass are changed. Limits (App Store): description 4000, keywords 100,
promotionalText 170, whatsNew 4000.
"""
import argparse, sys
import asc_client as asc

EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_REVIEW"}
LIMITS = {"description": 4000, "keywords": 100, "promotionalText": 170, "whatsNew": 4000}


def editable_version(app_id, platform):
    r = asc.get(f"/v1/apps/{app_id}/appStoreVersions?filter[platform]={platform}&limit=50")
    for v in r.get("data", []):
        if v["attributes"]["appStoreState"] in EDITABLE:
            return v
    return None


def localization(version_id, locale):
    r = asc.get(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=50")
    for loc in r.get("data", []):
        if loc["attributes"]["locale"] == locale:
            return loc
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app-id", required=True)
    ap.add_argument("--platform", required=True, choices=["IOS", "MAC_OS", "TV_OS"])
    ap.add_argument("--locale", default="en-US")
    ap.add_argument("--description-file")
    ap.add_argument("--whats-new-file")
    ap.add_argument("--keywords")
    ap.add_argument("--promo")
    ap.add_argument("--marketing-url")
    ap.add_argument("--support-url")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    attrs = {}
    if a.description_file: attrs["description"] = open(a.description_file).read().rstrip("\n") + "\n"
    if a.whats_new_file:   attrs["whatsNew"] = open(a.whats_new_file).read().rstrip("\n") + "\n"
    if a.keywords is not None:      attrs["keywords"] = a.keywords
    if a.promo is not None:         attrs["promotionalText"] = a.promo
    if a.marketing_url is not None: attrs["marketingUrl"] = a.marketing_url
    if a.support_url is not None:   attrs["supportUrl"] = a.support_url
    if not attrs:
        sys.exit("nothing to update (pass at least one field)")

    for k, v in attrs.items():
        if k in LIMITS and len(v) > LIMITS[k]:
            sys.exit(f"{k} is {len(v)} chars, over the {LIMITS[k]} limit")

    ver = editable_version(a.app_id, a.platform)
    if not ver:
        sys.exit(f"no editable {a.platform} version.")
    vid, vstr = ver["id"], ver["attributes"]["versionString"]
    loc = localization(vid, a.locale)
    if not loc:
        sys.exit(f"no localization {a.locale} on version {vstr}")

    print(f"{a.platform} version {vstr} / {a.locale} — updating: {', '.join(attrs)}")
    for k in attrs:
        preview = attrs[k].replace("\n", " ")
        print(f"    {k}: {preview[:80]}{'…' if len(preview) > 80 else ''}")
    if a.dry_run:
        print("  (dry-run, not sent)")
        return

    asc.patch(f"/v1/appStoreVersionLocalizations/{loc['id']}",
              {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": attrs}})
    print("  ✓ updated.")


if __name__ == "__main__":
    main()
