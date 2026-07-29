#!/usr/bin/env python3
"""
upload_previews.py — upload an App Store app-preview video to a version's preview set
(per platform / preview type / locale). Apple then processes the video asynchronously.

Credentials come from the environment (see asc_client.py). Nothing sensitive is stored here.

Usage:
  python3 upload_previews.py --app-id 6782659268 --platform IOS \
      --display APP_IPHONE_65 --locale en-US --file <preview.mp4> \
      [--frame 00:00:04] [--replace] [--dry-run]

Preview types match the display slots — NOTE: unlike screenshot display types, preview
types have NO "APP_" prefix:
  IOS 6.5"/6.9"  886x1920 -> IPHONE_65 / IPHONE_67
  iPad 13"      1200x1600 -> IPAD_PRO_129          macOS 1920x1080 -> DESKTOP
"""
import argparse, os, sys
import asc_client as asc

EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_REVIEW"}
CHUNK = 5 * 1024 * 1024   # reservation may split into parts; we honor uploadOperations anyway


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


def preview_set(loc_id, display, create=True):
    r = asc.get(f"/v1/appStoreVersionLocalizations/{loc_id}/appPreviewSets?limit=50")
    for s in r.get("data", []):
        if s["attributes"]["previewType"] == display:
            return s["id"]
    if not create:
        return None
    body = {"data": {"type": "appPreviewSets",
                     "attributes": {"previewType": display},
                     "relationships": {"appStoreVersionLocalization":
                        {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}}
    return asc.post("/v1/appPreviewSets", body)["data"]["id"]


def clear_set(set_id):
    r = asc.get(f"/v1/appPreviewSets/{set_id}/appPreviews?limit=50")
    for p in r.get("data", []):
        asc.delete(f"/v1/appPreviews/{p['id']}")
        print(f"    - deleted existing {p['id']}")


def upload_one(set_id, path, frame=None):
    data = open(path, "rb").read()
    attrs = {"fileName": os.path.basename(path), "fileSize": len(data), "mimeType": "video/mp4"}
    if frame:
        attrs["previewFrameTimeCode"] = frame
    reserve = {"data": {"type": "appPreviews", "attributes": attrs,
                        "relationships": {"appPreviewSet":
                            {"data": {"type": "appPreviewSets", "id": set_id}}}}}
    res = asc.post("/v1/appPreviews", reserve)
    pid = res["data"]["id"]
    asc.upload_asset(res["data"]["attributes"]["uploadOperations"], data)
    asc.patch(f"/v1/appPreviews/{pid}",
              {"data": {"type": "appPreviews", "id": pid,
                        "attributes": {"uploaded": True, "sourceFileChecksum": asc.md5_hex(data)}}})
    return pid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app-id", required=True)
    ap.add_argument("--platform", required=True, choices=["IOS", "MAC_OS", "TV_OS"])
    ap.add_argument("--display", required=True)
    ap.add_argument("--locale", default="en-US")
    ap.add_argument("--file", required=True)
    ap.add_argument("--frame", default=None, help="poster-frame timecode, e.g. 00:00:04")
    ap.add_argument("--replace", action="store_true")
    ap.add_argument("--version-id", help="skip the /v1/apps lookup and use this "
                    "appStoreVersion id directly (Apple's /v1/apps resource "
                    "sometimes 500s while sub-resources still work)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if not os.path.isfile(a.file):
        sys.exit(f"no file: {a.file}")

    # A given --version-id skips the /v1/apps lookup, which can 500 while sub-resources work.
    ver = ({"id": a.version_id,
            "attributes": {"versionString": "?", "appStoreState": "(given)"}}
           if a.version_id else editable_version(a.app_id, a.platform))
    if not ver:
        sys.exit(f"no editable {a.platform} version (need PREPARE_FOR_SUBMISSION).")
    vid, vstr, vstate = ver["id"], ver["attributes"]["versionString"], ver["attributes"]["appStoreState"]
    print(f"{a.platform} version {vstr} ({vstate}) id={vid}")

    loc = localization(vid, a.locale)
    if not loc:
        sys.exit(f"no localization {a.locale} on version {vstr}")

    print(f"preview {os.path.basename(a.file)} ({os.path.getsize(a.file)//1024} KB) "
          f"-> {a.display} / {a.locale}")
    if a.dry_run:
        return

    set_id = preview_set(loc, a.display)
    if a.replace:
        clear_set(set_id)
    pid = upload_one(set_id, a.file, a.frame)
    print(f"    ✓ uploaded -> {pid}  (Apple will process it asynchronously)")


if __name__ == "__main__":
    main()
