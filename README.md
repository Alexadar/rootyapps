# rootyapps

Monorepo of small, paid-once, offline-first apps. One folder per app (`<app>.swift`), a shared
`marketing/` toolchain, and per-app engines as SPM packages.

---

## Adding a watch app: the App Group

Every watch app here needs an App Group, because the watch app and its complication extension are
separate processes that must share state. This is the part that is not obvious, costs an hour to
rediscover, and has now been rediscovered three times (`eartharound`, `marinenav`, `ephemeris`).

### The short version

**Bundle IDs and the `APP_GROUPS` capability can be created through the App Store Connect API.
The group identifier itself cannot — Xcode creates it, and only when it falls back to your
signed-in Apple ID.**

### Why the API can't do it

There is no public endpoint. Verified, not assumed:

```
GET /v1/appGroups          -> 404
GET /v1/applicationGroups  -> 404
GET /v1/bundleIds?filter[identifier]=group.…   -> 0 results (groups aren't bundle IDs)
```

The `APP_GROUPS` capability on a bundle ID has `settings: null` — it is only a flag saying "this
ID may join groups". It does not say *which* group, and it does not create one.

### The sequence that works

**1 — Register the bundle IDs (API is fine).** Follow the existing naming, which is what Xcode
expects for a watch app embedded in an iOS app:

```
com.example.myapp                          # iOS app
com.example.myapp.watchkitapp              # watch app
com.example.myapp.watchkitapp.widgets      # complications
```

```python
asc.post("/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
    "identifier": "com.example.myapp.watchkitapp",
    "name": "MyApp Watch", "platform": "IOS"}}})     # platform IOS even for a watch app
```

**2 — Enable `APP_GROUPS` on every one of them (API is fine).** Each ID needs it separately:

```python
asc.post("/v1/bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities",
    "attributes": {"capabilityType": "APP_GROUPS"},
    "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_id}}}}})
```

**3 — Declare the group in an entitlements file** committed next to the project:

```xml
<!-- AppGroup.entitlements -->
<key>com.apple.security.application-groups</key>
<array><string>group.com.example.myapp</string></array>
```

and point every target at it (`CODE_SIGN_ENTITLEMENTS: AppGroup.entitlements`).

**4 — Let Xcode create the group. Build WITHOUT `-authenticationKey*`:**

```bash
xcodebuild -project MyApp.xcodeproj -scheme MyAppWatch \
  -destination 'generic/platform=watchOS' build -allowProvisioningUpdates
```

Xcode sees the entitlement, sees the capability is enabled, registers
`group.com.example.myapp`, and generates the profiles carrying it.

### The trap

**Passing an ASC API key to `xcodebuild` breaks exactly this.** These flags:

```
-authenticationKeyPath …/AuthKey_XXXX.p8 -authenticationKeyID … -authenticationKeyIssuerID …
```

make Xcode authenticate as the API key, which has **no Certificates / Identifiers / Profiles
access**. You get:

```
error: Authentication failed: Make sure a bearer token was provided…
error: Provisioning profile doesn't support the group.com.example.myapp App Group.
```

The second error is misleading — it reads as though the group is missing or malformed, when the
real problem is that Xcode was never permitted to create it. **Drop the auth flags** and Xcode
falls back to your signed-in Apple ID, which does have that access.

### Verifying it worked

```bash
for f in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision; do
  security cms -D -i "$f" 2>/dev/null | grep -q "group.com.example.myapp" && basename "$f"
done
```

You should see both Development (`get-task-allow = true`, for device installs) and Store
(`false`, for archives) profiles.

---

## Other watch-app gotchas

**`WKWatchOnly` vs companion — pick one, never both.** A watch app shipping inside the iOS app
record (one listing, one price — what every app here does) uses:

```yaml
INFOPLIST_KEY_WKCompanionAppBundleIdentifier: com.example.myapp
INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp: YES
```

`WKWatchOnly: YES` is for a watch app with **no** iOS counterpart at all. Setting it alongside the
other two fails the install with *"Having both defined is ambiguous"*; setting neither fails with
*"must specify WKCompanionAppBundleIdentifier"*.

**xcodegen's `info:` key generates a plist — it does not use yours.** It overwrites your
hand-written file on disk. For an extension needing a specific `NSExtensionPointIdentifier`, use
`INFOPLIST_FILE` and set `GENERATE_INFOPLIST_FILE: NO`.

**An extension's version must match its host.** A widget at `1.0`/`1` inside an app at `1.0.5`/`5`
fails to install with the opaque *"Invalid placeholder attributes"*. Use `$(MARKETING_VERSION)`
and `$(CURRENT_PROJECT_VERSION)` in the extension's plist.

**App groups do not cross the pairing.** The group is shared between an app and its extensions on
**one device**. The phone cannot hand the watch anything through it — that needs
`WatchConnectivity` (`updateApplicationContext` for state, since it keeps only the latest value
and delivers whenever the counterpart next wakes). Getting this wrong is quiet: the watch reads
its own empty container and behaves as if nothing was ever configured.

**Complication `kind` strings are cached.** WidgetKit caches timelines *and rendered snapshots*
per `kind`, so an installed complication keeps serving the old view across rebuilds and
reinstalls. Changing the identifier (`eph.moon.v1` → `eph.moon.v2`) is the reliable invalidation.
Existing complications then go blank and must be re-added to the face.

**Restarting a watch is scriptable:** `xcrun devicectl device reboot --device <UDID>`. Installs
usually need retrying afterwards — the device reports `available` before its tunnel is really
back, and the first attempt fails with a tunnel timeout.

---

## Debugging note: where the code actually is

Debug builds use Xcode's dylib split. The app binary (`MyApp.app/MyApp`) is a ~200 KB loader stub
and the real code is in `MyApp.debug.dylib` alongside it. `nm`/`strings` on the main binary find
**nothing** and look alarming; search the `.debug.dylib` instead.
