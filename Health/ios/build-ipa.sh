#!/bin/bash
set -e

METHOD=${1:-testflight}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Archiving VitalCommandIOS (method: $METHOD) ==="
xcodebuild archive \
  -project VitalCommandIOS.xcodeproj \
  -scheme VitalCommandIOS \
  -archivePath build/VC.xcarchive \
  -destination "generic/platform=iOS" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=BBT2D26L2V

echo "=== Exporting IPA ==="
xcodebuild -exportArchive \
  -archivePath build/VC.xcarchive \
  -exportPath build/ipa \
  -exportOptionsPlist "ExportOptions-${METHOD}.plist"

echo ""
echo "✅ IPA exported to: build/ipa/"

if [ "$METHOD" = "testflight" ]; then
  echo ""
  echo "Upload to TestFlight:"
  echo "  xcrun altool --upload-app -f build/ipa/VitalCommandIOS.ipa \\"
  echo "    -t ios -u YOUR_APPLE_ID -p YOUR_APP_SPECIFIC_PASSWORD"
fi
