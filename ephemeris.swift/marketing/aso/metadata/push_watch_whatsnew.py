#!/usr/bin/env python3
"""
push_watch_whatsnew.py — prepend the Apple Watch section to each locale's release notes.

Prepends rather than replaces because the 1.0.5 notes already say the useful things (houses and
axes, and per-locale, that the app now speaks that language). The watch app is the headline of
build 6, so it goes on top and the rest survives underneath.

Idempotent: a locale whose notes already open with the watch section is skipped, so re-running
after a partial failure cannot stack the paragraph twice.

Credentials come from the environment (see asc_client.py): ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
"""
import json, os, sys

sys.path.insert(0, "/Users/oleksandr/Projects/rootyapps/marketing/logic")
import asc_client as asc

APP_ID = "6782659268"
LIMIT = 4000          # App Store Connect's whatsNew maximum
HERE = os.path.dirname(os.path.abspath(__file__))
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY"}


def main():
    dry = "--dry-run" in sys.argv
    watch = json.load(open(os.path.join(HERE, "meta_watch_whatsnew.json")))
    watch.pop("_note", None)

    versions = asc.get(f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&limit=50")
    version = next((v for v in versions["data"]
                    if v["attributes"]["appStoreState"] in EDITABLE), None)
    if not version:
        sys.exit("no editable IOS version")
    print(f"IOS {version['attributes']['versionString']} "
          f"({version['attributes']['appStoreState']}) id={version['id']}")

    locs = asc.get(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations?limit=50")
    for loc in locs["data"]:
        code, existing = loc["attributes"]["locale"], loc["attributes"].get("whatsNew") or ""
        section = watch.get(code)
        if not section:
            print(f"    {code}: no watch text — SKIPPED")
            continue
        # The first line is the locale's own "NEW: … APPLE WATCH …" headline; matching on it
        # rather than the whole block keeps this idempotent even if the tail was edited by hand.
        if existing.startswith(section.split("\n")[0]):
            print(f"    {code}: already present")
            continue
        merged = section + existing
        if len(merged) > LIMIT:
            print(f"    {code}: {len(merged)} chars > {LIMIT} — SKIPPED, needs trimming")
            continue
        if dry:
            print(f"    {code}: would write {len(merged)} chars")
            continue
        asc.patch(f"/v1/appStoreVersionLocalizations/{loc['id']}",
                  {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
                            "attributes": {"whatsNew": merged}}})
        print(f"    ✓ {code}  ({len(merged)} chars)")
    print("done.")


if __name__ == "__main__":
    main()
