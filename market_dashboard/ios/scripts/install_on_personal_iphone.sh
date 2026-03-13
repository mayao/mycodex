#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$IOS_DIR/PortfolioWorkbenchIOS.xcodeproj"
SCHEME="PortfolioWorkbenchIOS"
DEFAULT_APP_BUNDLE_ID="com.xmly.portfolioworkbenchios"
PORT="${PORT:-8008}"
SKIP_XCODEGEN="${SKIP_XCODEGEN:-auto}"
DEFAULT_TEAM_ID="$(
  sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM: //p' "$IOS_DIR/project.yml" 2>/dev/null \
    | head -n 1
)"

TEAM_ID="${TEAM_ID:-${1:-$DEFAULT_TEAM_ID}}"
DEVICE_DESTINATION_ID="${DEVICE_DESTINATION_ID:-${2:-}}"
DEVICE_CORE_ID="${DEVICE_CORE_ID:-${3:-}}"
BUNDLE_ID="${BUNDLE_ID:-}"
CONFIGURATION="${CONFIGURATION:-Debug}"
SERVER_URL="${SERVER_URL:-}"

detect_lan_ip() {
  if [[ -n "${LAN_IP:-}" ]]; then
    printf '%s\n' "$LAN_IP"
    return 0
  fi

  local iface=""
  local candidate=""

  iface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
  if [[ "$iface" == utun* ]]; then
    iface=""
  fi
  for candidate in "$iface" en0 en1 en2; do
    [[ -n "$candidate" ]] || continue
    if ipconfig getifaddr "$candidate" >/dev/null 2>&1; then
      ipconfig getifaddr "$candidate"
      return 0
    fi
  done

  ifconfig | awk '/inet / && $2 != "127.0.0.1" && $2 !~ /^169\.254\./ {print $2; exit}'
}

should_generate_project() {
  case "$SKIP_XCODEGEN" in
    1|true|TRUE|yes|YES)
      return 1
      ;;
    0|false|FALSE|no|NO)
      return 0
      ;;
  esac

  [[ ! -d "$PROJECT_PATH" ]]
}

has_xcode_account() {
  local accounts_dump=""
  accounts_dump="$(defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists 2>/dev/null || true)"
  [[ "$accounts_dump" == *"identifier ="* ]]
}

if [[ -z "$TEAM_ID" ]]; then
  echo "Missing TEAM_ID."
  echo "Usage: TEAM_ID=<your_team_id> $0 [TEAM_ID] [DEVICE_DESTINATION_ID] [DEVICE_CORE_ID]"
  exit 1
fi

if [[ -z "$BUNDLE_ID" ]]; then
  TEAM_ID_LOWER="$(printf '%s' "$TEAM_ID" | tr '[:upper:]' '[:lower:]')"
  BUNDLE_ID="com.${TEAM_ID_LOWER}.PortfolioWorkbenchIOS"
fi

if ! has_xcode_account; then
  echo "No Xcode Apple account configured."
  echo "Open Xcode > Settings > Accounts and sign in with the Apple ID for team $TEAM_ID."
  echo "Then rerun this script."
  echo
  echo "For immediate local testing, use:"
  echo "  ./scripts/install_on_simulator.sh"
  exit 1
fi

if [[ -z "$SERVER_URL" ]]; then
  DETECTED_LAN_IP="$(detect_lan_ip || true)"
  if [[ -n "$DETECTED_LAN_IP" ]]; then
    SERVER_URL="http://$DETECTED_LAN_IP:$PORT/"
  fi
fi

if [[ -z "$DEVICE_DESTINATION_ID" ]]; then
  DEVICE_DESTINATION_ID="$(
    xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -showdestinations 2>/dev/null \
      | awk -F'id:' '/platform:iOS, arch:arm64/ && $0 !~ /Any iOS Device/ {split($2, fields, ","); gsub(/ /, "", fields[1]); print fields[1]; exit}'
  )"
fi

if [[ -z "$DEVICE_CORE_ID" ]]; then
  DEVICE_CORE_ID="$(
    xcrun devicectl list devices 2>/dev/null \
      | awk 'NR > 2 && $1 != "Name" && $1 != "----" {print $3; exit}'
  )"
fi

if [[ -z "$DEVICE_CORE_ID" ]]; then
  echo "No trusted iPhone found via devicectl."
  echo "Before retrying:"
  echo "1. Connect the iPhone with USB."
  echo "2. Tap Trust on the phone."
  echo "3. Enable Developer Mode on the phone if prompted."
  echo "4. Make sure Xcode is signed in with your Apple ID."
  exit 1
fi

echo "== Generating project =="
cd "$IOS_DIR"
if should_generate_project; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is required to create $PROJECT_PATH. Install with: brew install xcodegen"
    exit 1
  fi

  xcodegen generate
else
  echo "Using existing project at $PROJECT_PATH"
fi

if [[ -n "$SERVER_URL" ]]; then
  echo "Default server URL: $SERVER_URL"
fi

CURRENT_BUNDLE_ID="$(
  xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | sed -n 's/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = //p' \
    | head -n 1
)"

if [[ "$CURRENT_BUNDLE_ID" =~ ^[A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$ ]] && [[ "$BUNDLE_ID" != "$CURRENT_BUNDLE_ID" ]]; then
  perl -0pi -e "s/\Q$CURRENT_BUNDLE_ID\E/$BUNDLE_ID/g" "$PROJECT_PATH/project.pbxproj"
elif [[ "$BUNDLE_ID" != "$DEFAULT_APP_BUNDLE_ID" ]]; then
  perl -0pi -e "s/\Q$DEFAULT_APP_BUNDLE_ID\E/$BUNDLE_ID/g" "$PROJECT_PATH/project.pbxproj"
fi

uninstall_if_present() {
  local candidate_bundle_id="$1"
  if [[ -z "$candidate_bundle_id" ]]; then
    return 0
  fi

  echo
  echo "== Removing previous install for $candidate_bundle_id =="
  if xcrun devicectl device uninstall app --device "$DEVICE_CORE_ID" "$candidate_bundle_id" >/dev/null 2>&1; then
    echo "Removed existing app."
    return 0
  fi

  echo "No installed app found for this bundle ID."
}

declare -a UNINSTALL_BUNDLE_IDS=()
for candidate in "$BUNDLE_ID" "$CURRENT_BUNDLE_ID" "$DEFAULT_APP_BUNDLE_ID"; do
  already_added=0
  if [[ -z "$candidate" ]]; then
    continue
  fi
  for existing in "${UNINSTALL_BUNDLE_IDS[@]:-}"; do
    if [[ "$existing" == "$candidate" ]]; then
      already_added=1
      break
    fi
  done
  if [[ "$already_added" -eq 1 ]]; then
    continue
  fi
  UNINSTALL_BUNDLE_IDS+=("$candidate")
done

for candidate in "${UNINSTALL_BUNDLE_IDS[@]}"; do
  uninstall_if_present "$candidate"
done

echo
echo "== Building for iPhone =="
BUILD_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=iOS"
  -allowProvisioningUpdates
  -allowProvisioningDeviceRegistration
  DEVELOPMENT_TEAM="$TEAM_ID"
)

if [[ -n "$SERVER_URL" ]]; then
  BUILD_ARGS+=("PORTFOLIO_WORKBENCH_DEFAULT_SERVER_URL=$SERVER_URL")
fi

xcodebuild "${BUILD_ARGS[@]}" build

APP_PATH="$IOS_DIR/build/${CONFIGURATION}-iphoneos/${SCHEME}.app"

if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH="$(
    find "$HOME/Library/Developer/Xcode/DerivedData" \
      -path "*/Build/Products/${CONFIGURATION}-iphoneos/${SCHEME}.app" \
      ! -path "*/Index.noindex/*" \
      -type d \
      -print \
      | head -n 1
  )"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at: $APP_PATH"
  exit 1
fi

STAGING_DIR="$(mktemp -d /tmp/portfolio-workbench-device.XXXXXX)"
INSTALL_APP_PATH="$STAGING_DIR/${SCHEME}.app"
rm -rf "$INSTALL_APP_PATH"
ditto "$APP_PATH" "$INSTALL_APP_PATH"

ACTUAL_BUNDLE_ID="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALL_APP_PATH/Info.plist" 2>/dev/null || true
)"
if [[ -n "$ACTUAL_BUNDLE_ID" ]]; then
  BUNDLE_ID="$ACTUAL_BUNDLE_ID"
fi

echo
echo "== Installing on device $DEVICE_CORE_ID =="
xcrun devicectl device install app --device "$DEVICE_CORE_ID" "$INSTALL_APP_PATH"

echo
echo "== Launching =="
if ! xcrun devicectl device process launch --device "$DEVICE_CORE_ID" "$BUNDLE_ID"; then
  echo
  echo "App installed, but iOS denied the first launch."
  echo "On the iPhone, open:"
  echo "Settings > General > VPN & Device Management"
  echo "Trust the developer app for your Apple ID, then launch the app manually."
  exit 0
fi

echo
echo "Installed successfully."
echo "Bundle ID: $BUNDLE_ID"
echo "App path: $INSTALL_APP_PATH"
if [[ -n "$SERVER_URL" ]]; then
  echo "Default server URL: $SERVER_URL"
fi
