#!/usr/bin/env bash
set -euo pipefail

echo "== Xcode =="
xcodebuild -version
echo

echo "== Code Signing Identities =="
security find-identity -v -p codesigning || true
echo

echo "== Xcode Apple Accounts =="
defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists 2>/dev/null || true
echo

echo "== Provisioning Profiles =="
ls -1 ~/Library/MobileDevice/Provisioning\ Profiles 2>/dev/null || true
echo

echo "== Destinations =="
xcodebuild -project "$(dirname "$0")/../PortfolioWorkbenchIOS.xcodeproj" -scheme PortfolioWorkbenchIOS -showdestinations 2>/dev/null || true
echo

echo "== Connected Devices (devicectl) =="
xcrun devicectl list devices 2>/dev/null || true
echo

echo "== Connected Devices (xctrace) =="
xcrun xctrace list devices 2>/dev/null || true
