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

- [ ] **High:** Incoming transfer state on Android is global, but GATT allows multiple connected centrals; frames/hashes can mix across peers.
  - `android/app/src/main/java/com/clipshare/service/ClipShareService.kt`
  - `android/app/src/main/java/com/clipshare/ble/GattServerCallback.kt`
  - `android/app/src/main/java/com/clipshare/ble/GattServerManager.kt`

- [ ] **High:** macOS sends chunk frames on timers without CoreBluetooth flow control (`canSendWriteWithoutResponse` / readiness callback), so larger payloads can be dropped under load.
  - `macos/ClipShareMac/Sources/BLE/BLECentralManager.swift`

- [ ] **Medium:** Outbound Android publish blocks a single shared executor via `Thread.sleep`, which also handles inbound parsing/decrypt work; this can delay or starve receive handling during long sends.
  - `android/app/src/main/java/com/clipshare/service/ClipShareService.kt`
  - `android/app/src/main/java/com/clipshare/ble/GattServerManager.kt`

- [ ] **Medium:** Production logging in mac BLE includes detailed manufacturer/tag diagnostics and high-frequency event logs, increasing noise and leaking pairing metadata into logs.
  - `macos/ClipShareMac/Sources/BLE/BLECentralManager.swift`

- [ ] **Medium:** Protocol/config values are duplicated across platforms and docs, and drift already exists (security model + min SDK mismatch).
  - `README.md`
  - `docs/protocol.md`
  - `android/app/src/main/java/com/clipshare/crypto/E2ECrypto.kt`
  - `macos/ClipShareMac/Sources/Crypto/E2ECrypto.swift`
  - `project.md`
  - `android/app/build.gradle.kts`

- [ ] **Low:** Remove dead code / stale artifacts.
  - `android/app/src/main/java/com/clipshare/models/ClipboardContent.kt`
  - `macos/ClipShareMac/Sources/Models/ClipboardContent.swift`
  - `android/app/src/main/res/values/strings.xml`
  - `macos/ClipShareMac/Sources/Security/KeychainStore.swift`
  - `macos/ClipShareMac/Sources/BLE/ChunkAssembler.swift`
  - `android/app/src/main/java/com/clipshare/service/ClipShareService.kt`

- [ ] **Low:** Reduce unnecessary complexity in `BLECentralManager` (scan/connect/reconnect/chunking/crypto/dispatch/UI notifications).
  - `macos/ClipShareMac/Sources/BLE/BLECentralManager.swift`

## Testing / Quality To-Do

- [ ] Add and maintain automated regression coverage for protocol and reconnect behavior.

## Structure / Idiomaticity To-Do

- [ ] **Medium:** Split large orchestrators (`ClipShareService`, `BLECentralManager`) into smaller responsibilities.
  - `android/app/src/main/java/com/clipshare/service/ClipShareService.kt`
  - `macos/ClipShareMac/Sources/BLE/BLECentralManager.swift`

- [ ] **Medium:** Reduce protocol/chunking duplication across platforms to lower drift risk.
  - `android/app/src/main/java/com/clipshare/ble/ChunkTransfer.kt`
  - `android/app/src/main/java/com/clipshare/ble/ChunkReassembler.kt`
  - `macos/ClipShareMac/Sources/BLE/ChunkAssembler.swift`
  - `macos/ClipShareMac/Sources/BLE/BLECentralManager.swift`

- [ ] **Medium:** Improve concurrency/control-flow scalability (avoid blocking Android worker thread and centralizing too much work on the macOS main queue).
  - `android/app/src/main/java/com/clipshare/ble/GattServerManager.kt`
  - `android/app/src/main/java/com/clipshare/service/ClipShareService.kt`
  - `macos/ClipShareMac/Sources/BLE/BLECentralManager.swift`

- [ ] **Low:** Improve tooling maturity and doc alignment (CI/lint and protocol/security docs).
  - `README.md`
  - `docs/protocol.md`
  - `android/app/src/main/java/com/clipshare/crypto/E2ECrypto.kt`
  - `macos/ClipShareMac/Sources/Crypto/E2ECrypto.swift`
