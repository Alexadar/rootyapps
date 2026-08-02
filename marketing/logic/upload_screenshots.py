#!/usr/bin/env python3
"""
upload_screenshots.py — upload a folder of PNG screenshots to an App Store Connect
version's screenshot set (per platform / display type / locale).

Credentials come from the environment (see asc_client.py): ASC_KEY_ID, ASC_ISSUER_ID,
ASC_KEY_PATH. Nothing sensitive is stored here.

Usage:
  python3 upload_screenshots.py --app-id 6782659268 --platform IOS \
      --display APP_IPHONE_65 --locale en-US --dir <folder-of-pngs> [--replace] [--dry-run]

Display types (screenshot slot must match the image size):
  IOS 6.5"  1242x2688 -> APP_IPHONE_65      IOS 6.9"  1320x2868 -> APP_IPHONE_67
  iPad 13"  2048x2732 -> APP_IPAD_PRO_129    macOS 2880x1800   -> APP_DESKTOP
"""
import argparse, os, sys, glob
import asc_client as asc

EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_REVIEW"}


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
            return loc["id"]
    return None


def screenshot_set(loc_id, display, create=True):
    r = asc.get(f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets?limit=50")
    for s in r.get("data", []):
        if s["attributes"]["screenshotDisplayType"] == display:
            return s["id"]
    if not create:
        return None
    body = {"data": {"type": "appScreenshotSets",
                     "attributes": {"screenshotDisplayType": display},
                     "relationships": {"appStoreVersionLocalization":
                        {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}}
    return asc.post("/v1/appScreenshotSets", body)["data"]["id"]


def clear_set(set_id):
    r = asc.get(f"/v1/appScreenshotSets/{set_id}/appScreenshots?limit=50")
    for ss in r.get("data", []):
        asc.delete(f"/v1/appScreenshots/{ss['id']}")
        print(f"    - deleted existing {ss['id']}")


def upload_one(set_id, path):
    data = open(path, "rb").read()
    reserve = {"data": {"type": "appScreenshots",
                        "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
                        "relationships": {"appScreenshotSet":
                            {"data": {"type": "appScreenshotSets", "id": set_id}}}}}
    res = asc.post("/v1/appScreenshots", reserve)
    ss_id = res["data"]["id"]
    asc.upload_asset(res["data"]["attributes"]["uploadOperations"], data)
    asc.patch(f"/v1/appScreenshots/{ss_id}",
              {"data": {"type": "appScreenshots", "id": ss_id,
                        "attributes": {"uploaded": True, "sourceFileChecksum": asc.md5_hex(data)}}})
    return ss_id


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app-id", required=True)
    ap.add_argument("--platform", required=True, choices=["IOS", "MAC_OS", "TV_OS"])
    ap.add_argument("--display", required=True)
    ap.add_argument("--locale", default="en-US")
    ap.add_argument("--dir", required=True)
    ap.add_argument("--replace", action="store_true", help="delete existing shots in the set first")
    ap.add_argument("--version-id", help="skip the /v1/apps lookup and use this "
                    "appStoreVersion id directly (Apple's /v1/apps resource "
                    "sometimes 500s while sub-resources still work)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    pngs = sorted(glob.glob(os.path.join(a.dir, "*.png")))
    if not pngs:
        sys.exit(f"no PNGs in {a.dir}")

    # A given --version-id skips the /v1/apps lookup, which can 500 while sub-resources work.
    ver = ({"id": a.version_id,
            "attributes": {"versionString": "?", "appStoreState": "(given)"}}
           if a.version_id else editable_version(a.app_id, a.platform))
    if not ver:
        sys.exit(f"no editable {a.platform} version (need PREPARE_FOR_SUBMISSION). "
                 "Create/prepare the version in App Store Connect first.")
    vid, vstr, vstate = ver["id"], ver["attributes"]["versionString"], ver["attributes"]["appStoreState"]
    print(f"{a.platform} version {vstr} ({vstate}) id={vid}")

    loc = localization(vid, a.locale)
    if not loc:
        sys.exit(f"no localization {a.locale} on version {vstr}")

    print(f"{len(pngs)} screenshot(s) -> {a.display} / {a.locale}")
    if a.dry_run:
        for p in pngs:
            print(f"    (dry-run) {os.path.basename(p)}")
        return

    set_id = screenshot_set(loc, a.display)
    if a.replace:
        clear_set(set_id)
    for p in pngs:
        sid = upload_one(set_id, p)
        print(f"    ✓ {os.path.basename(p)}  -> {sid}")
    print("done.")


if __name__ == "__main__":
    main()
