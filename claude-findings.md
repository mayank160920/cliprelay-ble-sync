# GreenPaste Codebase Review

> **Tracking instructions:** This file is a checklist. When a finding is addressed,
> mark it done by adding `- [x]` and wrapping the title in `~~strikethrough~~`.
> Unresolved items use `- [ ]`.

## Critical / High Severity

- [x] **1. ~~Device tag leaks encryption key material~~ — FIXED** (HKDF with separate info labels)
- [x] **2. ~~SHA-256 used as KDF with no domain separation~~ — FIXED** (HKDF with separate info labels)
- [ ] **3. No BLE flow control — chunk frames silently dropped under back-pressure**
  `macos/.../BLE/BLECentralManager.swift:133-145`
  Only the first chunk uses `.withResponse`; all subsequent chunks use `.withoutResponse` with a fixed 10ms delay. CoreBluetooth silently drops `.withoutResponse` writes when the transmit buffer is full. For 100 KiB payloads (~200 frames), drops are likely on congested links, silently corrupting the transfer. Should use `peripheralIsReady(toSendWriteWithoutResponse:)` for flow control.
- [ ] **4. Hash check bypassed when metadata notification is missing**
  `macos/.../BLE/BLECentralManager.swift:481-485`, `android/.../service/ClipShareService.kt:184-189`
  On both platforms, if the `Clipboard Available` metadata was never received (dropped BLE frame, or omitted), `pendingInboundHash` is nil/null and the integrity check is silently skipped. Data is accepted and decrypted without verification. The guard should require that metadata was received.
- [x] **5. ~~`minSdk = 35` should be 31~~ — FIXED** (now set to 29)
- [ ] **6. Race condition: executor shutdown vs GATT server stop**
  `android/.../service/ClipShareService.kt:128-133`
  `onDestroy()` calls `gattServer.stop()` then `transferExecutor.shutdown()`. `shutdown()` is graceful — already-submitted tasks keep running and can call `publishClipboardFrames()` on the now-closed GATT server. Should use `shutdownNow()` before stopping BLE, or gate tasks on a `@Volatile isDestroyed` flag.
- [ ] **7. `GattServerCallback.server` field has no visibility guarantee across threads**
  `android/.../ble/GattServerCallback.kt:20`
  `server` is assigned on the main thread but read from BLE Binder threads. Without `@Volatile`, the BLE callback thread may see a stale null and silently drop `sendResponse()` calls.
- [x] **8. ~~`Thread.sleep(8)` blocks the single-threaded transfer executor for ~1.6s during sends~~ — FIXED**
  `android/.../ble/GattServerManager.kt:103`
  For max 100 KiB payloads, 202 chunks x 8ms = ~1.6s of executor blocking. All incoming data processing is delayed during this window.
- [ ] **9. `stop()` on macOS can be undone by late CoreBluetooth callbacks**
  `macos/.../BLE/BLECentralManager.swift:65-81`
  After `stop()`, queued `didDisconnectPeripheral` callbacks fire and trigger `centralManager.connect()`, re-inserting peers into `connectingPeerIDs`. The manager silently restarts after being stopped. Needs an `isStopped` guard.
- [ ] **10. No BLE-level access control — any device can write to characteristics**
  `android/.../ble/GattServerManager.kt:39-50`
  Both characteristics use `PERMISSION_WRITE` (unauthenticated). Any BLE scanner can connect and write arbitrary bytes. AES-GCM decryption is the only defense, but the service still processes every write (JSON parsing, reassembly). Should use `PERMISSION_WRITE_ENCRYPTED` or check the device tag in callbacks.

## Medium Severity

- [ ] **11. `SecRandomCopyBytes` return value discarded**
  `macos/.../Pairing/PairingManager.swift:33-37`
  If `SecRandomCopyBytes` fails, `bytes` remains all zeroes and a zero token is stored as a valid pairing credential. The return value should be checked.
- [ ] **12. Keychain items stored without `kSecAttrAccessible`**
  `macos/.../Security/KeychainStore.swift:26-43`
  Defaults to `kSecAttrAccessibleAlways` — pairing tokens readable even when the device is locked. Should use `kSecAttrAccessibleAfterFirstUnlock`.
- [ ] **13. Silent fallback from encrypted to plaintext SharedPreferences**
  `android/.../pairing/PairingStore.kt:14-27`
  If `EncryptedSharedPreferences` creation fails, the code silently falls back to unencrypted `SharedPreferences` under the same filename. The 256-bit pairing token gets written as plaintext with no indication.
- [ ] **14. `BootCompletedReceiver` handles `ACTION_LOCKED_BOOT_COMPLETED` but service needs user unlock**
  `android/.../service/BootCompletedReceiver.kt:11-16`
  Starting the service before unlock causes `EncryptedSharedPreferences` to fail (Keystore keys unavailable), falling back to plaintext prefs without the token. Service starts unpaired. Should only handle `ACTION_BOOT_COMPLETED`.
- [ ] **15. Dual reconnect paths fire simultaneously on disconnect**
  `macos/.../BLE/BLECentralManager.swift:403-425`
  `didDisconnectPeripheral` both calls `centralManager.connect()` directly AND calls `scheduleReconnect()` (which rescans). Both paths independently try to reconnect, potentially producing duplicate connection requests.
- [ ] **16. Pairing window shows stale QR code**
  `macos/.../Pairing/PairingWindowController.swift:9-11`
  If the pairing window is already open, clicking "Pair New Device" generates a new token (stored in the device list) but the window keeps showing the old QR code. The new token becomes an orphaned "Pending pairing..." entry.
- [ ] **17. `GattServerManager` fields accessed from multiple threads without synchronization**
  `android/.../ble/GattServerManager.kt`
  `server`, `availableCharacteristic`, `dataCharacteristic` are plain `var`s accessed from both the main thread and `transferExecutor`. No `@Volatile` or synchronization.
- [ ] **18. BLE advertise `onStartFailure` doesn't clear callback — permanently blocks re-advertising**
  `android/.../ble/Advertiser.kt:53-57`
  On failure, `callback` field is still set, so future `start()` calls exit early (`if (callback != null) return`). Advertising becomes permanently broken until service restart.
- [ ] **19. `openGattServer` null return not handled**
  `android/.../ble/GattServerManager.kt:28`
  If `openGattServer` returns null (no BT adapter), subsequent operations silently no-op. No log or user notification.
- [ ] **20. `android:allowBackup="true"` may expose pairing token**
  `android/.../AndroidManifest.xml:13`
  ADB backup can include SharedPreferences. The encrypted prefs are Keystore-bound, but the plaintext fallback prefs would be included unprotected.
- [ ] **21. `ClipboardWriter` called from background thread**
  `android/.../service/ClipboardWriter.kt`
  `setPrimaryClip()` is called from `transferExecutor` (background thread) but is documented for the main thread. Can cause `CalledFromWrongThreadException` on some OEM firmware.
- [ ] **22. Notifications pile up — random UUID identifier on each**
  `macos/.../App/ReceiveNotificationManager.swift:23-27`
  Each clipboard receive creates a new notification with `UUID().uuidString`. Rapid transfers produce many stacked notifications. Using a stable identifier like `"clipboard-received"` would replace older ones.
- [ ] **23. `deviceStableID` returns random UUID on failure**
  `macos/.../BLE/BLECentralManager.swift:172-187`
  If `deviceTag` returns nil (malformed token), a new random `UUID()` is returned each call. The status bar UI can never match this peer as "connected" since the ID changes every time.

## Dead Code

- [ ] **24. `ClipboardContent` struct/class unused on both platforms**
  `macos/.../Models/ClipboardContent.swift`, `android/.../models/ClipboardContent.kt`
  Both are leftover from an earlier design. Delete them.
- [ ] **25. `KeychainStore.removeData` never called**
  `macos/.../Security/KeychainStore.swift:45-54`
  No call site exists. `PairingManager.removeDevice` overwrites the JSON blob but never calls this.
- [ ] **26. `ChunkAssembler.clear()` never called**
  `macos/.../BLE/ChunkAssembler.swift:23-28`
  The BLE manager always uses `reset(with:)` or discards the assembler entirely. `clear()` is dead.
- [ ] **27. `ChunkHeader.encoding` decoded but never validated or used**
  `macos/.../BLE/ChunkAssembler.swift:13,19` and `android/.../ble/ChunkReassembler.kt:6`
  Both platforms store the `encoding` field from chunk headers but always hardcode UTF-8 for decoding. If a non-UTF-8 encoding is sent, it's silently ignored.
- [ ] **28. `tx_id` parsed but never used on either platform**
  Protocol spec requires `tx_id` in both metadata and chunk headers. Both platforms decode it and discard it. No cross-check exists to correlate data frames with the correct announced transfer.
- [ ] **29. Metadata `size` and `type` fields ignored on receipt**
  `macos/.../BLE/BLECentralManager.swift:255-262`, `android/.../service/ClipShareService.kt:215-223`
  Both platforms extract only `hash` from the `Available` metadata. `size` (for pre-validation) and `type` (for content filtering) are decoded and discarded.

## Documentation Issues

- [ ] **30. Protocol spec contradicts implementation on encryption**
  `docs/protocol.md:31-33`
  Spec says: "No additional application-layer encryption in v1." The implementation has full AES-256-GCM encryption. This is the most authoritative protocol document and has the most critical inaccuracy.
- [ ] **31. README pairing instructions are wrong**
  `README.md:84-92`
  Describes OS-level Bluetooth pairing dialogs. The actual flow is QR-code-based application-layer pairing (Mac generates QR, Android scans it).
- [ ] **32. README security claim is wrong**
  `README.md:106`
  Claims "MVP security relies on BLE Secure Connections (no additional app-layer crypto)." The app has full application-layer crypto.
- [x] **33. ~~`project.md` says minSdk 31, `build.gradle.kts` has 35~~ — FIXED** (same as #5)

## Minor / Style

- [ ] **34. `security-crypto:1.1.0-alpha06` is an alpha dependency**
  `android/app/build.gradle.kts:44`
  Stable `1.0.0` provides the same APIs used by this project. Alpha in production is risky.
- [ ] **35. `BluetoothAdapter.getDefaultAdapter()` deprecated since API 31**
  `android/.../ble/Advertiser.kt:23,62`
  Should use `BluetoothManager.adapter` instead.
- [ ] **36. `isMinifyEnabled = false` for release builds**
  `android/app/build.gradle.kts:20`
  Leaves dead code and increases APK size. Enable R8 for release.
- [ ] **37. `sha256Hex` duplicated between BLECentralManager and ClipboardMonitor**
  `macos/.../BLE/BLECentralManager.swift:271`, `macos/.../Clipboard/ClipboardMonitor.swift:47`
  Identical logic in two places. Should be a shared utility.
- [ ] **38. `findDevice(byTag:)` does keychain I/O + HKDF per device on every BLE advertisement**
  `macos/.../Pairing/PairingManager.swift:63-68`
  Called on every BLE scan result (100-500ms intervals). Does a full keychain read + JSON decode + N HKDF derivations. Tags should be cached in memory.
- [ ] **39. Duplicate `CCC_DESCRIPTOR_UUID` constant**
  `android/.../ble/GattServerManager.kt:19`, `android/.../ble/GattServerCallback.kt:17`
  Same UUID defined in two files. Should be a shared constant.
- [ ] **40. No `onRequestPermissionsResult` handler**
  `android/.../ui/MainActivity.kt:129-131`
  Permission denial is silently ignored. BLE operations fail with no user feedback.
- [ ] **41. Stale `rm -rf ClipShareMac.app` in build script**
  `scripts/build-all.sh:76`
  Cleanup for old branding name. Harmless but dead weight.
