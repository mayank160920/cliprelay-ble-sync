#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
ANDROID_APP_ID="com.clipshare"

ANDROID_SERIAL=""

usage() {
  cat <<'EOF'
Usage: ./scripts/ble-hardware-smoke.sh [--serial <adb-serial>]

Runs non-destructive preflight checks for the manual BLE smoke pass and
prints a checklist for:
  1) Mac -> Android clipboard sync
  2) Android Share -> Mac clipboard sync
  3) Reconnect after Android Bluetooth toggle
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --serial" >&2
        exit 1
      fi
      ANDROID_SERIAL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

ADB=(adb)
if [[ -n "$ANDROID_SERIAL" ]]; then
  ADB=(adb -s "$ANDROID_SERIAL")
fi

echo "==> Hardware smoke preflight"

if [[ ! -d "$DIST_DIR/GreenPaste.app" ]]; then
  echo "Missing macOS app bundle: $DIST_DIR/GreenPaste.app" >&2
  echo "Build first: ./scripts/build-all.sh" >&2
  exit 1
fi

if [[ ! -f "$DIST_DIR/greenpaste-debug.apk" ]]; then
  echo "Missing Android APK: $DIST_DIR/greenpaste-debug.apk" >&2
  echo "Build first: ./scripts/build-all.sh" >&2
  exit 1
fi

echo "- Found macOS bundle and Android APK in dist/"

if command -v adb >/dev/null 2>&1; then
  set +e
  DEVICE_STATE="$(${ADB[@]} get-state 2>/dev/null)"
  ADB_STATUS=$?
  set -e

  if [[ $ADB_STATUS -eq 0 && "$DEVICE_STATE" == "device" ]]; then
    echo "- ADB device online"
    if ${ADB[@]} shell pm list packages | tr -d '\r' | grep -q "^package:${ANDROID_APP_ID}$"; then
      echo "- Android app installed: ${ANDROID_APP_ID}"
    else
      echo "- Android app not installed yet"
      echo "  Install with: adb install -r dist/greenpaste-debug.apk"
    fi
  else
    echo "- No online Android device detected via adb"
    echo "  Connect device and enable USB debugging for install/log capture"
  fi
else
  echo "- adb not found; skipping Android device checks"
fi

echo
echo "==> Manual BLE smoke checklist"
echo "[ ] Launch GreenPaste on macOS and start Android foreground service"
echo "[ ] Verify paired/trusted device appears on both sides"
echo "[ ] Mac -> Android: copy unique text on macOS and confirm it appears on Android clipboard"
echo "[ ] Android -> Mac: share unique text to GreenPaste and confirm macOS pasteboard updates"
echo "[ ] Reconnect: toggle Bluetooth OFF then ON on Android, wait for reconnect, repeat both sync checks"
echo
echo "Log suggestions:"
echo "- macOS app logs: Console.app (filter for GreenPaste)"
echo "- Android logs: adb logcat | grep -E 'ClipShareService|GattServer|Advertiser'"
echo
echo "Automated helper (debug builds): ./scripts/ble-hardware-smoke-auto.sh"
