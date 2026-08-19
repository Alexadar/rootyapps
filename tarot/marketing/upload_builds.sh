#!/usr/bin/env bash
#
# upload_builds.sh [ios|mac|both] — archive, export and upload Tarot to App Store Connect.
#
# This is the STAGING half of a release. It uploads builds and (separately, once Apple finishes
# processing) they can be attached to the draft version. It does not create a version, does not
# change price, and does not submit — those stay human decisions.
#
# Signing: automatic, with the ASC API key passed to xcodebuild. That is what mints the Apple
# Distribution certificate and the App Store provisioning profile, neither of which exists on this
# machine by default (it has Apple Development and Developer ID only).
#
# `-allowProvisioningUpdates` is REQUIRED here and is safe for this app specifically: the bundle
# ID oleksandr.aisixteen.tarot already exists in the portal (record 486GDXR7WL), so the flag
# reuses it rather than creating anything. The standing rule against it applies to device installs,
# which ride the wildcard profile and genuinely need no portal write.
set -uo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/tarot"
SCHEME=tarot
PROJECT="$APP_DIR/tarot.xcodeproj"
BUILD="$APP_DIR/.build/release"
KEY_ID=55B6L3J65N
ISSUER=057ddafb-cb0e-4410-9e0a-00e24f6e1688
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
WHICH="${1:-both}"

[ -f "$KEY_PATH" ] || { echo "❌ no ASC key at $KEY_PATH" >&2; exit 1; }
mkdir -p "$BUILD"

# `destination: upload` makes xcodebuild do the export AND the upload in one step, so there is no
# separate altool invocation and no .ipa/.pkg sitting around half-signed.
EXPORT_PLIST="$BUILD/ExportOptions.plist"
cat > "$EXPORT_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>LSKNNBG94G</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

( cd "$APP_DIR" && xcodegen generate >/dev/null ) || { echo "❌ xcodegen failed" >&2; exit 1; }

ship() {
  local PLAT="$1" DEST="$2"
  local ARCHIVE="$BUILD/$PLAT.xcarchive"
  echo "▶ archiving $PLAT"
  rm -rf "$ARCHIVE"
  xcodebuild archive \
    -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination "$DEST" -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$KEY_ID" \
    -authenticationKeyIssuerID "$ISSUER" \
    > "$BUILD/archive-$PLAT.log" 2>&1
  if [ ! -d "$ARCHIVE" ]; then
    echo "❌ $PLAT archive failed — tail of $BUILD/archive-$PLAT.log:" >&2
    grep -E "error:|Error|failed" "$BUILD/archive-$PLAT.log" | tail -12 >&2
    return 1
  fi

  # A Release build must not carry the filming harness: the scenario YAML holds pre-captured
  # model prose, and shipping it would put words in the binary the app did not generate.
  local APPBIN
  APPBIN=$(find "$ARCHIVE/Products" -maxdepth 4 -name "Tarot.app" | head -1)
  if [ -n "$APPBIN" ] && find "$APPBIN" -name "*.scenario.yaml" | grep -q .; then
    echo "❌ $PLAT archive contains a .scenario.yaml — Release must exclude it" >&2
    return 1
  fi

  echo "▶ exporting and uploading $PLAT"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" -exportPath "$BUILD/export-$PLAT" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$KEY_ID" \
    -authenticationKeyIssuerID "$ISSUER" \
    > "$BUILD/export-$PLAT.log" 2>&1
  if grep -qE "EXPORT SUCCEEDED|Upload succeeded" "$BUILD/export-$PLAT.log"; then
    echo "✅ $PLAT uploaded"
  else
    echo "❌ $PLAT export/upload failed — tail of $BUILD/export-$PLAT.log:" >&2
    grep -E "error:|Error|failed|Provisioning" "$BUILD/export-$PLAT.log" | tail -12 >&2
    return 1
  fi
}

RC=0
case "$WHICH" in
  ios)  ship ios "generic/platform=iOS"   || RC=1 ;;
  mac)  ship mac "generic/platform=macOS" || RC=1 ;;
  both) ship ios "generic/platform=iOS"   || RC=1
        ship mac "generic/platform=macOS" || RC=1 ;;
  *) echo "usage: $0 [ios|mac|both]" >&2; exit 2 ;;
esac

echo
echo "Apple now processes the build(s); that takes minutes and is not instant."
echo "Attach with:  marketing/attach_build.py"
exit $RC
