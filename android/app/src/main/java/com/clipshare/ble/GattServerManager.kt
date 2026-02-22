package com.clipshare.ble

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.content.Context
import android.os.Build
import android.util.Log
import java.util.UUID
import java.util.concurrent.TimeUnit

class GattServerManager(
    private val context: Context,
    private val callback: GattServerCallback
) {
    companion object {
        private const val TAG = "GattServerManager"
        val SERVICE_UUID: UUID = UUID.fromString("c10b0001-1234-5678-9abc-def012345678")
        val AVAILABLE_UUID: UUID = UUID.fromString("c10b0002-1234-5678-9abc-def012345678")
        val DATA_UUID: UUID = UUID.fromString("c10b0003-1234-5678-9abc-def012345678")
        private val CCC_DESCRIPTOR_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    private var server: BluetoothGattServer? = null
    private var availableCharacteristic: BluetoothGattCharacteristic? = null
    private var dataCharacteristic: BluetoothGattCharacteristic? = null

    fun start() {
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        server = bluetoothManager.openGattServer(context, callback)
        callback.server = server

        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)

        val available = BluetoothGattCharacteristic(
            AVAILABLE_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or
                BluetoothGattCharacteristic.PROPERTY_NOTIFY or
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_READ or
                BluetoothGattCharacteristic.PERMISSION_WRITE
        )

        val data = BluetoothGattCharacteristic(
            DATA_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or
                BluetoothGattCharacteristic.PROPERTY_NOTIFY or
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_READ or
                BluetoothGattCharacteristic.PERMISSION_WRITE
        )

        available.addDescriptor(
            BluetoothGattDescriptor(
                CCC_DESCRIPTOR_UUID,
                BluetoothGattDescriptor.PERMISSION_READ or
                    BluetoothGattDescriptor.PERMISSION_WRITE
            )
        )

        data.addDescriptor(
            BluetoothGattDescriptor(
                CCC_DESCRIPTOR_UUID,
                BluetoothGattDescriptor.PERMISSION_READ or
                    BluetoothGattDescriptor.PERMISSION_WRITE
            )
        )

        availableCharacteristic = available
        dataCharacteristic = data

        service.addCharacteristic(available)
        service.addCharacteristic(data)
        server?.addService(service)
    }

    fun hasConnectedCentral(): Boolean {
        return callback.connectedDevicesSnapshot().isNotEmpty()
    }

    fun publishClipboardFrames(
        availablePayload: ByteArray,
        dataFrames: List<ByteArray>
    ): Boolean {
        val server = server ?: return false
        val available = availableCharacteristic ?: return false
        val data = dataCharacteristic ?: return false
        val connectedDevices = callback.connectedDevicesSnapshot()
        if (connectedDevices.isEmpty()) {
            return false
        }

        // Drain any stale permits before starting
        callback.notificationSent.drainPermits()

        connectedDevices.forEach { device ->
            notifyCharacteristicChanged(server, device, available, availablePayload)
        }

        dataFrames.forEach { frame ->
            connectedDevices.forEach { device ->
                notifyCharacteristicChanged(server, device, data, frame)
                // Wait for onNotificationSent before sending the next chunk;
                // timeout prevents hanging if the callback never fires.
                if (!callback.notificationSent.tryAcquire(500, TimeUnit.MILLISECONDS)) {
                    Log.w(TAG, "onNotificationSent timeout — BLE congestion or disconnected peer")
                }
            }
        }

        return true
    }

    fun stop() {
        server?.close()
        callback.server = null
        callback.clearConnectedDevices()
        server = null
        availableCharacteristic = null
        dataCharacteristic = null
    }

    private fun notifyCharacteristicChanged(
        server: BluetoothGattServer,
        device: BluetoothDevice,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            server.notifyCharacteristicChanged(device, characteristic, false, value)
            return
        }

        @Suppress("DEPRECATION")
        run {
            characteristic.value = value
            server.notifyCharacteristicChanged(device, characteristic, false)
        }
    }
}
