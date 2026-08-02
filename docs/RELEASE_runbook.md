# Release runbook — archive, upload and submit an app in this monorepo

> Split out of the UI-test prompt on 2026-07-30: this is App Store plumbing, not testing. The
> UI-test prompt (`docs/PROMPT_uitests_rollout.md`) links here for its final step.
>
> Everything below is measured on a real submission (Storypole 1.0.0, iOS + macOS, 2026-07-29).

Replace `<app>` / `<App>` / `<scheme>` with the app's names.

## 1. Ship a build

### 1.1 Establish the real state — never assume

```bash
cd marketing/logic
# creds come from the environment (see asc_client.py). The values are in ~/.claude.json under the
# app-store-connect MCP server config: APP_STORE_CONNECT_KEY_ID / _ISSUER_ID / _P8_PATH.
export ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=...
```

```python
import asc_client as a
app = "<app store id>"                              # a.get("/v1/apps?limit=200") to find it
for v in a.get(f"/v1/apps/{app}/appStoreVersions?limit=10")["data"]:
    print(v["attributes"]["platform"], v["attributes"]["versionString"], v["attributes"]["appStoreState"])
```

Apple's API returns intermittent **500s** on these endpoints — the same GET can succeed, then fail
seconds later. Retry with backoff before concluding anything is broken, but see F.4 for what a failed
*upload* leaves behind.

### 1.2 Act on the state

| State | Action |
|---|---|
| `PREPARE_FOR_SUBMISSION`, never submitted | Bump the **patch of `MARKETING_VERSION`** (not the build number), archive, upload, attach, submit. |
| `WAITING_FOR_REVIEW` | The fix can still get in, but the queued submission must be cancelled first. **Ask me before cancelling.** |
| `IN_REVIEW` | Needs a developer reject and loses the queue position. **Ask me first** — shipping the fix as the next version is often better. |
| `READY_FOR_DISTRIBUTION` / live | New version: bump, archive, upload, attach, submit, and write `whatsNew`. |

### 1.3 Archive, upload, attach

```bash
xcodebuild -project <app>.xcodeproj -scheme <scheme> -destination 'generic/platform=iOS' \
  -configuration Release -archivePath build/archives/<App>-iOS.xcarchive archive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/archives/<App>-iOS.xcarchive \
  -exportOptionsPlist build/ExportOptions-iOS.plist -exportPath build/export-ios -allowProvisioningUpdates
xcrun altool --upload-app -f build/export-ios/<App>.ipa -t ios --apiKey <KEYID> --apiIssuer <ISSUER>
```

`ExportOptions` = `method: app-store-connect`, `teamID: LSKNNBG94G`, `signingStyle: automatic`,
`uploadSymbols: true`. macOS is the same with `-destination 'platform=macOS'` and `-t macos`; it
produces a `.pkg`.

**Archive and export WITHOUT `-authenticationKey*` flags.** Those make Xcode authenticate as the API
key, which has no Certificates/Identifiers/Profiles access, and provisioning then fails with the
misleading *"Provisioning profile doesn't support the … App Group"*. Xcode must fall back to my
signed-in Apple ID. Use the API key only for `altool`.

The build's `CFBundleShortVersionString` **must equal** the App Store version string, or it cannot be
attached. Then attach it:
`PATCH /v1/appStoreVersions/{id}/relationships/build` with the VALID build for that platform.

### 1.4 Things that will waste your time if you don't know them

- **App Privacy / data usages has NO API.** The app resource exposes no such relationship; every
  candidate endpoint 404s. It is web-UI only, the answers must be **Published** (not merely saved), and
  submission fails with `STATE_ERROR.APP_DATA_USAGES_REQUIRED` until they are. Ask me to do it.
- **App Group identifiers:** Xcode creates them, and only when not authenticating as the API key. The
  group is also what forces Xcode to register **explicit** bundle IDs — with no capability it signs
  everything with the team wildcard and registers nothing. Scope the group to iOS/watchOS only: adding
  it to the macOS entitlements demands a Mac provisioning profile and breaks every
  `-destination platform=macOS` build, including the test runs.
- **`APP_IPAD_PRO_129` and `APP_IPAD_PRO_3GEN_129` are different slots at identical pixel sizes**
  (2048×2732). Apple requires the 3GEN one.
- **An app with a watch app MUST have `APP_WATCH_SERIES_4` screenshots at 368×448.** A Series 10
  capture (416×496) does not satisfy it. Capture on an `Apple-Watch-Series-6-44mm` sim.
- **After any upload that errored mid-flight, re-list the set.** A failed upload leaves debris and a
  retry *adds* rather than replaces: one set ended up with 9 screenshots — 3 duplicates plus an asset
  stuck in `AWAITING_UPLOAD`, which by itself blocked submission. Delete orphans and duplicates,
  keeping one COMPLETE instance per filename.
- Screenshot display types take an `APP_` prefix; **preview types do not** (`IPHONE_65`, `DESKTOP`).
- Upload media with `marketing/logic/upload_screenshots.py` / `upload_previews.py`. Never upload a
  video-only preview — App Store Connect requires an AAC track.
- A framed reel is a **2.3.4 rejection** as an app preview. Store previews are full-bleed
  (`store_preview.py`); framed output is for the site and socials only.

### 1.5 Submit

```python
rs = a.post("/v1/reviewSubmissions", {"data": {"type":"reviewSubmissions",
      "attributes": {"platform": plat},
      "relationships": {"app": {"data": {"type":"apps","id": app}}}}})["data"]["id"]
a.post("/v1/reviewSubmissionItems", {"data": {"type":"reviewSubmissionItems",
      "relationships": {"reviewSubmission": {"data":{"type":"reviewSubmissions","id":rs}},
                        "appStoreVersion":  {"data":{"type":"appStoreVersions","id":vid}}}}})
a.patch(f"/v1/reviewSubmissions/{rs}", {"data": {"type":"reviewSubmissions","id":rs,
      "attributes": {"submitted": True}}})
```

Adding the item is what surfaces the blockers: a 409 carries `meta.associatedErrors` naming every
missing screenshot slot, missing privacy answer and stuck asset. **Print that whole structure** —
truncating it hides the actual cause. One submission per platform.

Also required before review, and easy to miss: primary category, age-rating declaration
(`/v1/appInfos/{id}/ageRatingDeclaration` — **not** on the version, which 404s; and sending both
`ageRatingOverride` and `ageRatingOverrideV2` is a hard 409), copyright, content-rights declaration,
App Review contact details, and a support URL that actually resolves. Copy the values from a shipped
sibling app rather than inventing them.

---


## 2. Non-testing traps that bite at release time

- **`PRODUCT_NAME` must be set on every target**, or the macOS menu bar ships the target name and App
  Review rejects under guideline 5.2.5. This repo has been caught three times.
- **Widgets/complications:** a complication that looks right in the Simulator but renders grey on
  device needs `.containerBackground(.clear, for: .widget)`.
- **An extension's version must match its host** (`$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`
  in its plist), or the install fails with the opaque *"Invalid placeholder attributes"*.
- `UDID=$(… | grep …)` under `set -euo pipefail` aborts a capture script when the sim does not exist
  yet — exactly the first-run path. Append `|| true`.

## 3. Standing rules

Never create an App Store record, change price, or assign a build to an external TestFlight group
without asking. Draft and stage freely; the submit itself needs an explicit go-ahead unless the task
that sent you here already granted one.
