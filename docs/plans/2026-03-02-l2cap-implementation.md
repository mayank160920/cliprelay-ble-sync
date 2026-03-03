# L2CAP Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace ClipRelay's GATT-based chunked transfer protocol with L2CAP CoC, delivering a dramatically simpler and more reliable clipboard sync over BLE.

**Architecture:** Android acts as BLE peripheral (advertiser + L2CAP listener), Mac acts as BLE central (scanner + L2CAP initiator). A minimal GATT service exposes the L2CAP PSM. All clipboard data flows over a single bidirectional L2CAP byte stream using a 6-message protocol (HELLO, WELCOME, OFFER, ACCEPT, PAYLOAD, DONE).

**Tech Stack:** Swift 5.10 / CoreBluetooth (macOS 14+), Kotlin / Android BLE API (API 29+), AES-256-GCM encryption, HKDF-SHA256 key derivation.

**Design doc:** `docs/plans/2026-03-02-l2cap-redesign.md`

---

## Task Overview

1. Wire protocol codec + cross-platform test fixture (shared)
2. L2CAP session logic — platform-agnostic protocol handler (both platforms)
3. Android — L2CAP server + minimal GATT PSM characteristic
4. Android — integrate session into ClipRelayService
5. macOS — ConnectionManager (scan, connect, read PSM, open L2CAP)
6. macOS — integrate session into app (clipboard monitor, AppDelegate)
7. Remove old GATT transfer code (both platforms)
8. Hardware integration smoke test

---

### Task 1: Wire Protocol Codec + Test Fixture

Build the message codec (encode/decode length-prefixed messages) and a cross-platform golden fixture for interoperability testing.

**Files:**
- Create: `test-fixtures/protocol/l2cap/l2cap_fixture.json`
- Create: `android/app/src/main/java/com/cliprelay/protocol/MessageCodec.kt`
- Create: `android/app/src/test/java/com/cliprelay/protocol/MessageCodecTest.kt`
- Create: `android/app/src/test/java/com/cliprelay/protocol/L2capFixtureCompatibilityTest.kt`
- Create: `macos/ClipRelayMac/Sources/Protocol/MessageCodec.swift`
- Create: `macos/ClipRelayMac/Tests/ClipRelayTests/MessageCodecTests.swift`
- Create: `macos/ClipRelayMac/Tests/ClipRelayTests/L2capFixtureCompatibilityTests.swift`

**Step 1: Create the golden test fixture**

Generate a JSON fixture with pre-computed encoded messages for all 6 types. This fixture is the source of truth for cross-platform compatibility.

```json
{
  "fixture_id": "l2cap-v1",
  "description": "Golden fixture for L2CAP wire protocol",
  "messages": [
    {
      "type": "HELLO",
      "type_byte": "0x01",
      "payload_json": "{\"version\":1}",
      "encoded_hex": "<4-byte length><0x01><utf8 payload>"
    },
    {
      "type": "WELCOME",
      "type_byte": "0x02",
      "payload_json": "{\"version\":1}",
      "encoded_hex": "..."
    },
    {
      "type": "OFFER",
      "type_byte": "0x10",
      "payload_json": "{\"hash\":\"abc123...\",\"size\":42,\"type\":\"text/plain\"}",
      "encoded_hex": "..."
    },
    {
      "type": "ACCEPT",
      "type_byte": "0x11",
      "payload_json": "",
      "encoded_hex": "..."
    },
    {
      "type": "PAYLOAD",
      "type_byte": "0x12",
      "payload_hex": "<raw binary: nonce + ciphertext + tag>",
      "encoded_hex": "..."
    },
    {
      "type": "DONE",
      "type_byte": "0x13",
      "payload_json": "{\"hash\":\"abc123...\",\"ok\":true}",
      "encoded_hex": "..."
    }
  ],
  "negative_cases": [
    {"name": "unknown_type", "encoded_hex": "...", "expected_error": "unknown message type"},
    {"name": "truncated_header", "encoded_hex": "0001", "expected_error": "incomplete header"},
    {"name": "zero_length", "encoded_hex": "00000000", "expected_error": "empty message"}
  ]
}
```

Compute the `encoded_hex` values by hand or in a script: for each message, `message_length` = 1 (type byte) + payload byte count, encoded as uint32 big-endian, followed by the type byte, followed by the payload bytes.

**Step 2: Write the Android codec + tests**

`MessageCodec.kt`:
```kotlin
package com.cliprelay.protocol

import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

enum class MessageType(val byte: Byte) {
    HELLO(0x01),
    WELCOME(0x02),
    OFFER(0x10),
    ACCEPT(0x11),
    PAYLOAD(0x12),
    DONE(0x13);

    companion object {
        fun fromByte(b: Byte): MessageType =
            entries.firstOrNull { it.byte == b }
                ?: throw ProtocolException("Unknown message type: 0x${b.toUByte().toString(16)}")
    }
}

data class Message(val type: MessageType, val payload: ByteArray)

class ProtocolException(message: String) : Exception(message)

object MessageCodec {
    private const val HEADER_SIZE = 5 // 4 bytes length + 1 byte type
    private const val MAX_MESSAGE_SIZE = 200_000 // 200 KB safety limit

    fun encode(message: Message): ByteArray {
        val length = 1 + message.payload.size // type byte + payload
        val buf = ByteBuffer.allocate(4 + length).order(ByteOrder.BIG_ENDIAN)
        buf.putInt(length)
        buf.put(message.type.byte)
        buf.put(message.payload)
        return buf.array()
    }

    fun decode(input: InputStream): Message {
        val headerBuf = input.readNBytes(4)
        if (headerBuf.size < 4) throw ProtocolException("Incomplete header")

        val length = ByteBuffer.wrap(headerBuf).order(ByteOrder.BIG_ENDIAN).int
        if (length < 1) throw ProtocolException("Empty message")
        if (length > MAX_MESSAGE_SIZE) throw ProtocolException("Message too large: $length")

        val body = input.readNBytes(length)
        if (body.size < length) throw ProtocolException("Incomplete message body")

        val type = MessageType.fromByte(body[0])
        val payload = body.copyOfRange(1, body.size)
        return Message(type, payload)
    }

    fun write(output: OutputStream, message: Message) {
        output.write(encode(message))
        output.flush()
    }
}
```

Run: `cd android && ./gradlew testDebugUnitTest --tests "com.cliprelay.protocol.MessageCodecTest"`
Expected: All tests pass.

**Step 3: Write the macOS codec + tests**

`MessageCodec.swift`:
```swift
import Foundation

enum MessageType: UInt8 {
    case hello   = 0x01
    case welcome = 0x02
    case offer   = 0x10
    case accept  = 0x11
    case payload = 0x12
    case done    = 0x13
}

struct Message {
    let type: MessageType
    let payload: Data
}

enum ProtocolError: Error {
    case incompleteHeader
    case emptyMessage
    case messageTooLarge(Int)
    case incompleteBody
    case unknownType(UInt8)
}

enum MessageCodec {
    static let maxMessageSize = 200_000

    static func encode(_ message: Message) -> Data {
        let length = UInt32(1 + message.payload.count)
        var data = Data(capacity: 4 + Int(length))
        var beLenth = length.bigEndian
        data.append(Data(bytes: &beLenth, count: 4))
        data.append(message.type.rawValue)
        data.append(message.payload)
        return data
    }

    static func decode(from data: Data, offset: inout Int) throws -> Message {
        guard offset + 4 <= data.count else { throw ProtocolError.incompleteHeader }
        let length = Int(data.readUInt32BE(at: offset))
        offset += 4

        guard length >= 1 else { throw ProtocolError.emptyMessage }
        guard length <= maxMessageSize else { throw ProtocolError.messageTooLarge(length) }
        guard offset + length <= data.count else { throw ProtocolError.incompleteBody }

        let typeByte = data[offset]
        guard let type = MessageType(rawValue: typeByte) else {
            throw ProtocolError.unknownType(typeByte)
        }
        let payload = data.subdata(in: (offset + 1)..<(offset + length))
        offset += length
        return Message(type: type, payload: payload)
    }
}

extension Data {
    func readUInt32BE(at index: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { dest in
            self.copyBytes(to: dest, from: index..<(index + 4))
        }
        return UInt32(bigEndian: value)
    }
}
```

Run: `swift test --package-path macos/ClipRelayMac --filter MessageCodecTests`
Expected: All tests pass.

**Step 4: Write fixture compatibility tests (both platforms)**

Each platform loads `test-fixtures/protocol/l2cap/l2cap_fixture.json`, encodes each message, and asserts the encoded bytes match `encoded_hex`. Also decodes `encoded_hex` and asserts it produces the correct type and payload. Negative cases assert that decoding throws the expected error.

Run: `scripts/test-all.sh`
Expected: All tests pass on both platforms.

**Step 5: Commit**

```bash
git add test-fixtures/protocol/l2cap/ android/app/src/main/java/com/cliprelay/protocol/ \
    android/app/src/test/java/com/cliprelay/protocol/ \
    macos/ClipRelayMac/Sources/Protocol/ macos/ClipRelayMac/Tests/ClipRelayTests/
git commit -m "feat: add L2CAP wire protocol codec with cross-platform fixture"
```

---

### Task 2: Session Protocol Logic

Build the platform-agnostic session handler that reads/writes messages on a byte stream. This is the core protocol brain — testable with in-memory streams, no BLE required.

**Files:**
- Create: `android/app/src/main/java/com/cliprelay/protocol/Session.kt`
- Create: `android/app/src/test/java/com/cliprelay/protocol/SessionTest.kt`
- Create: `macos/ClipRelayMac/Sources/Protocol/Session.swift`
- Create: `macos/ClipRelayMac/Tests/ClipRelayTests/SessionTests.swift`

**Step 1: Define the Session interface and callback protocol**

The Session takes an input/output stream pair and a callback interface. It manages:
- Handshake: send/receive HELLO/WELCOME
- Outbound transfer: OFFER → wait ACCEPT → send PAYLOAD → wait DONE
- Inbound transfer: receive OFFER → send ACCEPT → receive PAYLOAD → verify → send DONE
- Timeouts: 5s for handshake, 30s for transfer completion
- Error handling: any error → close streams (caller handles reconnect)

Android `Session.kt`:
```kotlin
package com.cliprelay.protocol

import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

interface SessionCallback {
    fun onSessionReady()
    fun onClipboardReceived(plaintext: ByteArray, hash: String)
    fun onTransferComplete(hash: String)
    fun onSessionError(error: Exception)
}

class Session(
    private val input: InputStream,
    private val output: OutputStream,
    private val callback: SessionCallback
) {
    @Volatile private var closed = false

    fun performHandshake(asInitiator: Boolean) { /* send/receive HELLO/WELCOME */ }
    fun sendClipboard(encryptedBlob: ByteArray, hash: String) { /* OFFER/ACCEPT/PAYLOAD/DONE flow */ }
    fun listenForMessages() { /* blocking loop: read messages, dispatch to callback */ }
    fun close() { closed = true; input.close(); output.close() }
}
```

macOS `Session.swift` — same logic, using Foundation `InputStream`/`OutputStream`.

**Step 2: Write tests for the handshake flow**

Test with piped in-memory streams:
- Initiator sends HELLO, receives WELCOME → `onSessionReady()` called
- Responder receives HELLO, sends WELCOME → `onSessionReady()` called
- Handshake timeout (no WELCOME within 5s) → `onSessionError()` called
- Wrong message type during handshake → `onSessionError()` called
- Version mismatch → `onSessionError()` called

**Step 3: Write tests for clipboard transfer flow**

- Sender sends OFFER, gets ACCEPT, sends PAYLOAD, gets DONE → `onTransferComplete()` called
- Receiver gets OFFER, sends ACCEPT, gets PAYLOAD, verifies hash, sends DONE → `onClipboardReceived()` called
- Duplicate OFFER (receiver already has hash) → receiver sends DONE immediately, no PAYLOAD exchange
- Transfer timeout → `onSessionError()` called

**Step 4: Implement Session to make all tests pass**

Run: `scripts/test-all.sh`
Expected: All tests pass on both platforms.

**Step 5: Commit**

```bash
git add android/app/src/main/java/com/cliprelay/protocol/Session.kt \
    android/app/src/test/java/com/cliprelay/protocol/SessionTest.kt \
    macos/ClipRelayMac/Sources/Protocol/Session.swift \
    macos/ClipRelayMac/Tests/ClipRelayTests/SessionTests.swift
git commit -m "feat: add L2CAP session protocol handler with handshake and transfer logic"
```

---

### Task 3: Android — L2CAP Server + Minimal GATT PSM Characteristic

Replace the existing GATT server (multi-characteristic, chunked transfer) with a minimal GATT service that exposes one read-only characteristic: the L2CAP PSM value. Add the L2CAP server socket listener.

**Files:**
- Create: `android/app/src/main/java/com/cliprelay/ble/L2capServer.kt`
- Create: `android/app/src/main/java/com/cliprelay/ble/PsmGattServer.kt`
- Create: `android/app/src/test/java/com/cliprelay/ble/L2capServerTest.kt`
- Existing (will be modified later in Task 4): `android/app/src/main/java/com/cliprelay/service/ClipRelayService.kt`
- Existing (keep as-is for now): `android/app/src/main/java/com/cliprelay/ble/Advertiser.kt`

**Step 1: Write L2capServer**

```kotlin
package com.cliprelay.ble

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import java.io.IOException

interface L2capServerCallback {
    fun onClientConnected(socket: BluetoothSocket)
    fun onAcceptError(error: IOException)
}

class L2capServer(
    private val adapter: BluetoothAdapter,
    private val callback: L2capServerCallback
) {
    private var serverSocket: BluetoothServerSocket? = null
    private var acceptThread: Thread? = null

    fun start(): Int {
        // listenUsingInsecureL2capChannel() — insecure = no BLE-level encryption
        val socket = adapter.listenUsingInsecureL2capChannel()
        serverSocket = socket
        val psm = socket.psm

        acceptThread = Thread({
            while (!Thread.currentThread().isInterrupted) {
                try {
                    val client = socket.accept() // blocks
                    callback.onClientConnected(client)
                } catch (e: IOException) {
                    if (!Thread.currentThread().isInterrupted) {
                        callback.onAcceptError(e)
                    }
                    break
                }
            }
        }, "L2CAP-Accept")
        acceptThread?.start()

        return psm
    }

    fun stop() {
        acceptThread?.interrupt()
        try { serverSocket?.close() } catch (_: IOException) {}
        serverSocket = null
        acceptThread = null
    }
}
```

**Step 2: Write PsmGattServer**

A minimal GATT server with one service and one read-only characteristic containing the PSM value.

```kotlin
package com.cliprelay.ble

import android.bluetooth.*
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID

class PsmGattServer(
    private val bluetoothManager: BluetoothManager,
    private val psm: Int
) {
    companion object {
        val SERVICE_UUID = UUID.fromString("c10b0001-1234-5678-9abc-def012345678")
        val PSM_CHAR_UUID = UUID.fromString("c10b0010-1234-5678-9abc-def012345678")
    }

    private var gattServer: BluetoothGattServer? = null

    fun start() {
        val callback = object : BluetoothGattServerCallback() {
            override fun onCharacteristicReadRequest(
                device: BluetoothDevice, requestId: Int, offset: Int,
                characteristic: BluetoothGattCharacteristic
            ) {
                if (characteristic.uuid == PSM_CHAR_UUID) {
                    val psmBytes = ByteBuffer.allocate(2)
                        .order(ByteOrder.BIG_ENDIAN)
                        .putShort(psm.toShort())
                        .array()
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, psmBytes)
                }
            }
        }

        val server = bluetoothManager.openGattServer(/* context */, callback)
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val psmChar = BluetoothGattCharacteristic(
            PSM_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        service.addCharacteristic(psmChar)
        server.addService(service)
        gattServer = server
    }

    fun stop() {
        gattServer?.clearServices()
        gattServer?.close()
        gattServer = null
    }
}
```

**Step 3: Write tests**

L2capServer is hard to unit-test (requires real Bluetooth), so write a minimal test that validates the accept-loop lifecycle (start/stop without crashing). Real testing happens in Task 8 (hardware smoke test).

Run: `cd android && ./gradlew testDebugUnitTest`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add android/app/src/main/java/com/cliprelay/ble/L2capServer.kt \
    android/app/src/main/java/com/cliprelay/ble/PsmGattServer.kt \
    android/app/src/test/java/com/cliprelay/ble/L2capServerTest.kt
git commit -m "feat(android): add L2CAP server and minimal PSM GATT characteristic"
```

---

### Task 4: Android — Integrate Session into ClipRelayService

Wire up L2capServer + PsmGattServer + Session into the existing ClipRelayService. Replace the old GATT transfer logic with the L2CAP session.

**Files:**
- Modify: `android/app/src/main/java/com/cliprelay/service/ClipRelayService.kt`
- Modify: `android/app/src/main/java/com/cliprelay/ui/ShareReceiverActivity.kt` (outbound send path)
- Modify: `android/app/src/main/java/com/cliprelay/service/ClipboardWriter.kt` (inbound receive path)

**Step 1: Refactor ClipRelayService**

Replace the current BLE orchestration with:

```kotlin
// In ClipRelayService:
private var l2capServer: L2capServer? = null
private var psmGattServer: PsmGattServer? = null
private var activeSession: Session? = null

fun startBle() {
    // 1. Start L2CAP server, get PSM
    l2capServer = L2capServer(adapter, l2capCallback)
    val psm = l2capServer!!.start()

    // 2. Start minimal GATT server with PSM characteristic
    psmGattServer = PsmGattServer(bluetoothManager, psm)
    psmGattServer!!.start()

    // 3. Start advertising (reuse existing Advertiser — same service UUID + device tag)
    advertiser.start()
}

// L2CAP callback:
val l2capCallback = object : L2capServerCallback {
    override fun onClientConnected(socket: BluetoothSocket) {
        // Tear down previous session if any
        activeSession?.close()

        // Create new session on the L2CAP stream
        val session = Session(socket.inputStream, socket.outputStream, sessionCallback)
        activeSession = session

        executor.execute {
            session.performHandshake(asInitiator = false) // Android = responder
            session.listenForMessages() // blocking loop
        }
    }
}

// Session callback:
val sessionCallback = object : SessionCallback {
    override fun onClipboardReceived(plaintext: ByteArray, hash: String) {
        clipboardWriter.write(String(plaintext, Charsets.UTF_8))
    }
    override fun onSessionError(error: Exception) {
        activeSession?.close()
        activeSession = null
        // L2CAP server is still listening — next connection will create a new session
    }
}
```

**Step 2: Update ShareReceiverActivity outbound path**

When Android user shares text → forward to ClipRelayService → if activeSession exists, call `session.sendClipboard(encryptedBlob, hash)`.

**Step 3: Test manually (build + install on device)**

Run: `scripts/build-all.sh --android-only`
Then: `adb install -r dist/cliprelay-debug.apk`

At this point Android can accept L2CAP connections but there's no Mac side yet to connect. Visual verification: app starts, advertises, no crashes.

**Step 4: Commit**

```bash
git add android/app/src/main/java/com/cliprelay/service/ClipRelayService.kt \
    android/app/src/main/java/com/cliprelay/ui/ShareReceiverActivity.kt \
    android/app/src/main/java/com/cliprelay/service/ClipboardWriter.kt
git commit -m "feat(android): wire L2CAP session into ClipRelayService"
```

---

### Task 5: macOS — ConnectionManager

Build the new ConnectionManager that replaces BLECentralManager. This is the only component that talks to CoreBluetooth. It handles: scan → match tag → GATT connect → read PSM → open L2CAP channel → hand off stream to Session.

**Files:**
- Create: `macos/ClipRelayMac/Sources/BLE/ConnectionManager.swift`
- Create: `macos/ClipRelayMac/Tests/ClipRelayTests/ConnectionManagerTests.swift`

**Step 1: Write ConnectionManager**

```swift
import CoreBluetooth
import Foundation

protocol ConnectionManagerDelegate: AnyObject {
    func connectionManager(_ manager: ConnectionManager, didEstablishSession session: Session, for token: String)
    func connectionManager(_ manager: ConnectionManager, didDisconnectFor token: String)
}

class ConnectionManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // State machine
    enum State {
        case idle
        case scanning
        case connecting(CBPeripheral)
        case readingPSM(CBPeripheral)
        case openingL2CAP(CBPeripheral, UInt16)
        case connected(CBPeripheral, CBL2CAPChannel)
    }

    weak var delegate: ConnectionManagerDelegate?
    private var centralManager: CBCentralManager!
    private var state: State = .idle
    private var reconnectDelay: TimeInterval = 1.0
    private var reconnectTimer: Timer?

    // Pairing data
    private let pairedDevices: () -> [(token: String, tag: Data)]

    // PSM characteristic UUID (must match Android PsmGattServer)
    static let serviceUUID = CBUUID(string: "c10b0001-1234-5678-9abc-def012345678")
    static let psmCharUUID = CBUUID(string: "c10b0010-1234-5678-9abc-def012345678")

    init(pairedDevices: @escaping () -> [(token: String, tag: Data)]) {
        self.pairedDevices = pairedDevices
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            reconnectDelay = 1.0
            startScanning()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        // Extract device tag from manufacturer data, match against paired tokens
        guard let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return }
        let tag = extractDeviceTag(from: mfgData)
        guard let matched = pairedDevices().first(where: { $0.tag == tag }) else { return }

        // Stop scanning, connect
        central.stopScan()
        state = .connecting(peripheral)
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Discover the service to read PSM
        state = .readingPSM(peripheral)
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Clean up, schedule reconnect with backoff
        state = .idle
        scheduleReconnect()
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([Self.psmCharUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBGattService, error: Error?) {
        guard let char = service.characteristics?.first(where: { $0.uuid == Self.psmCharUUID }) else {
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.readValue(for: char)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.psmCharUUID,
              let data = characteristic.value, data.count == 2 else {
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        let psm = data.readUInt16BE(at: 0)
        state = .openingL2CAP(peripheral, psm)
        peripheral.openL2CAPChannel(CBL2CAPPSM(psm))
    }

    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        guard let channel = channel, error == nil else {
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        // Keep strong reference to channel (critical — CoreBluetooth deallocates otherwise)
        state = .connected(peripheral, channel)
        reconnectDelay = 1.0

        // Schedule streams on main RunLoop (avoids threading pitfalls)
        channel.inputStream.schedule(in: .main, forMode: .common)
        channel.outputStream.schedule(in: .main, forMode: .common)
        channel.inputStream.open()
        channel.outputStream.open()

        // Create session and hand off to delegate
        let session = Session(input: channel.inputStream, output: channel.outputStream, ...)
        delegate?.connectionManager(self, didEstablishSession: session, for: matchedToken)
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectDelay, repeats: false) { [weak self] _ in
            self?.startScanning()
        }
        reconnectDelay = min(reconnectDelay * 2, 30.0)
    }

    private func startScanning() {
        state = .scanning
        centralManager.scanForPeripherals(withServices: [Self.serviceUUID])
    }
}
```

**Step 2: Write tests**

ConnectionManager's CoreBluetooth interactions can't be unit-tested easily, but test:
- State machine transitions (idle → scanning → connecting → etc.)
- Reconnect backoff calculation (1, 2, 4, 8, 16, 30, 30, ...)
- Device tag matching logic

Run: `swift test --package-path macos/ClipRelayMac --filter ConnectionManagerTests`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add macos/ClipRelayMac/Sources/BLE/ConnectionManager.swift \
    macos/ClipRelayMac/Tests/ClipRelayTests/ConnectionManagerTests.swift
git commit -m "feat(macos): add L2CAP ConnectionManager with scan/connect/PSM/channel lifecycle"
```

---

### Task 6: macOS — Integrate Session into App

Wire ConnectionManager + Session into AppDelegate. Replace old BLECentralManager usage. Connect clipboard monitor to outbound transfer path.

**Files:**
- Modify: `macos/ClipRelayMac/Sources/App/AppDelegate.swift`
- Modify: `macos/ClipRelayMac/Sources/App/StatusBarController.swift` (connection status display)
- Modify: `macos/ClipRelayMac/Sources/Clipboard/ClipboardMonitor.swift` (outbound trigger)

**Step 1: Replace BLECentralManager with ConnectionManager in AppDelegate**

```swift
// In AppDelegate:
private var connectionManager: ConnectionManager!
private var activeSession: Session?
private var pendingClipboardPayload: (encrypted: Data, hash: String)?

func applicationDidFinishLaunching(_ notification: Notification) {
    // ...existing setup...
    connectionManager = ConnectionManager(pairedDevices: { [weak self] in
        self?.pairingManager.loadDevices().compactMap { device in
            guard let tag = self?.pairingManager.deviceTag(for: device.token) else { return nil }
            return (token: device.token, tag: tag)
        } ?? []
    })
    connectionManager.delegate = self
    clipboardMonitor.delegate = self
}
```

**Step 2: Implement ConnectionManagerDelegate**

```swift
extension AppDelegate: ConnectionManagerDelegate {
    func connectionManager(_ manager: ConnectionManager, didEstablishSession session: Session, for token: String) {
        activeSession = session

        // Handshake (Mac = initiator)
        session.performHandshake(asInitiator: true)

        // If there's a pending clipboard payload from before reconnect, send it
        if let pending = pendingClipboardPayload {
            session.sendClipboard(encryptedBlob: pending.encrypted, hash: pending.hash)
        }

        // Start listening for inbound messages
        session.listenForMessages()
    }

    func connectionManager(_ manager: ConnectionManager, didDisconnectFor token: String) {
        activeSession = nil
        statusBarController.updateConnectionState(.disconnected)
    }
}
```

**Step 3: Wire clipboard monitor to session**

```swift
extension AppDelegate: ClipboardMonitorDelegate {
    func clipboardMonitor(_ monitor: ClipboardMonitor, didDetectNewContent text: String) {
        guard let key = pairingManager.encryptionKey(for: activeToken) else { return }
        let plainData = text.data(using: .utf8)!
        let encrypted = try! E2ECrypto.seal(plainData, key: key)
        let hash = SHA256.hash(data: encrypted).hex

        if let session = activeSession {
            session.sendClipboard(encryptedBlob: encrypted, hash: hash)
        }
        // Retain for retry after reconnect
        pendingClipboardPayload = (encrypted: encrypted, hash: hash)
    }
}
```

**Step 4: Build and verify**

Run: `scripts/build-all.sh --mac-only`
Expected: Builds without errors.

**Step 5: Commit**

```bash
git add macos/ClipRelayMac/Sources/App/AppDelegate.swift \
    macos/ClipRelayMac/Sources/App/StatusBarController.swift \
    macos/ClipRelayMac/Sources/Clipboard/ClipboardMonitor.swift
git commit -m "feat(macos): wire L2CAP session into AppDelegate and clipboard monitor"
```

---

### Task 7: Remove Old GATT Transfer Code

Delete the old GATT-based chunking, reassembly, and multi-characteristic transfer code. Keep Advertiser (still needed), E2ECrypto (still needed), PairingStore/PairingManager (still needed).

**Files:**
- Delete: `android/app/src/main/java/com/cliprelay/ble/ChunkTransfer.kt`
- Delete: `android/app/src/main/java/com/cliprelay/ble/ChunkReassembler.kt`
- Delete: `android/app/src/main/java/com/cliprelay/ble/BleInboundStateMachine.kt`
- Delete: `android/app/src/main/java/com/cliprelay/ble/BleConnectionStateMachine.kt`
- Delete: `android/app/src/main/java/com/cliprelay/ble/GattServerCallback.kt`
- Delete: `android/app/src/main/java/com/cliprelay/ble/GattServerManager.kt`
- Delete: `android/app/src/test/java/com/cliprelay/ble/ChunkTransferTest.kt`
- Delete: `android/app/src/test/java/com/cliprelay/ble/ChunkReassemblerTest.kt`
- Delete: `android/app/src/test/java/com/cliprelay/ble/BleInboundStateMachineTest.kt`
- Delete: `android/app/src/test/java/com/cliprelay/ble/BleConnectionStateMachineTest.kt`
- Delete: `macos/ClipRelayMac/Sources/BLE/BLECentralManager.swift`
- Delete: `macos/ClipRelayMac/Sources/BLE/ChunkAssembler.swift`
- Delete: `macos/ClipRelayMac/Tests/ClipRelayTests/ChunkAssemblerTests.swift`
- Delete: `macos/ClipRelayMac/Tests/ClipRelayTests/BLEConnectionStateTests.swift`
- Keep: `test-fixtures/protocol/v1/` (historical reference)

**Step 1: Delete files**

```bash
git rm android/app/src/main/java/com/cliprelay/ble/ChunkTransfer.kt \
    android/app/src/main/java/com/cliprelay/ble/ChunkReassembler.kt \
    android/app/src/main/java/com/cliprelay/ble/BleInboundStateMachine.kt \
    android/app/src/main/java/com/cliprelay/ble/BleConnectionStateMachine.kt \
    android/app/src/main/java/com/cliprelay/ble/GattServerCallback.kt \
    android/app/src/main/java/com/cliprelay/ble/GattServerManager.kt \
    android/app/src/test/java/com/cliprelay/ble/ChunkTransferTest.kt \
    android/app/src/test/java/com/cliprelay/ble/ChunkReassemblerTest.kt \
    android/app/src/test/java/com/cliprelay/ble/BleInboundStateMachineTest.kt \
    android/app/src/test/java/com/cliprelay/ble/BleConnectionStateMachineTest.kt \
    macos/ClipRelayMac/Sources/BLE/BLECentralManager.swift \
    macos/ClipRelayMac/Sources/BLE/ChunkAssembler.swift \
    macos/ClipRelayMac/Tests/ClipRelayTests/ChunkAssemblerTests.swift \
    macos/ClipRelayMac/Tests/ClipRelayTests/BLEConnectionStateTests.swift
```

**Step 2: Fix any remaining references**

Grep for references to deleted classes (e.g., `BLECentralManager`, `GattServerManager`, `ChunkAssembler`) in remaining files. Update imports, remove dead code paths.

**Step 3: Build + test both platforms**

Run: `scripts/build-all.sh && scripts/test-all.sh`
Expected: Clean build, all remaining tests pass.

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor: remove old GATT chunked transfer code"
```

---

### Task 8: Hardware Integration Smoke Test

End-to-end test with real devices. This validates the entire L2CAP flow: advertisement → discovery → GATT connect → PSM read → L2CAP channel → HELLO/WELCOME → clipboard transfer.

**Files:**
- Modify: `scripts/hardware-smoke-test.sh` (update for L2CAP protocol)

**Step 1: Build both apps**

Run: `scripts/build-all.sh`
Expected: Both platforms build cleanly.

**Step 2: Deploy to devices**

```bash
# Mac
pkill -f ClipRelay; open dist/ClipRelay.app

# Android (if device connected)
adb install -r dist/cliprelay-debug.apk
adb shell am force-stop com.cliprelay
adb shell am start -n com.cliprelay/.ui.MainActivity
```

**Step 3: Test pairing**

- Mac shows QR code
- Android scans QR code
- Both apps confirm pairing

**Step 4: Test Mac → Android clipboard sync**

- Copy text on Mac
- Verify it appears on Android within 5 seconds
- Repeat with longer text (~10 KB)

**Step 5: Test Android → Mac clipboard sync**

- Share text from Android via Share sheet → ClipRelay
- Verify it appears on Mac clipboard within 5 seconds

**Step 6: Test reconnection**

- Toggle Bluetooth off on Android, wait 5 seconds, toggle back on
- Verify Mac reconnects and clipboard sync resumes
- Close Mac lid, reopen
- Verify reconnects within 10 seconds

**Step 7: Test transfer-in-flight recovery**

- Copy text on Mac
- Before transfer completes, toggle Android Bluetooth off
- Toggle back on
- Verify the text arrives after reconnect

**Step 8: Run automated hardware smoke test if available**

Run: `scripts/hardware-smoke-test.sh`

**Step 9: Commit any smoke test script updates**

```bash
git add scripts/
git commit -m "test(hardware): update smoke tests for L2CAP protocol"
```
