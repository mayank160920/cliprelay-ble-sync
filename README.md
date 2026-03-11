# ClipRelay

Seamless, encrypted clipboard sharing between Mac and Android over Bluetooth.

- **End-to-end encrypted** — ECDH key exchange (X25519) with AES-256-GCM encryption
- **Bluetooth only** — direct BLE transfer, no WiFi or internet needed
- **No cloud, no servers** — your clipboard data never leaves the connection between your devices
- **Text only** — up to 100 KiB per transfer

## Download

The easiest way to get ClipRelay is from the official releases:

- **Android** — [Join the beta on Google Play](https://cliprelay.org/beta.html)
- **Mac** — [Download the DMG](https://cliprelay.org/downloads/ClipRelay.dmg)

For more details, visit [cliprelay.org](https://cliprelay.org).

## How it works

1. Install ClipRelay on both your Mac and Android device.
2. Open the Mac app (menu bar icon appears), click "Pair New Device" to show a QR code.
3. Open the Android app, tap "Pair with Mac", and scan the QR code.
4. Done — clipboard sharing is automatic:
   - **Mac to Android:** copy text on Mac, it syncs automatically.
   - **Android to Mac:** select text on Android, Share → ClipRelay.

## Building from source

### Prerequisites

**macOS app:**
- macOS with Xcode Command Line Tools (`xcode-select --install`)
- `swift` available in PATH

**Android app:**
- JDK 17 or newer
- Android SDK (via Android Studio or standalone)
- `ANDROID_HOME` set or Android Studio configured

### Build

```bash
# Build both platforms (debug)
./scripts/build-all.sh

# Build only one platform
./scripts/build-all.sh --mac-only
./scripts/build-all.sh --android-only

# Release build (requires signing configuration)
./scripts/build-all.sh --release
```

**Output artifacts:**

| Artifact | Path |
|----------|------|
| Mac app | `dist/ClipRelay.app` |
| Android debug APK | `dist/cliprelay-debug.apk` |
| Android release AAB | `dist/cliprelay-release.aab` |
| Android release APK | `dist/cliprelay-release.apk` |

### Install from build

**Mac:**

```bash
cp -R dist/ClipRelay.app /Applications/
open /Applications/ClipRelay.app
```

On first run, macOS may block an unsigned app. Right-click → Open in Finder, then approve in System Settings → Privacy & Security.

**Android:**

```bash
adb install -r dist/cliprelay-debug.apk
```

### Release signing (Android)

For release builds, configure signing via `android/keystore.properties`:

```properties
storeFile=../path-to-keystore.jks
storePassword=...
keyAlias=...
keyPassword=...
```

Or set environment variables: `CLIPRELAY_STORE_FILE`, `CLIPRELAY_STORE_PASSWORD`, `CLIPRELAY_KEY_ALIAS`, `CLIPRELAY_KEY_PASSWORD`.

## Development

### Running tests

```bash
# Unit tests (Android + Mac)
./scripts/test-all.sh
```

### Hardware smoke tests

For real-device BLE verification (requires a Mac host + Android phone connected via USB):

```bash
./scripts/hardware-smoke-test.sh
```

Options:

```bash
# Target a specific device
./scripts/hardware-smoke-test.sh --serial <adb-serial>

# Tune connection parameters
./scripts/hardware-smoke-test.sh --stability-seconds 8
./scripts/hardware-smoke-test.sh --timeout 90

# Stress test with repeated transfers
./scripts/hardware-smoke-test.sh --m2a-stress-count 25 --m2a-stress-timeout 12

# Keep the test pairing after the run (removed by default)
./scripts/hardware-smoke-test.sh --keep-pairing
```

When a smoke step fails, the script auto-dumps Android BLE logs, probe state, and recent macOS ClipRelay logs.

### Project structure

```
android/          Android app (Kotlin, Jetpack Compose)
ClipRelay/        macOS app (Swift)
website/          Static website (HTML/CSS/JS, hosted on Cloudflare Pages)
scripts/          Build, test, and publish scripts
docs/             Design documents and plans
```

## License

This source code is made available for reference and review purposes. See [LICENSE](LICENSE) for details.
