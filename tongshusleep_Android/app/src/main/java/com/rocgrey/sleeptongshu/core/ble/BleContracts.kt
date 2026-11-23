package com.rocgrey.sleeptongshu.core.ble

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.rocgrey.sleeptongshu.core.data.WearableVitalEntity
import java.util.ArrayDeque
import java.util.UUID
import kotlin.math.pow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** 手环/戒指通道状态。 */
data class BandStatus(
    val connected: Boolean = false,
    val message: String = "",
)

/** 记住的设备（扫描结果与后续重连共用）。 */
data class RememberedDevice(
    val id: String,
    val name: String,
    val address: String,
    val kind: String = "ble",
    val lastSeenAt: Long = 0L,
)

/**
 * 可穿戴数据通道抽象（对应 iOS BandService）。
 * 本轮仅做架构预留，厂商通道全部未接入。
 */
interface BandChannel {
    val id: String
    val name: String
    val status: StateFlow<BandStatus>

    suspend fun start()

    suspend fun stop()

    /** 预留连接接口：厂商 SDK 接入后实现。 */
    suspend fun connect(device: RememberedDevice) {}
}

/**
 * 厂商通道占位实现：isAvailable 恒为 false，
 * 对应 iOS 端 Veepoo framework / IVSleep.a 等闭源依赖。
 */
abstract class VendorSdkPlaceholderChannel(
    override val id: String,
    override val name: String,
    iosCounterpart: String,
) : BandChannel {

    /** 厂商 Android SDK 未接入，通道不可用。 */
    val isAvailable: Boolean = false

    private val _status = MutableStateFlow(
        BandStatus(false, "需要厂商 Android SDK，当前版本未接入（对应 iOS $iosCounterpart）"),
    )
    override val status: StateFlow<BandStatus> = _status.asStateFlow()

    override suspend fun start() {
        // 占位：无厂商 SDK，不做任何事
    }

    override suspend fun stop() {
        // 占位：无厂商 SDK，不做任何事
    }

    override suspend fun connect(device: RememberedDevice) {
        // 占位：等待厂商 SDK 接入
    }
}

/** Veepoo 戒指（iOS 端对应 Veepoo framework）。 */
class VeepooChannel : VendorSdkPlaceholderChannel("veepoo", "Veepoo 戒指", "Veepoo framework")

/** Iwown 探测通道（iOS 端对应 IVSleep 探测依赖）。 */
class IwownProbeChannel : VendorSdkPlaceholderChannel("iwown_probe", "Iwown 探测", "IVSleep 探测通道")

/** 小米手环加密通道。 */
class StBandChannel : VendorSdkPlaceholderChannel("st_band", "小米手环", "小米手环 SDK")

/** 加密手环通道。 */
class EncryptedBandChannel : VendorSdkPlaceholderChannel("encrypted_band", "加密手环", "加密手环固件协议")

/** BIO 本地睡眠算法（iOS 端对应 IVSleep.a）。 */
class BioLocalSleepCalculator : VendorSdkPlaceholderChannel("bio_local", "BIO 本机睡眠算法", "IVSleep.a")

/**
 * 标准 GATT 体征客户端（无厂商 SDK 依赖）：
 * - 电量 180F/2A19、设备型号 180A/2A24、心率 180D/2A37、
 *   血压 1810/2A35、PLX 血氧点测 2A5E / 连续 2A5F；
 * - 扫描用 BluetoothLeScanner；
 * - 读数写入 WearableVitalDao（id=device|kind|time|origin 去重）。
 *
 * 注意：Android 12+ 需要运行时申请 BLUETOOTH_SCAN / BLUETOOTH_CONNECT（UI 层负责）。
 */
class GattVitalsClient(
    private val context: Context,
    private val onVital: (WearableVitalEntity) -> Unit = {},
) {

    companion object {
        val SERVICE_BATTERY: UUID = UUID.fromString("0000180f-0000-1000-8000-00805f9b34fb")
        val CHAR_BATTERY_LEVEL: UUID = UUID.fromString("00002a19-0000-1000-8000-00805f9b34fb")
        val SERVICE_DEVICE_INFORMATION: UUID = UUID.fromString("0000180a-0000-1000-8000-00805f9b34fb")
        val CHAR_MODEL_NUMBER: UUID = UUID.fromString("00002a24-0000-1000-8000-00805f9b34fb")
        val SERVICE_HEART_RATE: UUID = UUID.fromString("0000180d-0000-1000-8000-00805f9b34fb")
        val CHAR_HEART_RATE_MEASUREMENT: UUID = UUID.fromString("00002a37-0000-1000-8000-00805f9b34fb")
        val SERVICE_BLOOD_PRESSURE: UUID = UUID.fromString("00001810-0000-1000-8000-00805f9b34fb")
        val CHAR_BLOOD_PRESSURE_MEASUREMENT: UUID = UUID.fromString("00002a35-0000-1000-8000-00805f9b34fb")
        val SERVICE_PLX: UUID = UUID.fromString("00001822-0000-1000-8000-00805f9b34fb")
        val CHAR_PLX_SPOT_CHECK: UUID = UUID.fromString("00002a5e-0000-1000-8000-00805f9b34fb")
        val CHAR_PLX_CONTINUOUS: UUID = UUID.fromString("00002a5f-0000-1000-8000-00805f9b34fb")
        val CLIENT_CHARACTERISTIC_CONFIG: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    private val _status = MutableStateFlow(BandStatus(false, "未连接"))
    val status: StateFlow<BandStatus> = _status.asStateFlow()

    private val _devices = MutableStateFlow<List<RememberedDevice>>(emptyList())
    val devices: StateFlow<List<RememberedDevice>> = _devices.asStateFlow()

    private val _scanning = MutableStateFlow(false)
    val scanning: StateFlow<Boolean> = _scanning.asStateFlow()

    private val adapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private var scanCallback: ScanCallback? = null
    private var gatt: BluetoothGatt? = null
    private var deviceId: String = "unknown"
    private val pendingReads = ArrayDeque<Pair<UUID, UUID>>()

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    /** 扫描附近 BLE 设备（需要 BLUETOOTH_SCAN，Android 11 及以下需定位权限）。 */
    @SuppressLint("MissingPermission")
    fun startScan() {
        val scanPermission = if (android.os.Build.VERSION.SDK_INT >= 31) {
            Manifest.permission.BLUETOOTH_SCAN
        } else {
            Manifest.permission.ACCESS_FINE_LOCATION
        }
        if (!hasPermission(scanPermission)) {
            _status.value = BandStatus(false, "缺少扫描权限，请先授权")
            return
        }
        val scanner = adapter?.bluetoothLeScanner
        if (scanner == null) {
            _status.value = BandStatus(false, "蓝牙不可用")
            return
        }
        stopScan()
        _devices.value = emptyList()
        _scanning.value = true
        _status.value = BandStatus(false, "扫描中…")
        scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                if (_devices.value.any { it.address == result.device.address }) return
                _devices.value = _devices.value + RememberedDevice(
                    id = result.device.address,
                    name = result.device.name ?: "未命名设备",
                    address = result.device.address,
                    kind = "ble",
                    lastSeenAt = System.currentTimeMillis(),
                )
            }

            override fun onScanFailed(errorCode: Int) {
                _scanning.value = false
                _status.value = BandStatus(false, "扫描失败：错误码 $errorCode")
            }
        }
        runCatching { scanner.startScan(scanCallback) }
            .onFailure {
                _scanning.value = false
                _status.value = BandStatus(false, "扫描启动失败：${it.message}")
            }
    }

    fun stopScan() {
        scanCallback?.let { callback ->
            runCatching { adapter?.bluetoothLeScanner?.stopScan(callback) }
        }
        scanCallback = null
        _scanning.value = false
    }

    /** 连接并读取标准 GATT 体征（需要 BLUETOOTH_CONNECT）。 */
    @SuppressLint("MissingPermission")
    fun connect(address: String) {
        if (!hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
            _status.value = BandStatus(false, "缺少 BLUETOOTH_CONNECT 权限，请先授权")
            return
        }
        val a = adapter
        if (a == null || !a.isEnabled) {
            _status.value = BandStatus(false, "蓝牙不可用")
            return
        }
        disconnect()
        deviceId = address
        _status.value = BandStatus(false, "连接中：$address")
        val device: BluetoothDevice? = try {
            a.getRemoteDevice(address)
        } catch (_: IllegalArgumentException) {
            null
        }
        gatt = device?.connectGatt(context, false, callback)
        if (gatt == null) {
            _status.value = BandStatus(false, "无法发起 GATT 连接")
        }
    }

    fun disconnect() {
        gatt?.let { g ->
            runCatching { g.disconnect() }
            runCatching { g.close() }
        }
        gatt = null
        pendingReads.clear()
        _status.value = BandStatus(false, "未连接")
    }

    private val callback = object : BluetoothGattCallback() {

        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    _status.value = BandStatus(true, "已连接，正在发现服务")
                    runCatching { g.discoverServices() }
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    _status.value = BandStatus(false, "已断开")
                    runCatching { g.close() }
                    if (gatt === g) gatt = null
                }
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                _status.value = BandStatus(false, "服务发现失败：错误码 $status")
                return
            }
            _status.value = BandStatus(true, "已连接，正在读取体征")
            pendingReads.clear()
            pendingReads.addLast(SERVICE_BATTERY to CHAR_BATTERY_LEVEL)
            pendingReads.addLast(SERVICE_DEVICE_INFORMATION to CHAR_MODEL_NUMBER)
            pendingReads.addLast(SERVICE_BLOOD_PRESSURE to CHAR_BLOOD_PRESSURE_MEASUREMENT)
            pendingReads.addLast(SERVICE_PLX to CHAR_PLX_SPOT_CHECK)
            enableNotify(g, SERVICE_HEART_RATE, CHAR_HEART_RATE_MEASUREMENT)
            enableNotify(g, SERVICE_PLX, CHAR_PLX_CONTINUOUS)
            readNext(g)
        }

        override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            readNext(g)
        }

        // API 33+ 新签名
        override fun onCharacteristicRead(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int,
        ) {
            handleRead(g, characteristic, value, status)
        }

        // API 32 及以下旧签名
        override fun onCharacteristicRead(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            handleRead(g, characteristic, characteristic.value, status)
        }

        // API 33+ 新签名
        override fun onCharacteristicChanged(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            handleNotify(characteristic, value)
        }

        // API 32 及以下旧签名
        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            handleNotify(characteristic, characteristic.value)
        }

        private fun handleRead(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray?,
            status: Int,
        ) {
            if (status == BluetoothGatt.GATT_SUCCESS && value != null) {
                parseReading(characteristic.uuid, value)
            }
            readNext(g)
        }

        private fun handleNotify(characteristic: BluetoothGattCharacteristic, value: ByteArray?) {
            if (value != null) parseReading(characteristic.uuid, value)
        }
    }

    /** 按特征 UUID 解析读数并保存。 */
    private fun parseReading(uuid: UUID, value: ByteArray) {
        when (uuid) {
            CHAR_BATTERY_LEVEL -> if (value.isNotEmpty()) {
                saveVital("battery", value[0].toDouble(), "%")
            }
            CHAR_MODEL_NUMBER -> {
                val model = String(value, Charsets.UTF_8).trim()
                if (model.isNotEmpty()) _status.value = BandStatus(true, "已连接，型号：$model")
            }
            CHAR_BLOOD_PRESSURE_MEASUREMENT -> {
                val systolic = parseSFloat(value, 1)
                val diastolic = parseSFloat(value, 3)
                systolic?.let { saveVital("blood_pressure_systolic", it, "mmHg") }
                diastolic?.let { saveVital("blood_pressure_diastolic", it, "mmHg") }
            }
            CHAR_PLX_SPOT_CHECK, CHAR_PLX_CONTINUOUS -> {
                // PLX 基础测量格式：flags(1) + SpO2 SFLOAT(2) + 脉率 SFLOAT(2)
                parseSFloat(value, 1)?.let { saveVital("oxygen_saturation", it, "%") }
                parseSFloat(value, 3)?.let { saveVital("pulse", it, "次/分") }
            }
            CHAR_HEART_RATE_MEASUREMENT -> {
                if (value.isEmpty()) return
                val flags = value[0].toInt() and 0xFF
                val bpm = if (flags and 0x01 != 0 && value.size >= 3) {
                    ((value[2].toInt() and 0xFF) shl 8) or (value[1].toInt() and 0xFF)
                } else if (value.size >= 2) {
                    value[1].toInt() and 0xFF
                } else {
                    return
                }
                saveVital("heart_rate", bpm.toDouble(), "次/分")
            }
        }
    }

    private fun saveVital(kind: String, value: Double, unit: String) {
        val now = System.currentTimeMillis()
        onVital(
            WearableVitalEntity(
                id = "$deviceId|$kind|$now|gatt",
                deviceId = deviceId,
                kind = kind,
                value = value,
                recordAt = now,
                unit = unit,
                origin = "gatt",
            ),
        )
    }

    @SuppressLint("MissingPermission")
    private fun enableNotify(g: BluetoothGatt, service: UUID, charUuid: UUID) {
        val characteristic = g.getService(service)?.getCharacteristic(charUuid) ?: return
        val cccd = characteristic.getDescriptor(CLIENT_CHARACTERISTIC_CONFIG) ?: return
        runCatching {
            g.setCharacteristicNotification(characteristic, true)
            @Suppress("DEPRECATION")
            cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            @Suppress("DEPRECATION")
            g.writeDescriptor(cccd)
        }
    }

    @SuppressLint("MissingPermission")
    private fun readNext(g: BluetoothGatt) {
        val next = pendingReads.pollFirst() ?: return
        val characteristic = g.getService(next.first)?.getCharacteristic(next.second)
        if (characteristic == null) {
            readNext(g)
            return
        }
        val ok = runCatching {
            @Suppress("DEPRECATION")
            g.readCharacteristic(characteristic)
        }.getOrDefault(false)
        if (!ok) readNext(g)
    }
}

/** 解析 IEEE-11073 16-bit SFLOAT；NaN/INF 等特殊值返回 null。 */
fun parseSFloat(bytes: ByteArray, offset: Int): Double? {
    if (offset + 1 >= bytes.size) return null
    val raw = ((bytes[offset + 1].toInt() and 0xFF) shl 8) or (bytes[offset].toInt() and 0xFF)
    if (raw == 0x0800 || raw == 0x07FF || raw == 0x0801 || raw == 0x0802) return null
    var mantissa = raw and 0x0FFF
    if (mantissa and 0x0800 != 0) mantissa -= 0x1000
    var exponent = (raw shr 12) and 0x0F
    if (exponent and 0x08 != 0) exponent -= 0x10
    return mantissa * 10.0.pow(exponent)
}
