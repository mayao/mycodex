#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$IOS_DIR/PortfolioWorkbenchIOS.xcodeproj"
SCHEME="PortfolioWorkbenchIOS"
CONFIGURATION="${CONFIGURATION:-Debug}"
PORT="${PORT:-8008}"
SERVER_URL="${SERVER_URL:-http://127.0.0.1:8008/}"
SIMULATOR_NAME="${SIMULATOR_NAME:-}"
SIMULATOR_ID="${SIMULATOR_ID:-}"
SKIP_XCODEGEN="${SKIP_XCODEGEN:-auto}"

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

if [[ "$SERVER_URL" == "http://127.0.0.1:8008/" ]]; then
  LAN_IP="$(detect_lan_ip || true)"
  if [[ -n "$LAN_IP" ]]; then
    SERVER_URL="http://$LAN_IP:$PORT/"
  fi
fi

resolve_simulator_id() {
  python3 - "$SIMULATOR_NAME" <<'PY'
import json
import subprocess
import sys

preferred_name = sys.argv[1].strip()
payload = json.loads(
    subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        text=True,
    )
)

preferred = None
booted = None
fallback = None
for runtime_devices in payload.get("devices", {}).values():
    for device in runtime_devices:
        if not device.get("isAvailable"):
            continue
        name = str(device.get("name") or "")
        if not name.startswith("iPhone"):
            continue
        if fallback is None:
            fallback = device.get("udid")
        if booted is None and device.get("state") == "Booted":
            booted = device.get("udid")
        if preferred_name and name == preferred_name:
            preferred = device.get("udid")
            break
    if preferred:
        break

selected = preferred or booted or fallback
if not selected:
    sys.exit(1)

print(selected)
PY
}

if [[ -z "$SIMULATOR_ID" ]]; then
  SIMULATOR_ID="$(resolve_simulator_id)"
fi

if [[ -z "$SIMULATOR_ID" ]]; then
  echo "No available iPhone simulator found."
  exit 1
fi

echo "== Booting simulator $SIMULATOR_ID =="
open -a Simulator >/dev/null 2>&1 || true
xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b

echo
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

echo
echo "== Building for simulator =="
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=$SIMULATOR_ID" \
  "PORTFOLIO_WORKBENCH_DEFAULT_SERVER_URL=$SERVER_URL" \
  build

APP_PATH="$IOS_DIR/build/${CONFIGURATION}-iphonesimulator/${SCHEME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH="$(
    find "$HOME/Library/Developer/Xcode/DerivedData" \
      -path "*/Build/Products/${CONFIGURATION}-iphonesimulator/${SCHEME}.app" \
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

STAGING_DIR="$(mktemp -d /tmp/portfolio-workbench-sim.XXXXXX)"
INSTALL_APP_PATH="$STAGING_DIR/${SCHEME}.app"
rm -rf "$INSTALL_APP_PATH"
ditto "$APP_PATH" "$INSTALL_APP_PATH"

BUNDLE_ID="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALL_APP_PATH/Info.plist" 2>/dev/null || true
)"
if [[ -z "$BUNDLE_ID" ]]; then
  echo "Unable to read bundle identifier from $INSTALL_APP_PATH/Info.plist"
  exit 1
fi

echo
echo "== Installing on simulator =="
xcrun simctl install "$SIMULATOR_ID" "$INSTALL_APP_PATH"

DATA_CONTAINER="$(xcrun simctl get_app_container "$SIMULATOR_ID" "$BUNDLE_ID" data)"
PREFS_FILE="$DATA_CONTAINER/Library/Preferences/${BUNDLE_ID}.plist"
mkdir -p "$(dirname "$PREFS_FILE")"
python3 - "$PREFS_FILE" "$SERVER_URL" <<'PY'
import plistlib
import pathlib
import sys

prefs_path = pathlib.Path(sys.argv[1])
server_url = sys.argv[2]
data = {}
if prefs_path.exists():
    try:
        with prefs_path.open('rb') as handle:
            data = plistlib.load(handle)
    except Exception:
        data = {}
data['portfolio-workbench-ios.server-url'] = server_url
with prefs_path.open('wb') as handle:
    plistlib.dump(data, handle)
PY

echo
echo "== Launching =="
xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID"

echo
echo "Installed successfully."
echo "Simulator ID: $SIMULATOR_ID"
echo "Bundle ID: $BUNDLE_ID"
echo "App path: $INSTALL_APP_PATH"
echo "Default server URL: $SERVER_URL"
