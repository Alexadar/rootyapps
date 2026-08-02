#!/usr/bin/env python3
"""
push_metadata.py — localize the App Store listing for ephemeris across every locale in
marketing/aso/metadata/meta_*.json.

Writes two different resources, because App Store Connect splits the listing in two:

  appInfoLocalizations         name, subtitle          (per app, not per version)
  appStoreVersionLocalizations description, keywords,
                               promotionalText, whatsNew (per version, per platform)

Screenshots are deliberately NOT touched. Apple copies the primary language's screenshots to
any locale that has none, so metadata-only localization is valid and the English media carries
over — see developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information

Credentials come from the environment (ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH), never from
this file. --dry-run validates and prints without sending anything; run it first.

Usage:
  python3 push_metadata.py --dry-run
  python3 push_metadata.py --locales de-DE,ja        # subset
  python3 push_metadata.py                          # all
"""
import argparse, json, os, sys, glob

sys.path.insert(0, "/Users/oleksandr/Projects/rootyapps/marketing/logic")
import asc_client as asc

APP_ID = "6782659268"
HERE = os.path.dirname(os.path.abspath(__file__))

# App Store limits. Exceeding any of these is a hard API rejection, so we check locally first
# rather than discovering it 40 requests in.
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100,
          "promotionalText": 170, "description": 4000, "whatsNew": 4000}
VERSION_FIELDS = ("description", "keywords", "promotionalText", "whatsNew")
INFO_FIELDS = ("name", "subtitle")
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY"}


def load():
    """Merge meta_*.json into {locale: {field: value}}."""
    meta = {}
    for path in sorted(glob.glob(os.path.join(HERE, "meta_*.json"))):
        blob = json.load(open(path))
        whatsnew = os.path.basename(path) == "meta_whatsnew.json"
        for locale, value in blob.items():
            if locale.startswith("_"):
                continue
            entry = meta.setdefault(locale, {})
            if whatsnew:
                entry["whatsNew"] = value
            else:
                entry.update({k: v for k, v in value.items() if not k.startswith("_")})
    return meta


def validate(meta):
    problems = []
    for locale, fields in sorted(meta.items()):
        for field, limit in LIMITS.items():
            value = fields.get(field)
            if value is None:
                problems.append(f"{locale}: missing {field}")
                continue
            if len(value) > limit:
                problems.append(f"{locale}: {field} is {len(value)} chars, limit {limit}")
        # Keywords are one comma-separated field; a space after a comma wastes a character.
        kw = fields.get("keywords", "")
        if ", " in kw:
            problems.append(f"{locale}: keywords contain ', ' — drop the space, it costs a char")
    return problems


def editable_versions():
    """The draft version per platform — that's what we're allowed to edit."""
    out = {}
    for platform in ("IOS", "MAC_OS"):
        r = asc.get(f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]={platform}&limit=50")
        for v in r.get("data", []):
            if v["attributes"]["appStoreState"] in EDITABLE:
                out[platform] = v["id"]
                break
    return out


def upsert_version_localization(version_id, locale, fields, dry):
    existing = {d["attributes"]["locale"]: d["id"] for d in
                asc.get(f"/v1/appStoreVersions/{version_id}"
                        f"/appStoreVersionLocalizations?limit=100")["data"]}
    attrs = {f: fields[f] for f in VERSION_FIELDS if f in fields}
    if locale in existing:
        if dry:
            return f"PATCH version loc {locale}"
        asc.patch(f"/v1/appStoreVersionLocalizations/{existing[locale]}",
                  {"data": {"type": "appStoreVersionLocalizations",
                            "id": existing[locale], "attributes": attrs}})
        return f"updated {locale}"
    if dry:
        return f"CREATE version loc {locale}"
    asc.post("/v1/appStoreVersionLocalizations",
             {"data": {"type": "appStoreVersionLocalizations",
                       "attributes": {**attrs, "locale": locale},
                       "relationships": {"appStoreVersion": {
                           "data": {"type": "appStoreVersions", "id": version_id}}}}})
    return f"created {locale}"


def upsert_info_localization(info_id, locale, fields, dry):
    existing = {d["attributes"]["locale"]: d["id"] for d in
                asc.get(f"/v1/appInfos/{info_id}/appInfoLocalizations?limit=100")["data"]}
    attrs = {f: fields[f] for f in INFO_FIELDS if f in fields}
    if locale in existing:
        if dry:
            return f"PATCH info loc {locale}"
        asc.patch(f"/v1/appInfoLocalizations/{existing[locale]}",
                  {"data": {"type": "appInfoLocalizations",
                            "id": existing[locale], "attributes": attrs}})
        return f"updated {locale}"
    if dry:
        return f"CREATE info loc {locale}"
    asc.post("/v1/appInfoLocalizations",
             {"data": {"type": "appInfoLocalizations",
                       "attributes": {**attrs, "locale": locale},
                       "relationships": {"appInfo": {
                           "data": {"type": "appInfos", "id": info_id}}}}})
    return f"created {locale}"


def editable_app_info():
    for i in asc.get(f"/v1/apps/{APP_ID}/appInfos?limit=10")["data"]:
        if i["attributes"].get("appStoreState") in EDITABLE:
            return i["id"]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--locales", help="comma-separated subset")
    args = ap.parse_args()

    meta = load()
    if args.locales:
        want = set(args.locales.split(","))
        meta = {k: v for k, v in meta.items() if k in want}

    problems = validate(meta)
    print(f"{len(meta)} locales: {', '.join(sorted(meta))}\n")
    for locale in sorted(meta):
        f = meta[locale]
        print(f"  {locale:6} name={len(f.get('name','')):2}/30  sub={len(f.get('subtitle','')):2}/30  "
              f"kw={len(f.get('keywords','')):3}/100  promo={len(f.get('promotionalText','')):3}/170  "
              f"desc={len(f.get('description','')):4}/4000  new={len(f.get('whatsNew','')):4}/4000")
    if problems:
        print("\nPROBLEMS:")
        for p in problems:
            print("  ✗ " + p)
        sys.exit(1)
    print("\nAll fields within limits.")

    versions = editable_versions()
    info_id = editable_app_info()
    print(f"editable versions: {versions}\neditable appInfo: {info_id}\n")
    if not versions or not info_id:
        sys.exit("No editable draft version/appInfo — nothing to write.")

    for locale in sorted(meta):
        print(f"  {locale}: {upsert_info_localization(info_id, locale, meta[locale], args.dry_run)}")
        for platform, vid in versions.items():
            r = upsert_version_localization(vid, locale, meta[locale], args.dry_run)
            print(f"    {platform}: {r}")
    print("\nDone." + (" (dry run — nothing sent)" if args.dry_run else ""))


if __name__ == "__main__":
    main()
