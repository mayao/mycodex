#!/bin/bash
set -e

METHOD=${1:-testflight}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEAM_ID=${DEVELOPMENT_TEAM:-J32AD5KDR3}
ARCHIVE_PATH=${ARCHIVE_PATH:-build/VC.xcarchive}
EXPORT_PATH=${EXPORT_PATH:-build/ipa}
EXPORT_OPTIONS_PLIST=${EXPORT_OPTIONS_PLIST:-"ExportOptions-${METHOD}.plist"}
cd "$SCRIPT_DIR"

echo "=== Archiving VitalCommandIOS (method: $METHOD, team: $TEAM_ID) ==="
xcodebuild archive \
  -project VitalCommandIOS.xcodeproj \
  -scheme VitalCommandIOS \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID"

echo "=== Exporting IPA ==="
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -allowProvisioningUpdates

echo ""
echo "✅ Export completed: $EXPORT_PATH/"

if [ "$METHOD" = "testflight" ]; then
  echo ""
  echo "TestFlight upload is handled by xcodebuild during export."
fi
