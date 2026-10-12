#!/bin/bash
# Baut "RetroReminder.app" in ./build (signiert mit Zertifikat, sonst ad-hoc)
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -E "error|warning: unre|Compiling|Build" | grep -v "^\[" | head -50
APP="build/RetroReminder.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/RetroReminder "$APP/Contents/MacOS/"
cp Resources/AppIcon.icns Resources/leather.png Resources/paper.png Resources/pit.png "$APP/Contents/Resources/" 2>/dev/null || true
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>RetroReminder</string>
<key>CFBundleDisplayName</key><string>RetroReminder</string>
<key>CFBundleIdentifier</key><string>de.maik.RetroReminder</string>
<key>CFBundleExecutable</key><string>RetroReminder</string>
<key>NSHumanReadableCopyright</key><string>© 2026 Maik Klotz. MIT License. Not affiliated with Apple Inc.</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>de</string></array>
<key>NSRemindersFullAccessUsageDescription</key><string>Shows and edits your reminders from the macOS Reminders app.</string>
<key>NSRemindersUsageDescription</key><string>Shows and edits your reminders from the macOS Reminders app.</string>
<key>NSLocationUsageDescription</key><string>For location-based reminders.</string>
<key>NSLocationAlwaysUsageDescription</key><string>For location-based reminders.</string>
</dict></plist>
P
# Stabile Signatur: macOS bindet Datenschutz-Freigaben (Erinnerungen, Ort) an die Code-Anforderung der App.
# Ad-hoc ("-") ändert sich bei jedem Build (cdhash) → Freigabe-Dialog kommt jedes Mal neu. Mit Zertifikat bleibt sie erhalten.
ID="${SIGN_ID:-$(security find-identity -v -p codesigning | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"')}"
if [ -n "$ID" ]; then mkdir -p "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/de.lproj"
cat > "$APP/Contents/Resources/en.lproj/InfoPlist.strings" <<P
NSRemindersFullAccessUsageDescription = "Shows and edits your reminders from the macOS Reminders app.";
NSRemindersUsageDescription = "Shows and edits your reminders from the macOS Reminders app.";
NSLocationUsageDescription = "For location-based reminders.";
NSLocationAlwaysUsageDescription = "For location-based reminders.";
P
cat > "$APP/Contents/Resources/de.lproj/InfoPlist.strings" <<P
NSRemindersFullAccessUsageDescription = "Zeigt und bearbeitet deine Erinnerungen aus der macOS-App „Erinnerungen“.";
NSRemindersUsageDescription = "Zeigt und bearbeitet deine Erinnerungen aus der macOS-App „Erinnerungen“.";
NSLocationUsageDescription = "Für ortsbezogene Erinnerungen.";
NSLocationAlwaysUsageDescription = "Für ortsbezogene Erinnerungen.";
P
codesign --force $CODESIGN_FLAGS --sign "$ID" "$APP" && echo "signiert: $ID" || { echo "Signatur mit '$ID' fehlgeschlagen, ad-hoc"; codesign --force --sign - "$APP"; }
else codesign --force --sign - "$APP" >/dev/null 2>&1; echo "ad-hoc signiert (Freigaben müssen nach jedem Build neu erteilt werden)"; fi
echo "OK: $APP"
