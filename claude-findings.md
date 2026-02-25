# Claude Findings Tracker

> **Tracking instructions**
> - When a finding is addressed, change `- [ ]` to `- [x]`.
> - Wrap the finding title in `~~strikethrough~~` when completed.
> - Keep unresolved items as `- [ ]`.

## Open Findings (Special Review List)

Use this section for final disposition decisions on unresolved findings.

### Do Now

- [ ] **#10: No BLE-level access control — any device can write to characteristics**
  Suggested disposition: implement BLE abuse guardrails (strict frame limits, fail-fast parsing, and rate limits) while keeping app-layer pairing.

### Accept Risk (Close With Rationale)

- [ ] **#27: `ChunkHeader.encoding` decoded but never validated or used**
  Suggested disposition: keep for protocol forward compatibility.
- [ ] **#28: `tx_id` parsed but never used on either platform**
  Suggested disposition: keep for protocol compliance and future compatibility.
- [ ] **#29: Metadata `size` and `type` fields ignored on receipt**
  Suggested disposition: keep current behavior until non-text payload handling is implemented.
- [ ] **#34: `security-crypto:1.1.0-alpha06` is an alpha dependency**
  Suggested disposition: keep current dependency until a stable, API-compatible release exists.
- [ ] **#37: `sha256Hex` duplicated between BLECentralManager and ClipboardMonitor**
  Suggested disposition: keep as-is; duplication is small and low-risk.

## Critical / High Severity

- [x] **1. ~~Device tag leaks encryption key material~~ — FIXED** (HKDF with separate info labels)
- [x] **2. ~~SHA-256 used as KDF with no domain separation~~ — FIXED** (HKDF with separate info labels)
- [x] **3. ~~No BLE flow control — chunk frames silently dropped under back-pressure~~ — FIXED**
  `macos/.../BLE/BLECentralManager.swift`
  Replaced fixed 10ms timer delays with `peripheralIsReady(toSendWriteWithoutResponse:)` flow control. Outbound frames are queued and drained as the BLE transmit buffer becomes available.
- [x] **4. ~~Hash check bypassed when metadata notification is missing~~ — FIXED**
  `macos/.../BLE/BLECentralManager.swift`, `android/.../ble/BleInboundStateMachine.kt`
  Android: `BleInboundStateMachine` requires `pendingMetadataHash` to be non-null. macOS: changed to `guard let` — rejects assembled data when no metadata hash was received.
- [x] **5. ~~`minSdk = 35` should be 31~~ — FIXED** (now set to 29)
- [x] **6. ~~Race condition: executor shutdown vs GATT server stop~~ — FIXED**
  `android/.../service/ClipShareService.kt`
  Added `@Volatile isDestroyed` flag, switched to `shutdownNow()`, and added guard in `pushPlainTextToMac`.
- [x] **7. ~~`GattServerCallback.server` field has no visibility guarantee across threads~~ — FIXED**
  `android/.../ble/GattServerCallback.kt`
  Added `@Volatile` annotation.
- [x] **8. ~~`Thread.sleep(8)` blocks the single-threaded transfer executor for ~1.6s during sends~~ — FIXED**
  `android/.../ble/GattServerManager.kt`
  Now uses `Semaphore`/`onNotificationSent` for proper BLE flow control.
- [x] **9. ~~`stop()` on macOS can be undone by late CoreBluetooth callbacks~~ — FIXED**
  `macos/.../BLE/BLECentralManager.swift`
  Added `isStopped` flag set in `stop()`, cleared in `start()`, guarded in `didDisconnectPeripheral`.
- [ ] **10. No BLE-level access control — any device can write to characteristics**
  `android/.../ble/GattServerManager.kt:39-50`
  Both characteristics use `PERMISSION_WRITE` (unauthenticated). Any BLE scanner can connect and write arbitrary bytes. AES-GCM decryption is the only defense, but the service still processes every write (JSON parsing, reassembly). Acknowledged as a design trade-off: `PERMISSION_WRITE_ENCRYPTED` requires OS-level BLE pairing which this app intentionally avoids. AES-GCM provides the access control layer.

## Medium Severity

- [x] **11. ~~`SecRandomCopyBytes` return value discarded~~ — FIXED**
  `macos/.../Pairing/PairingManager.swift`
  `generateToken()` now returns `String?` and checks the return value. Caller guards with `guard let`.
- [x] **12. ~~Keychain items stored without `kSecAttrAccessible`~~ — FIXED**
  `macos/.../Security/KeychainStore.swift`
  Added `kSecAttrAccessibleAfterFirstUnlock` to keychain add operations.
- [x] **13. ~~Silent fallback from encrypted to plaintext SharedPreferences~~ — FIXED**
  `android/.../pairing/PairingStore.kt`
  Added logging when EncryptedSharedPreferences is unavailable and when falling back to plaintext.
- [x] **14. ~~`BootCompletedReceiver` handles `ACTION_LOCKED_BOOT_COMPLETED` but service needs user unlock~~ — FIXED**
  `android/.../service/BootCompletedReceiver.kt`, `AndroidManifest.xml`
  Removed `ACTION_LOCKED_BOOT_COMPLETED` from both receiver code and manifest intent-filter.
- [x] **15. ~~Dual reconnect paths fire simultaneously on disconnect~~ — FIXED**
  `macos/.../BLE/BLECentralManager.swift`
  `didDisconnectPeripheral` now only calls `scheduleReconnect()` when the peripheral is NOT in the token map (unknown device). For known paired peripherals, direct `connectToPairedPeerIfNeeded` is used exclusively.
- [x] **16. ~~Pairing window shows stale QR code~~ — ALREADY FIXED**
  `macos/.../Pairing/PairingWindowController.swift`
  `showPairingQR(uri:)` replaces the window's `contentView` with a fresh view built from the new URI when the window is already open.
- [x] **17. ~~`GattServerManager` fields accessed from multiple threads without synchronization~~ — FIXED**
  `android/.../ble/GattServerManager.kt`
  Added `@Volatile` to `server`, `availableCharacteristic`, and `dataCharacteristic`.
- [x] **18. ~~BLE advertise `onStartFailure` doesn't clear callback — permanently blocks re-advertising~~ — ALREADY FIXED**
  `android/.../ble/Advertiser.kt`
  `onStartFailure` already sets `callback = null` before scheduling retry.
- [x] **19. ~~`openGattServer` null return not handled~~ — FIXED**
  `android/.../ble/GattServerManager.kt`
  Added null check with early return and error log.
- [x] **20. ~~`android:allowBackup="true"` may expose pairing token~~ — FIXED**
  `android/.../AndroidManifest.xml`
  Changed to `android:allowBackup="false"`.
- [x] **21. ~~`ClipboardWriter` called from background thread~~ — FIXED**
  `android/.../service/ClipboardWriter.kt`
  Now dispatches `setPrimaryClip` to main thread via `Handler(Looper.getMainLooper())` when called from a background thread.
- [x] **22. ~~Notifications pile up — random UUID identifier on each~~ — FIXED**
  `macos/.../App/ReceiveNotificationManager.swift`
  Changed identifier from `UUID().uuidString` to stable `"clipboard-received"` so new notifications replace the previous one.
- [x] **23. ~~`deviceStableID` returns random UUID on failure~~ — FIXED**
  `macos/.../BLE/BLECentralManager.swift`
  Fallback now uses a deterministic UUID derived from the token string instead of `UUID()`.

## Dead Code

- [x] **24. ~~`ClipboardContent` struct/class unused on both platforms~~ — ALREADY FIXED**
  Both files deleted in prior commit.
- [x] **25. ~~`KeychainStore.removeData` never called~~ — ALREADY FIXED**
  Method removed in prior commit.
- [x] **26. ~~`ChunkAssembler.clear()` never called~~ — ALREADY FIXED**
  Method removed in prior commit.
- [ ] **27. `ChunkHeader.encoding` decoded but never validated or used**
  `macos/.../BLE/ChunkAssembler.swift:13,19` and `android/.../ble/ChunkReassembler.kt:6`
  Both platforms store the `encoding` field from chunk headers but always hardcode UTF-8 for decoding. Acknowledged: field is part of the protocol spec and kept for forward compatibility.
- [ ] **28. `tx_id` parsed but never used on either platform**
  Protocol spec requires `tx_id` in both metadata and chunk headers. Both platforms decode it and discard it. Acknowledged: kept for forward compatibility and protocol compliance.
- [ ] **29. Metadata `size` and `type` fields ignored on receipt**
  `macos/.../BLE/BLECentralManager.swift`, `android/.../ble/BleInboundStateMachine.kt`
  Both platforms extract only `hash` from the `Available` metadata. Acknowledged: kept for forward compatibility.

## Documentation Issues

- [x] **30. ~~Protocol spec contradicts implementation on encryption~~ — FIXED**
  `docs/protocol.md`
  Updated security model section to document HKDF key derivation with correct info labels.
- [x] **31. ~~README pairing instructions are wrong~~ — FIXED**
  `README.md`
  Updated to describe QR-code-based application-layer pairing flow.
- [x] **32. ~~README security claim is wrong~~ — FIXED**
  `README.md`
  Updated to describe AES-256-GCM encryption with HKDF-derived keys.
- [x] **33. ~~`project.md` says minSdk 31, `build.gradle.kts` has 35~~ — FIXED** (same as #5)

## Minor / Style

- [ ] **34. `security-crypto:1.1.0-alpha06` is an alpha dependency**
  `android/app/build.gradle.kts`
  Acknowledged: stable `1.0.0` has an incompatible API (`MasterKeys` vs `MasterKey.Builder`). The `1.1.0-alpha06` release is the de-facto standard — Google has not released a stable version with the `MasterKey.Builder` API. Keeping alpha.
- [x] **35. ~~`BluetoothAdapter.getDefaultAdapter()` deprecated since API 31~~ — FIXED**
  `android/.../ble/Advertiser.kt`
  Changed to `BluetoothManager.adapter` via context system service.
- [x] **36. ~~`isMinifyEnabled = false` for release builds~~ — FIXED**
  `android/app/build.gradle.kts`
  Enabled R8 minification for release builds.
- [ ] **37. `sha256Hex` duplicated between BLECentralManager and ClipboardMonitor**
  `macos/.../BLE/BLECentralManager.swift`, `macos/.../Clipboard/ClipboardMonitor.swift`
  Acknowledged: 2-line duplication; extracting to shared utility would add more complexity than it saves.
- [x] **38. ~~`findDevice(byTag:)` does keychain I/O + HKDF per device on every BLE advertisement~~ — FIXED**
  `macos/.../Pairing/PairingManager.swift`
  Added in-memory `tagCache` that is invalidated when devices change via `persist()`.
- [x] **39. ~~Duplicate `CCC_DESCRIPTOR_UUID` constant~~ — FIXED**
  `android/.../ble/GattServerManager.kt`, `android/.../ble/GattServerCallback.kt`
  Removed duplicate from `GattServerCallback`; now references `GattServerManager.CCC_DESCRIPTOR_UUID`.
- [x] **40. ~~No `onRequestPermissionsResult` handler~~ — ALREADY FIXED**
  `android/.../ui/MainActivity.kt`
  Handler exists and restarts service after permission result.
- [x] **41. ~~Stale `rm -rf ClipShareMac.app` in build script~~ — FIXED**
  `scripts/build-all.sh`
  Removed stale cleanup line.
