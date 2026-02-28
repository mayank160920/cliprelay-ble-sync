# Connection Loss Investigation

> Issue: BLE connection between Mac and Android dies after several hours,
> especially when the Mac laptop lid was closed in between.

## Root Causes Identified

### 1. **[HIGH] [FIXED] Mac timers are NOT restarted on wake — "zombie timer" bug**

**File**: `macos/.../BLE/BLECentralManager.swift` lines 119–162

`handleSystemWake()` calls `startKeepaliveTimer()`, `startScanCycleTimer()`,
and `startConnectionWatchdogIfNeeded()` — but all three methods have an
early-return guard:

```swift
guard keepaliveTimer == nil else { return }  // line 388
guard scanCycleTimer == nil else { return }  // line 444
guard connectionWatchdogTimer == nil else { return }  // line 334
```

The old timer references from before sleep are still non-nil, so **none of
these timers are recreated on wake**. The code relies on the pre-sleep Timer
objects resuming correctly after wake.

**Why this matters**: On macOS, `Timer` objects fire on the main RunLoop.
During deep sleep (lid closed for hours), the RunLoop is suspended. On wake,
timers whose fire dates have long passed will fire **once** as a catch-up,
then resume their interval. In most cases this works.

**But**: If CoreBluetooth's state cycles through `poweredOff` during wake,
`centralManagerDidUpdateState(.poweredOff)` calls `stopKeepaliveTimer()` etc.
(setting them to nil), and then `centralManagerDidUpdateState(.poweredOn)`
recreates them correctly. This is the **happy path**.

**The failure path**: If CoreBluetooth does NOT cycle its state (stays at
`poweredOn` throughout the sleep/wake), the timers from before sleep are the
only ones running. If macOS invalidates these Timer objects internally during
extended sleep (which can happen with deep sleep / Power Nap transitions),
the timers silently die. The variable still holds a reference (non-nil), so
the guard prevents recreation. **All keepalive probing, scan cycling, and
watchdog checks stop permanently.**

**Evidence**: This matches the user's report — connection works for hours,
then after closing the laptop lid and reopening, it never recovers. The
keepalive timer that would detect the dead link is itself dead.

**Fix**: In `handleSystemWake()`, explicitly stop then restart all timers:
```swift
stopConnectionWatchdog()
stopKeepaliveTimer()
stopScanCycleTimer()
startConnectionWatchdogIfNeeded()
startKeepaliveTimer()
startScanCycleTimer()
```

---

### 2. **[HIGH] `centralManagerDidUpdateState` clears `peripheralTokenMap` — reconnection data lost**

**File**: `macos/.../BLE/BLECentralManager.swift` lines 603–629

When CoreBluetooth's state transitions to anything other than `.poweredOn`
(which commonly happens during sleep/wake), the handler clears ALL maps:

```swift
knownPeripherals.removeAll()      // line 614
peripheralTokenMap.removeAll()    // line 618
```

This means after wake, the Mac has **no memory of which peripheral UUIDs map
to which pairing tokens**. It must wait for a fresh advertisement discovery,
extract the device tag, and re-match it against stored pairings.

Meanwhile, `handleSystemWake()` may have already fired and tried to reconnect
using `peripheralTokenMap` — but that data was nuked by the state callback.

The fresh-scan recovery path works, but adds 0–4 minutes of latency
(waiting for Android's advertisement cycle). Combined with issue #1 (dead
timers), the scan cycle that would trigger rediscovery may never fire.

**Fix**: Don't clear `peripheralTokenMap` on non-poweredOn state transitions.
CoreBluetooth invalidates peripheral objects, but the token mapping
(peripheral UUID → pairing token) is still useful when new peripheral
objects appear with the same UUIDs on the next poweredOn transition.

---

### 3. **[MEDIUM] [FIXED] No `willSleepNotification` handler — no pre-sleep cleanup**

**File**: `macos/.../BLE/BLECentralManager.swift`

The Mac only handles `NSWorkspace.didWakeNotification` but not
`NSWorkspace.willSleepNotification`. Without pre-sleep cleanup:

- Active BLE connections remain "open" from CoreBluetooth's perspective
- The BLE radio powers down, causing the link supervision timer on both
  sides to fire (typically 5–20 seconds)
- The Android side sees a disconnect via GATT callback
- On wake, CoreBluetooth may still think the connection is alive (stale
  connection handle)
- The `handleSystemWake` cancellation handles this, but doing cleanup
  before sleep would make the wake recovery cleaner and more reliable

**Fix**: Add a `willSleepNotification` handler that proactively disconnects
all peripherals and stops timers, so wake recovery starts from a clean state.

---

### 4. **[MEDIUM] Android GATT server has NO health check**

**Files**: `android/.../ble/GattServerManager.kt`, `android/.../service/ClipRelayService.kt`

The Advertiser has a health check (every 4 minutes) that cycles the
advertisement. But the GATT server (`BluetoothGattServer`) is **never
cycled or health-checked**.

The GATT server can become stale if:
- The Bluetooth adapter does an internal reset without triggering
  `ACTION_STATE_CHANGED`
- The BLE stack enters an error state
- Android OS memory pressure causes partial cleanup

When the GATT server is stale:
- The Mac discovers the peripheral via advertisement (advertiser was cycled)
- Connection succeeds at the link layer
- But service discovery fails or characteristics are unresponsive
- Mac's 15-second service discovery timeout disconnects
- Mac reconnects, same failure — creates a connect/disconnect loop

**Fix**: Cycle the GATT server alongside the advertisement in the health
check. Or at minimum, close and reopen the GATT server whenever the
advertiser is cycled.

---

### 5. **[MEDIUM] [FIXED] No persistent logging on Mac — can't diagnose past failures**

**File**: `macos/.../BLE/BLECentralManager.swift`

All Mac-side logging uses `print()` which goes to stdout only. This means:
- Logs are only visible if the app is launched from a terminal
- No log history survives between sessions
- System `log show` can't find any ClipRelay events
- Impossible to verify what happened during a connection loss

**Fix**: Switch from `print()` to `os_log` / `Logger` (from the `os`
framework). This writes to the unified logging system, which persists across
sessions and is searchable via `log show`.

---

### 6. **[LOW] Android `Handler.postDelayed` for health checks may drift during Doze**

**File**: `android/.../ble/Advertiser.kt` line 156

The advertiser health check uses `Handler.postDelayed()`. While foreground
services are generally exempt from Doze restrictions, the Handler message
delivery can still be delayed during screen-off idle periods on some OEMs.

If the health check is delayed and the advertisement was silently killed,
the phone may be invisible to the Mac for longer than the intended 4 minutes.

**Fix**: Consider using `AlarmManager.setExactAndAllowWhileIdle()` for the
health check, or request `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission.

---

### 7. **[LOW] No CBCentralManager state restoration**

**File**: `macos/.../BLE/BLECentralManager.swift` line 74

The `CBCentralManager` is created without a restoration identifier:
```swift
self.centralManager = CBCentralManager(delegate: self, queue: .main)
```

Without `CBCentralManagerOptionRestoreIdentifierKey`, if macOS terminates
the app during sleep (memory pressure), it won't be relaunched when a BLE
event occurs. The user would need to manually reopen the app.

This is low priority for a menu bar app but worth considering for reliability.

---

### 8. **[CRITICAL] [FIXED] CoreBluetooth connection slot leak — permanent "max connections" failure**

**File**: `macos/.../BLE/BLECentralManager.swift`

**Discovery**: Found via `os_log` analysis after deploying fix #5. Every wake
cycle showed:

```
didFailToConnect: Pixel 10 Pro XL error=The system has reached the maximum
number of connections for this client
```

This repeated hundreds of times per wake cycle, preventing any connection
recovery.

**Root cause**: When CoreBluetooth state cycles to `poweredOff` during sleep,
`centralManagerDidUpdateState` clears app-side state (`connectingPeerIDs`,
`knownPeripherals`) but does NOT call `cancelPeripheralConnection()` for
peripherals that had `connect()` queued. Those stale connection requests leak
inside CoreBluetooth's internal connection table.

On wake, `poweredOn` triggers scanning with `allowDuplicates: true`.
Discoveries fire every ~200ms. Each discovery calls
`connectToPairedPeerIfNeeded()` → `connect()` → immediate fail
(`connectionLimitReached`) → `scheduleReconnect()` → next discovery fires
before backoff completes → `connect()` again. This creates a tight
connect/fail storm that permanently exhausts CoreBluetooth's connection slots.

**Fix** (three parts):
1. **Pre-sleep cleanup**: Added `willSleepNotification` handler that cancels
   all connections before sleep (prevents stale slots).
2. **Cancel before clearing state**: In `centralManagerDidUpdateState(.poweredOff)`,
   call `cancelPeripheralConnection()` for all known/connected peripherals
   BEFORE clearing `knownPeripherals` and `connectedPeers`.
3. **Connection cooldown**: In `didFailToConnect`, detect
   `CBError.connectionLimitReached`, cancel ALL pending connections, enter a
   10-second cooldown, suppress new `connect()` calls during cooldown, then
   resume cleanly.

---

## Reproduction Conditions

1. Pair Mac and Android, verify clipboard sync works
2. Close Mac laptop lid
3. Wait 2+ hours
4. Open laptop lid
5. Try clipboard sync — connection appears dead

Alternative trigger: leave both devices idle for hours with no clipboard
activity (no data transfer to exercise the connection).

## Summary of Fixes (Priority Order)

| # | Severity | Fix | Status |
|---|----------|-----|--------|
| 8 | CRITICAL | Connection slot leak: pre-sleep cleanup + cancel before clear + cooldown | FIXED |
| 1 | HIGH | Stop/restart all timers in `handleSystemWake()` | FIXED |
| 2 | HIGH | Preserve `peripheralTokenMap` across BT state transitions | Open |
| 3 | MEDIUM | Add `willSleepNotification` handler | FIXED |
| 4 | MEDIUM | Add GATT server health check on Android | Open |
| 5 | MEDIUM | Switch Mac logging from `print()` to `os_log` | FIXED |
| 6 | LOW | Use AlarmManager for Android health checks | Open |
| 7 | LOW | Add CBCentralManager state restoration | Open |
