# ClipRelay Security Review

**Date:** 2026-03-03
**Scope:** Full codebase — crypto/protocol, macOS app, Android app, website, scripts
**Method:** Parallel automated review (4 agents) + validation pass (1 agent)
**Validation:** 11 confirmed, 2 partially confirmed, 0 false positives

---

## Executive Summary

ClipRelay implements a BLE-based clipboard relay between macOS and Android using AES-256-GCM encryption with HKDF-derived keys, shared via a QR code pairing flow. The cryptographic primitives are well-chosen and correctly implemented. The primary weaknesses are at the protocol design layer (unauthenticated handshake, no replay protection) and the macOS build pipeline (no sandbox, no hardened runtime, debug surfaces in release). No immediately exploitable remote vulnerabilities were found — all attacks require BLE proximity or local access.

---

## Findings

### CRITICAL

#### C-1: SmokeAutomationCLI available in release builds

**Files:** `macos/ClipRelayMac/Sources/main.swift:16`, `macos/ClipRelayMac/Sources/App/SmokeAutomationCLI.swift`
**Validated:** CONFIRMED

`--smoke-import-pairing` and `--smoke-remove-pairing` CLI flags are called unconditionally in `main.swift` with no `#if DEBUG` guard. Any local process that can execute the binary can inject a pairing token (replacing the legitimate one with an attacker-controlled token) or remove existing pairings.

**Fix:** Wrap `SmokeAutomationCLI.runIfRequested()` in `#if DEBUG`.

---

### HIGH

#### H-1: No replay protection at protocol layer

**Files:** `macos/ClipRelayMac/Sources/Protocol/Session.swift`, `android/.../protocol/Session.kt`
**Validated:** PARTIALLY CONFIRMED (originally reported as Critical, downgraded)

No sequence numbers, timestamps, or nonce-tracking at the session layer. The dedup mechanism (`lastReceivedHash` / `lastInboundHash`) is a single in-memory value that does not persist across restarts. An attacker in BLE range who captures an encrypted L2CAP frame can replay it after the target app restarts. Mitigating factor: AES-GCM uses a fresh random nonce per encryption, so the dedup hash changes even for the same plaintext — the attacker can only replay the exact captured ciphertext, not forge new content.

**Fix:** Add a monotonically increasing sequence number to OFFER messages. Reject messages with a sequence number <= the highest previously seen.

#### H-2: Handshake has no cryptographic authentication

**Files:** `macos/.../Protocol/Session.swift:97-121`, `android/.../protocol/Session.kt:80-104`
**Validated:** CONFIRMED

The HELLO/WELCOME exchange only transmits `{"version": 1, "name": "..."}`. No HMAC, challenge-response, or proof-of-possession of the shared pairing token. Any BLE device in range can complete the handshake. Authentication is implicit only — a rogue device would fail at AES-GCM decryption, but the session is already established and the legitimate peer may be blocked from connecting.

**Fix:** Add a challenge-response step: each side sends a random nonce, the other side responds with `HMAC(nonce, derived_auth_key)` to prove possession of the shared secret before exchanging clipboard data.

#### H-3: App is not sandboxed

**Files:** `macos/ClipRelayMac/Resources/ClipRelay.entitlements`, `scripts/build-all.sh`
**Validated:** CONFIRMED

`com.apple.security.app-sandbox` is absent from the entitlements file, and the entitlements file is never embedded during code signing (no `codesign --entitlements` step in `build-all.sh`). The app runs with full user-level filesystem, network, and IPC access.

**Fix:**
1. Add `com.apple.security.app-sandbox = true` to the entitlements file.
2. Add `codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" --options runtime "$app_dir"` to `build-all.sh`.

#### H-4: No hardened runtime

**Files:** `scripts/build-all.sh`
**Validated:** CONFIRMED

The build script contains no `codesign` invocation. The binary is produced by `swift build --configuration release` which only linker-signs it (ad-hoc). Without hardened runtime (`--options runtime`), DYLD injection, debugging, and memory manipulation by other processes are unrestricted.

**Fix:** Sign with `codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" --options runtime "$app_dir"`.

#### H-5: Debug log writes to world-readable /tmp in release builds

**Files:** `macos/.../App/AppDelegate.swift:11-22`, `macos/.../BLE/ConnectionManager.swift:9-20`
**Validated:** CONFIRMED

`debugLog()` writes to `/tmp/cliprelay-debug.log` unconditionally in all builds. No `#if DEBUG` guard. The file is world-readable by default on macOS and leaks BLE connection state, PSM values, device names, and timing information.

**Fix:** Guard `debugLog()` behind `#if DEBUG`, or replace with `os.Logger` exclusively and remove the file-based logger.

#### H-6: Insecure L2CAP channel (no BLE-level encryption)

**Files:** `android/.../ble/L2capServer.kt:30`
**Validated:** CONFIRMED

Uses `adapter.listenUsingInsecureL2capChannel()`. This is an intentional design choice (app-layer AES-256-GCM provides encryption), but the BLE link layer is unencrypted. Traffic metadata (message sizes, timing) is visible to nearby observers, and active MITM can selectively drop or delay messages.

**Fix:** Consider using `listenUsingL2capChannel()` (secure variant) for defense-in-depth, or document as accepted risk.

#### H-7: Plaintext fallback for pairing token storage

**Files:** `android/.../pairing/PairingStore.kt:37-41`
**Validated:** CONFIRMED

When `EncryptedSharedPreferences` fails, the pairing token (root secret for AES-256 key derivation) silently falls back to plaintext `SharedPreferences`. The plaintext copy is never cleaned up even if encrypted storage later becomes available.

**Fix:** Fail hard instead of falling back. If encrypted storage is unavailable, refuse to store the token and inform the user.

---

### MEDIUM

#### M-1: HKDF used without salt on both platforms

**Files:** `macos/.../Pairing/PairingManager.swift:78-82`, `android/.../crypto/E2ECrypto.kt:47-51`
**Validated:** CONFIRMED

Both HKDF implementations use no salt (macOS omits it; Android uses all-zeros). Per RFC 5869 this is acceptable when IKM has high entropy (256 bits here), but best practice is to use an application-specific salt.

**Fix:** Add a fixed salt string (e.g., `"cliprelay-salt-v1"`) to both platforms.

#### M-2: macOS key derivation split across modules

**Files:** `macos/.../Crypto/E2ECrypto.swift`, `macos/.../Pairing/PairingManager.swift`

The macOS `E2ECrypto` module contains only `seal` and `open`. Key derivation lives in `PairingManager.swift`, unlike Android where `E2ECrypto.kt` centralizes both. This asymmetry makes cross-platform consistency harder to audit.

**Fix:** Add `deriveKey` and `deviceTag` methods to macOS `E2ECrypto` for parity.

#### M-3: Notification preview leaks clipboard content

**Files:** `macos/.../App/ReceiveNotificationManager.swift:17-31`
**Validated:** CONFIRMED

The notification body contains `String(text.prefix(80))` — the first 80 characters of received clipboard text. Visible on the lock screen by default.

**Fix:** Use a generic body like "Clipboard received from [device]" without content preview.

#### M-4: SecItemUpdate path doesn't set kSecAttrAccessible

**Files:** `macos/.../Security/KeychainStore.swift:28-46`

Only the `SecItemAdd` code path sets `kSecAttrAccessible`. The `SecItemUpdate` path preserves whatever accessibility level the item was originally created with.

**Fix:** Include `kSecAttrAccessible` in the update attributes dictionary.

#### M-5: CLIPRELAY_POLL_INTERVAL_MS env var active in release

**Files:** `macos/.../Clipboard/ClipboardMonitor.swift:7-16`
**Validated:** CONFIRMED

The environment variable is read unconditionally with no `#if DEBUG` guard.

**Fix:** Guard behind `#if DEBUG`.

#### M-6: No payload size validation before ACCEPT

**Files:** `macos/.../Protocol/Session.swift:219-232`, `android/.../protocol/Session.kt:216-229`
**Validated:** CONFIRMED

When an OFFER is received, the `size` field is never inspected before sending ACCEPT. The receiver blindly accepts any OFFER regardless of claimed payload size.

**Fix:** Validate `size` against `MAX_CLIPBOARD_BYTES` before sending ACCEPT.

#### M-7: DebugSmokeReceiver exported without permission guard

**Files:** `android/app/src/debug/AndroidManifest.xml:4-12`
**Validated:** PARTIALLY CONFIRMED (debug-only, not in release builds)

The receiver is `android:exported="true"` with no `android:permission` attribute. Since it's in `src/debug/`, it only ships in debug APKs, limiting risk to developer devices. Any app on a debug device can send `IMPORT_PAIRING` / `CLEAR_PAIRING` intents.

**Fix:** Add `android:permission="org.cliprelay.permission.DEBUG_SMOKE"` with `protectionLevel="signature"`.

#### M-8: BootCompletedReceiver missing sender permission check

**Files:** `android/app/src/main/AndroidManifest.xml:43-50`

The receiver is `exported="true"` (required for BOOT_COMPLETED) but any app can send a crafted `BOOT_COMPLETED` intent to start the foreground service.

**Fix:** Add `android:permission="android.permission.RECEIVE_BOOT_COMPLETED"`.

#### M-9: registerReceiver missing RECEIVER_NOT_EXPORTED

**Files:** `android/.../service/ClipRelayService.kt:115`
**Validated:** CONFIRMED

Uses legacy `registerReceiver()` without `RECEIVER_NOT_EXPORTED` flag, unlike `MainActivity.kt` which correctly uses `ContextCompat.registerReceiver()`. On Android 14+ this will crash.

**Fix:** Use `ContextCompat.registerReceiver()` with `RECEIVER_NOT_EXPORTED`.

#### M-10: No Content Security Policy on website

**Files:** `website/index.html`, `website/privacy.html`
**Validated:** CONFIRMED

No `<meta http-equiv="Content-Security-Policy">` tag. The site is static with no XSS vectors today, but CSP provides defense-in-depth.

**Fix:** Add a CSP meta tag restricting `default-src 'none'` with allowlists for styles, fonts, scripts, and images.

#### M-11: Google Fonts loaded without SRI / not self-hosted

**Files:** `website/index.html:23`, `website/privacy.html:13`

External CSS from `fonts.googleapis.com` without `integrity` attribute. SRI is impractical for Google Fonts (response varies by user agent). Also a privacy concern — every visitor's IP is sent to Google, inconsistent with the privacy-first branding.

**Fix:** Self-host the Inter and Outfit WOFF2 files.

#### M-12: Pairing token printed to stdout in auto-pair.sh

**Files:** `scripts/auto-pair.sh:40-42, 109`

The full 256-bit hex token is printed to stdout. Could leak via CI logs or terminal scrollback.

**Fix:** Print only a fingerprint: `echo "Token fingerprint: ...${TOKEN:56:8}"`.

---

### LOW

| # | Finding | Location |
|---|---------|----------|
| L-1 | Static BLE device tag (8-byte HKDF derivative) enables location tracking across sessions | `Advertiser.kt`, `ConnectionManager.swift` |
| L-2 | Android HKDF counter is a signed `Byte` — overflow potential if deriving >8160 bytes | `E2ECrypto.kt:58` |
| L-3 | Non-constant-time hash comparison (not practically exploitable over BLE) | `Session.swift`, `Session.kt` |
| L-4 | Keychain `kSecAttrAccessibleAfterFirstUnlock` could use `WhenUnlockedThisDeviceOnly` | `KeychainStore.swift:42` |
| L-5 | `PeerSummary.token` carries raw token through UI layer via `NSMenuItem.representedObject` | `PeerSummary.swift` |
| L-6 | BLE manufacturer data uses reserved company ID `0xFFFF` | `Advertiser.kt:94` |
| L-7 | `Log.w` statements expose device address and PSM in release logcat | `PsmGattServer.kt:54`, `ClipRelayService.kt:235` |
| L-8 | ProGuard rules file is empty — no log stripping configured | `android/app/proguard-rules.pro` |
| L-9 | `security-crypto` uses alpha version `1.1.0-alpha06` | `android/app/build.gradle.kts:170` |

---

## What's Done Well

- **AES-256-GCM** with HKDF domain separation (`cliprelay-enc-v1` vs `cliprelay-tag-v1`) and AAD (`cliprelay-v1`)
- **Cryptographically secure token generation** via `SecRandomCopyBytes` (256 bits)
- **Cross-platform test vectors** for crypto interoperability
- **`android:allowBackup="false"`**, package-scoped broadcasts, unexported services
- **No XSS vectors** in website JS — zero `innerHTML`/`eval`/`document.write` usage
- **All shell scripts** use `set -euo pipefail` with properly quoted variables
- **No hardcoded secrets** anywhere in the codebase
- **Message size limits** (200KB codec cap, 100KB clipboard cap on send side)
- **EncryptedSharedPreferences** as primary storage for Android pairing token
- **`neverForLocation`** flag on `BLUETOOTH_SCAN` permission
- **SHA-256 integrity check** on received payloads

---

## Recommended Priority Order

### Quick wins

1. **C-1** — Wrap `SmokeAutomationCLI` in `#if DEBUG`
2. **H-5** — Remove `/tmp` file logging from release builds
3. **M-3** — Remove clipboard preview from notifications
4. **M-5** — Guard poll interval env var behind `#if DEBUG`
5. **M-12** — Print only token fingerprint in scripts
6. **M-9** — Fix `registerReceiver` to use `RECEIVER_NOT_EXPORTED`

### Moderate effort

7. **H-3 + H-4** — Enable App Sandbox + hardened runtime in build pipeline
8. **H-7** — Fail hard instead of plaintext fallback on Android
9. **M-6** — Validate OFFER size before ACCEPT
10. **M-10** — Add CSP meta tags to website
11. **M-11** — Self-host Google Fonts

### Significant effort (protocol changes)

12. **H-2** — Add mutual authentication (challenge-response) to handshake
13. **H-1** — Add sequence numbers / replay protection to protocol
