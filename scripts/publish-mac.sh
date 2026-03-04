#!/usr/bin/env bash
# Signs, packages, notarizes, and staples the macOS app for distribution.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/ClipRelay.app"
DMG_PATH="$DIST_DIR/ClipRelay.dmg"
ENTITLEMENTS="$ROOT_DIR/macos/ClipRelayMac/Resources/ClipRelay.entitlements"
SIGNING_IDENTITY="Developer ID Application: Christian Theilemann (B66YFKPUA8)"
KEYCHAIN_PROFILE="ClipRelay"

usage() {
  cat <<'EOF'
Usage: ./scripts/publish-mac.sh [options]

Signs, packages into DMG, notarizes, and staples the macOS app.

Prerequisites:
  - Run ./scripts/build-all.sh --mac-only first
  - Developer ID certificate in Keychain
  - Notarytool keychain profile "ClipRelay" configured

Options:
  -h, --help    Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

# ── Preflight checks ──

if [[ ! -d "$APP_DIR" ]]; then
  echo "dist/ClipRelay.app not found. Run ./scripts/build-all.sh --mac-only first." >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
  echo "Signing identity not found: $SIGNING_IDENTITY" >&2
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "Entitlements file not found: $ENTITLEMENTS" >&2
  exit 1
fi

# ── 1. Re-sign with Developer ID ──

echo "==> Signing with Developer ID + hardened runtime"
codesign --force --deep --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    --timestamp \
    "$APP_DIR"
echo "Signing complete."

codesign -dvv "$APP_DIR" 2>&1 | grep -E "Authority|TeamIdentifier"

# ── 2. Create DMG ──

echo "==> Creating DMG"
rm -f "$DMG_PATH"
hdiutil create -volname "ClipRelay" \
    -srcfolder "$APP_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"
echo "DMG created: $DMG_PATH"

# ── 3. Notarize ──

echo "==> Submitting to Apple notarization (this may take a few minutes)..."
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

# ── 4. Staple ──

echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP_DIR"
xcrun stapler staple "$DMG_PATH"

# ── 5. Verify ──

echo "==> Verification"
echo "--- App signature ---"
codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>&1
echo "--- DMG staple ---"
xcrun stapler validate "$DMG_PATH"

echo ""
echo "==> Publish complete: $DMG_PATH"
