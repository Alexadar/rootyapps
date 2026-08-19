#!/usr/bin/env python3
"""push_review_notes.py — set the App Review notes on both draft versions.

This is the 4.3(b) defence, and it is the one that matters. Apple names "fortune telling" in the
guideline as a category it will not accept new submissions into "unless they offer a meaningfully
different or improved experience". That call is judgement-driven, made quickly, and appeals
succeed mainly by pointing at a specific feature the reviewer did not see. So the differentiators
are put in front of the reviewer BEFORE the rejection, with instructions for reproducing them.

It also pre-empts the likeliest false rejection: a reviewer on hardware without Apple Intelligence
sees a deck that never writes and reads it as broken.

Staging only — writes notes on a PREPARE_FOR_SUBMISSION version. It does not submit.
"""
import sys, time, pathlib
import jwt, requests

KEY_ID = "55B6L3J65N"
ISSUER = "057ddafb-cb0e-4410-9e0a-00e24f6e1688"
KEY_PATH = pathlib.Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{KEY_ID}.p8"
BASE = "https://api.appstoreconnect.apple.com/v1"
APP = "6802612778"

NOTES = """WHAT THIS APP IS
A tarot deck you handle. 78 cards sit in a weighted stack on a 3D table; you drag each one into
its position yourself and the cards have mass, collide and settle. When the spread is complete,
Apple Intelligence writes a short reflection on it, on device, a word at a time.

WHY IT IS MEANINGFULLY DIFFERENT (Guideline 4.3(b))
1. The reading text is GENERATED ON DEVICE by the Foundation Models framework. There is no
   bundled table of card meanings anywhere in the binary and no server call — the app contains no
   networking code at all. Put the device in airplane mode and it behaves identically. This is
   also why no two readings are alike, even for the same three cards.
2. The deck is a physics simulation, not a picture carousel: a batch-vectorised motion kernel
   drives shuffling, dragging, flight and landing, with per-card foil that reacts to device tilt.
   Cards are dragged into place, never tapped to flip.
3. Four methods (Daily Card, Three Cards, Crossroads, Celtic Cross) x three decks, each the full
   78 cards, upright or reversed.
4. No subscription, no account, no ads, no analytics, no tracking, no network.

REGISTER — THE APP DOES NOT PREDICT
The app does not tell fortunes and makes no claim of foresight or accuracy. The model is
instructed to write in the present tense about what a card's traditional imagery might invite the
reader to consider, and the reading panel itself ends with the line "An interpretation of the
cards you drew - not a prediction." The store description says the same thing in the same words.

HOW TO TEST
Apple Intelligence is required for the reading. The app is deliberately NOT gated by device
capability - it installs anywhere and explains itself on hardware that cannot write, which is the
fallback behaviour Apple's own guidance asks for. Please review on a device with Apple
Intelligence ENABLED in Settings, or the reading will not be generated.

If Apple Intelligence is off, unavailable in your region, or still downloading its model, the
app is NOT broken: the table, deck, shuffle and all four methods still work, and the app shows a
specific message naming which of those three is stopping it. That state is deliberate, not a
failure to load.

No demo account is needed - there is no sign-in of any kind.
"""


def contact():
    """The review contact block, read from an already-shipped app on this account.

    Not hardcoded: if the owner updates their number on one app, the next run of this script
    picks the new one up rather than silently re-writing a stale one.
    """
    H = headers()
    apps = requests.get(f"{BASE}/apps", headers=H, params={"limit": 50}).json()["data"]
    for a in apps:
        if a["id"] == APP:
            continue
        for v in requests.get(f"{BASE}/apps/{a['id']}/appStoreVersions",
                              headers=H, params={"limit": 5}).json().get("data", []):
            d = requests.get(f"{BASE}/appStoreVersions/{v['id']}/appStoreReviewDetail",
                             headers=H).json().get("data")
            at = (d or {}).get("attributes", {})
            if at.get("contactPhone"):
                return {k: at[k] for k in ("contactFirstName", "contactLastName",
                                           "contactPhone", "contactEmail") if at.get(k)}
    raise SystemExit("no shipped app on this account has a review contact — fill it in ASC once")


def headers():
    tok = jwt.encode({"iss": ISSUER, "exp": int(time.time()) + 900, "aud": "appstoreconnect-v1"},
                     KEY_PATH.read_text(), algorithm="ES256",
                     headers={"kid": KEY_ID, "typ": "JWT"})
    return {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"}


def main():
    H = headers()
    rc = 0
    for v in requests.get(f"{BASE}/apps/{APP}/appStoreVersions",
                          headers=H, params={"limit": 10}).json()["data"]:
        plat = v["attributes"]["platform"]
        r = requests.get(f"{BASE}/appStoreVersions/{v['id']}/appStoreReviewDetail", headers=H)
        detail = r.json().get("data") if r.status_code == 200 else None
        body = {"type": "appStoreReviewDetails",
                "attributes": {"notes": NOTES, "demoAccountRequired": False}}
        # PATCHing an existing detail demands the full contact block, and DELETE is not permitted
        # on this resource (a re-POST then fails with "Resource already exists"). So the contact
        # block is carried along with the notes — copied from an app on this same account that has
        # already shipped, rather than invented. App Review actually dials that number, so a
        # plausible-looking placeholder would be worse than leaving the field empty.
        body["attributes"].update(contact())
        if detail:
            body["id"] = detail["id"]
            resp = requests.patch(f"{BASE}/appStoreReviewDetails/{detail['id']}",
                                  headers=H, json={"data": body})
        else:
            body["relationships"] = {"appStoreVersion": {
                "data": {"type": "appStoreVersions", "id": v["id"]}}}
            resp = requests.post(f"{BASE}/appStoreReviewDetails", headers=H, json={"data": body})
        ok = resp.status_code in (200, 201)
        print(f"{plat}: review notes {'✓' if ok else '✗ ' + resp.text[:300]}")
        if not ok:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
