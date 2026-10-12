#!/bin/bash
# Release: Developer-ID-Signatur (Hardened Runtime) → Notarisierung → DMG → DMG signieren/notarisieren/heften.
# Voraussetzung: Zertifikat "Developer ID Application" im Schlüsselbund, notarytool-Profil (Standard: Retromac).
set -e
cd "$(dirname "$0")"
VERSION=$(grep -A1 CFBundleShortVersionString build.sh | grep -o '<string>[^<]*' | head -1 | sed 's/<string>//')
PROFILE="${NOTARY_PROFILE:-Retromac}"
ID="${SIGN_ID:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"')}"
[ -n "$ID" ] || { echo "Kein Developer-ID-Zertifikat gefunden"; exit 1; }
echo "== Signatur: $ID, Version $VERSION"
SIGN_ID="$ID" CODESIGN_FLAGS="--options runtime --timestamp --entitlements Resources/RetroReminder.entitlements" ./build.sh | tail -2
APP="build/RetroReminder.app"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "== Notarisierung der App"
rm -f /tmp/mlr-app.zip; ditto -c -k --keepParent "$APP" /tmp/mlr-app.zip
xcrun notarytool submit /tmp/mlr-app.zip --keychain-profile "$PROFILE" --wait | tee /tmp/mlr-notary-app.log
grep -q "status: Accepted" /tmp/mlr-notary-app.log || { echo "App-Notarisierung fehlgeschlagen"; exit 1; }
xcrun stapler staple "$APP"
echo "== DMG"
DMG="build/RetroReminder-$VERSION.dmg"; STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"; hdiutil create -volname "RetroReminder" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null; rm -rf "$STAGE"
codesign --force --timestamp --sign "$ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait | tee /tmp/mlr-notary-dmg.log
grep -q "status: Accepted" /tmp/mlr-notary-dmg.log || { echo "DMG-Notarisierung fehlgeschlagen"; exit 1; }
xcrun stapler staple "$DMG"
echo "== Prüfung"
spctl -a -vv -t exec "$APP" 2>&1 | head -3
spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 | head -3
xcrun stapler validate "$DMG"
shasum -a 256 "$DMG"
echo "FERTIG: $DMG"
