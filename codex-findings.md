# Codebase Critique To-Do

## Workflow Rule (required)

For every completed task in this file:
1. Change `- [ ]` to `- [x]`.
2. Strike through the task text with `~~...~~`.
3. Keep the reference paths under the task for traceability.

## Findings To-Do

- [x] ~~**High:** Android can start BLE work before runtime permissions are granted, which risks `SecurityException` and service crash paths.~~
  - `android/app/src/main/java/com/clipshare/ui/MainActivity.kt`
  - `android/app/src/main/java/com/clipshare/service/ClipShareService.kt`
  - `android/app/src/main/java/com/clipshare/service/BootCompletedReceiver.kt`

- [x] ~~**High:** Incoming transfer state on Android is global, but GATT allows multiple connected centrals; frames/hashes can mix across peers.~~
  - `android/app/src/main/java/com/clipshare/service/ClipShareService.kt`
  - `android/app/src/main/java/com/clipshare/ble/GattServerCallback.kt`
  - `android/app/src/main/java/com/clipshare/ble/GattServerManager.kt`
  - Fixed by `BleInboundStateMachine` which maintains per-device slots with separate reassembler and metadata hash state.

- [x] ~~**High:** macOS sends chunk frames on timers without CoreBluetooth flow control (`canSendWriteWithoutResponse` / readiness callback), so larger payloads can be dropped under load.~~
  - `macos/ClipShareMac/Sources/BLE/BLECentralManager.swift`
  - Replaced timer-based delays with `peripheralIsReady(toSendWriteWithoutResponse:)` callback-driven flow control.

- [x] ~~**Medium:** Outbound Android publish blocks a single shared executor via `Thread.sleep`, which also handles inbound parsing/decrypt work; this can delay or starve receive handling during long sends.~~
  - `android/app/src/main/java/com/clipshare/service/ClipShareService.kt`
  - `android/app/src/main/java/com/clipshare/ble/GattServerManager.kt`
  - Fixed: replaced `Thread.sleep` with `Semaphore`/`onNotificationSent` for proper BLE flow control.

- [ ] **Medium:** Production logging in mac BLE includes detailed manufacturer/tag diagnostics and high-frequency event logs, increasing noise and leaking pairing metadata into logs.
  - `macos/ClipShareMac/Sources/BLE/BLECentralManager.swift`
  - Acknowledged: diagnostic logging is valuable during active development and helps debug BLE issues in the field.

- [x] ~~**Medium:** Protocol/config values are duplicated across platforms and docs, and drift already exists (security model + min SDK mismatch).~~
  - `README.md`
  - `docs/protocol.md`
  - `android/app/src/main/java/com/clipshare/crypto/E2ECrypto.kt`
  - `macos/ClipShareMac/Sources/Crypto/E2ECrypto.swift`
  - `project.md`
  - `android/app/build.gradle.kts`
  - Fixed: updated protocol.md and README.md to accurately reflect HKDF key derivation and AES-256-GCM encryption.

- [x] ~~**Low:** Remove dead code / stale artifacts.~~
  - `android/app/src/main/java/com/clipshare/models/ClipboardContent.kt` (removed)
  - `macos/ClipShareMac/Sources/Models/ClipboardContent.swift` (removed)
  - `macos/ClipShareMac/Sources/Security/KeychainStore.swift` (`removeData` removed)
  - `macos/ClipShareMac/Sources/BLE/ChunkAssembler.swift` (`clear` removed)

- [ ] **Low:** Reduce unnecessary complexity in `BLECentralManager` (scan/connect/reconnect/chunking/crypto/dispatch/UI notifications).
  - `macos/ClipShareMac/Sources/BLE/BLECentralManager.swift`
  - Acknowledged: architectural refactoring deferred; flow control improvement reduces some complexity.

## Testing / Quality To-Do

- [x] ~~Add and maintain automated regression coverage for protocol and reconnect behavior.~~
  - `android/app/src/test/java/com/clipshare/contract/ProtocolFixtureCompatibilityTest.kt`
  - `macos/ClipShareMac/Tests/GreenPasteTests/ProtocolFixtureCompatibilityTests.swift`
  - `scripts/test-all.sh`
  - `scripts/hardware-smoke-test.sh`

## Structure / Idiomaticity To-Do

- [ ] **Medium:** Split large orchestrators (`ClipShareService`, `BLECentralManager`) into smaller responsibilities.
  - `android/app/src/main/java/com/clipshare/service/ClipShareService.kt`
  - `macos/ClipShareMac/Sources/BLE/BLECentralManager.swift`
  - Acknowledged: architectural refactoring deferred to a future iteration.

- [ ] **Medium:** Reduce protocol/chunking duplication across platforms to lower drift risk.
  - `android/app/src/main/java/com/clipshare/ble/ChunkTransfer.kt`
  - `android/app/src/main/java/com/clipshare/ble/ChunkReassembler.kt`
  - `macos/ClipShareMac/Sources/BLE/ChunkAssembler.swift`
  - `macos/ClipShareMac/Sources/BLE/BLECentralManager.swift`
  - Acknowledged: cross-platform code sharing deferred.

- [ ] **Medium:** Improve concurrency/control-flow scalability (avoid blocking Android worker thread and centralizing too much work on the macOS main queue).
  - `android/app/src/main/java/com/clipshare/ble/GattServerManager.kt`
  - `android/app/src/main/java/com/clipshare/service/ClipShareService.kt`
  - `macos/ClipShareMac/Sources/BLE/BLECentralManager.swift`
  - Partially addressed: Android uses Semaphore-based flow control; macOS uses callback-driven flow control.

- [ ] **Low:** Improve tooling maturity and doc alignment (CI/lint and protocol/security docs).
  - `README.md`
  - `docs/protocol.md`
  - `android/app/src/main/java/com/clipshare/crypto/E2ECrypto.kt`
  - `macos/ClipShareMac/Sources/Crypto/E2ECrypto.swift`
  - Partially addressed: protocol.md and README.md updated. CI/lint deferred.
