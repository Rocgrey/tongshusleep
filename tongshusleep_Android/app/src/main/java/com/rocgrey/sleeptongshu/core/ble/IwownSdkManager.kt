package com.rocgrey.sleeptongshu.core.ble

import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.alibaba.fastjson.JSON
import com.rocgrey.sleeptongshu.core.api.ApiClient
import com.rocgrey.sleeptongshu.core.api.RawSensorBatchRequest
import com.rocgrey.sleeptongshu.core.api.RawSensorBatchResponse
import com.rocgrey.sleeptongshu.core.api.RawSensorPacket
import com.rocgrey.sleeptongshu.core.auth.AccountState
import com.rocgrey.sleeptongshu.core.data.AppDatabase
import com.rocgrey.sleeptongshu.core.data.WearableVitalEntity
import com.zeroner.blemidautumn.Constants
import com.zeroner.blemidautumn.bean.WristBand
import com.zeroner.blemidautumn.bluetooth.IDataReceiveHandler
import com.zeroner.blemidautumn.bluetooth.SuperBleSDK
import com.zeroner.blemidautumn.bluetooth.cmdimpl.ProtoBufSendBluetoothCmdImpl
import com.zeroner.blemidautumn.bluetooth.impl.AbsBle
import com.zeroner.blemidautumn.bluetooth.impl.BleService
import com.zeroner.blemidautumn.bluetooth.model.ProtoBufHardwareInfo
import com.zeroner.blemidautumn.bluetooth.model.ProtoBufRealTimeData
import com.zeroner.blemidautumn.task.BackgroundThreadManager
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** BIO-7349（Iwown BLE SDK）通道管理：初始化、扫描、连接、实时数据分发。 */
object IwownSdkManager : IDataReceiveHandler {

    data class DeviceInfo(
        val version: String? = null,
        val model: String? = null,
        val mac: String? = null,
        val sn: String? = null,
        val battery: Int? = null,
        val charging: Boolean = false,
    )

    data class ScanItem(val name: String, val address: String, val rssi: Int)

    private const val SDK_TYPE = Constants.Bluetooth.Zeroner_protobuf_Sdk

    /** 传感器类型位掩码（getRtSensorData 的 type 参数）。 */
    const val SENSOR_ACC = 0x10
    const val SENSOR_PPG = 0x02
    const val SENSOR_BIOZ = 0x200
    const val SENSOR_SPO2 = 0x8000

    /** 采集原始信号 20 秒的默认组合：ACC | BIOZ | PPG。 */
    const val DEFAULT_CAPTURE_TYPES = SENSOR_ACC or SENSOR_BIOZ or SENSOR_PPG

    private const val RAW_UPLOAD_BATCH = 20

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var appContext: Context? = null
    private var clientProvider: (() -> ApiClient)? = null
    private var accountState: (() -> AccountState)? = null
    private var userScope: (() -> String)? = null

    private var historySync: IwownHistorySync? = null
    private var bleService: BleService? = null
    private var lastAddress: String? = null

    // ---------- 状态总线 ----------
    private val _connectionState = MutableStateFlow("idle")
    val connectionState: StateFlow<String> = _connectionState.asStateFlow()

    private val _deviceInfo = MutableStateFlow<DeviceInfo?>(null)
    val deviceInfo: StateFlow<DeviceInfo?> = _deviceInfo.asStateFlow()

    private val _scanResults = MutableStateFlow<List<ScanItem>>(emptyList())
    val scanResults: StateFlow<List<ScanItem>> = _scanResults.asStateFlow()

    private val _lastEvent = MutableStateFlow("")
    val lastEvent: StateFlow<String> = _lastEvent.asStateFlow()

    // ---------- 原始信号采集 ----------
    private var captureId: String? = null
    private var captureTypes: Int = 0
    private val rawBuffer = mutableListOf<RawSensorPacket>()

    /** AppContainer 就绪后注入云端能力（登录判定与上传客户端）。 */
    fun attach(container: com.rocgrey.sleeptongshu.AppContainer) {
        clientProvider = { container.apiClient }
        accountState = { container.accountStore.state.value }
        userScope = { container.accountStore.userScope() }
    }

    fun init(app: Application) {
        if (appContext != null) return
        appContext = app.applicationContext
        historySync = IwownHistorySync(
            context = app.applicationContext,
            onEvent = ::setEvent,
            onSyncing = { syncing -> _connectionState.value = if (syncing) "syncing" else "connected" },
            deviceIdProvider = { currentDeviceId() },
            signedIn = ::isSignedIn,
            client = { clientProvider?.invoke() },
            userScopeId = { userScope?.invoke() ?: "" },
        )
        try {
            SuperBleSDK.getInstance().init(app)
        } catch (e: Exception) {
            setEvent("SDK 初始化失败：${e.message}")
        }
        try {
            SuperBleSDK.addBleListener(app, this)
        } catch (e: Exception) {
            setEvent("SDK 监听注册失败：${e.message}")
        }
        try {
            app.bindService(Intent(app, BleService::class.java), serviceConnection, Context.BIND_AUTO_CREATE)
        } catch (e: Exception) {
            setEvent("蓝牙服务绑定失败：${e.message}")
        }
    }

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            try {
                bleService = (binder as? BleService.LocalBinder)?.service
                setEvent("蓝牙服务已就绪")
                // 服务起来后再切 SDK 类型，延迟 3 秒（SDK 内部有异步初始化）
                mainHandler.postDelayed({
                    val ctx = appContext ?: return@postDelayed
                    try {
                        SuperBleSDK.switchSDKTYpe(ctx, SDK_TYPE)
                        setEvent("已切换到 protobuf SDK")
                    } catch (e: Exception) {
                        setEvent("SDK 类型切换失败：${e.message}")
                    }
                }, 3000L)
            } catch (e: Exception) {
                setEvent("蓝牙服务绑定异常：${e.message}")
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            bleService = null
        }
    }

    // ---------- 对外操作 ----------
    fun startScan() {
        val ble = ble() ?: run { setEvent("蓝牙未就绪，无法扫描"); return }
        try {
            _scanResults.value = emptyList()
            _connectionState.value = "scan"
            ble.startScan3()
            setEvent("开始扫描")
        } catch (e: Exception) {
            _connectionState.value = "idle"
            setEvent("扫描失败：${e.message}")
        }
    }

    fun stopScan() {
        runCatching { ble()?.stopScan() }
        if (_connectionState.value == "scan") _connectionState.value = "idle"
    }

    fun connect(name: String, address: String) {
        val ble = ble() ?: run { setEvent("蓝牙未就绪，无法连接"); return }
        stopScan()
        lastAddress = address
        _connectionState.value = "connecting"
        try {
            ble.setWristBand(WristBand(name, address))
            ble.setNeedReconnect(true)
            ble.connect()
            setEvent("连接中：$name")
        } catch (e: Exception) {
            _connectionState.value = "disconnected"
            setEvent("连接发起失败：${e.message}")
        }
    }

    fun disconnect() {
        runCatching { ble()?.setNeedReconnect(false) }
        val address = lastAddress
        runCatching { if (address != null) ble()?.disconnect(address, false) }
        lastAddress = null
        _connectionState.value = "disconnected"
        setEvent("已断开连接")
    }

    fun forgetDevice() {
        disconnect()
        _deviceInfo.value = null
        setEvent("已清除设备绑定")
    }

    /** 采集原始信号：status 0 启动 / 1 暂停 / 2 停止。 */
    fun startSensorCapture(types: Int = DEFAULT_CAPTURE_TYPES) {
        captureId = UUID.randomUUID().toString()
        captureTypes = types
        synchronized(rawBuffer) { rawBuffer.clear() }
        sendCmd(ProtoBufSendBluetoothCmdImpl.getInstance().getRtSensorData(0, types))
        setEvent("开始采集原始信号（掩码 0x${types.toString(16)}）")
    }

    fun stopSensorCapture() {
        sendCmd(ProtoBufSendBluetoothCmdImpl.getInstance().getRtSensorData(2, captureTypes))
        captureTypes = 0
        flushRawPackets()
        setEvent("停止采集原始信号")
    }

    fun startHistorySync(days: Int = 3) {
        historySync?.start(days)
    }

    /** 请求设备能力信息（0x09 回调，供历史同步判定 health/rri 支持）。 */
    internal fun startSupportQuery() {
        sendCmd(ProtoBufSendBluetoothCmdImpl.getInstance().getDataInfo())
    }

    fun measureHeartRate() {
        val ctx = appContext ?: return
        sendCmd(ProtoBufSendBluetoothCmdImpl.getInstance().measureHeartRate(ctx))
        setEvent("开始实时心率测量")
    }

    fun stopHeartMeasure() {
        val ctx = appContext ?: return
        sendCmd(ProtoBufSendBluetoothCmdImpl.getInstance().stopMeasurement(ctx))
        setEvent("停止心率测量")
    }

    // ---------- 内部工具 ----------
    private fun ble(): AbsBle? {
        val ctx = appContext ?: return null
        return try {
            SuperBleSDK.createInstance(ctx)
        } catch (e: Exception) {
            null
        }
    }

    private fun sendCmd(bytes: ByteArray?) {
        val ctx = appContext ?: return
        if (bytes == null || bytes.isEmpty()) return
        try {
            BackgroundThreadManager.getInstance().addWriteData(ctx, bytes)
        } catch (e: Exception) {
            setEvent("指令发送失败：${e.message}")
        }
    }

    private fun setEvent(message: String) {
        _lastEvent.value = "${nowText()} $message"
    }

    private fun currentDeviceId(): String =
        lastAddress ?: _deviceInfo.value?.mac ?: "iwown-unknown"

    private fun isSignedIn(): Boolean =
        accountState?.invoke() is AccountState.SignedIn

    private fun nowText(): String =
        LocalDateTime.now(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("HH:mm:ss"))

    private fun saveVital(kind: String, value: Double, unit: String, recordAt: Long = System.currentTimeMillis()) {
        if (value <= 0.0) return
        val ctx = appContext ?: return
        val deviceId = currentDeviceId()
        scope.launch {
            runCatching {
                AppDatabase.get(ctx).wearableVitalDao().insertAll(
                    listOf(
                        WearableVitalEntity(
                            id = "$deviceId|$kind|$recordAt|iwown",
                            deviceId = deviceId,
                            kind = kind,
                            value = value,
                            recordAt = recordAt,
                            unit = unit,
                            origin = "iwown",
                        ),
                    ),
                )
            }
        }
    }

    // ---------- SDK 回调 ----------
    override fun onDataArrived(ble_sdk_type: Int, dataType: Int, data: String) {
        when (dataType) {
            0x0000 -> scope.launch { handleHardwareInfo(data) }
            0x0009 -> historySync?.onSupportInfo(data)
            0x0070 -> handleRealTime(data)
            0x0080 -> historySync?.on80Data(data)
            0x2a37, 0x00f4, 0x00f6 -> {
                val bpm = data.trim().toIntOrNull()
                if (bpm != null && bpm in 20..250) {
                    saveVital("heart_rate", bpm.toDouble(), "次/分")
                    setEvent("实时心率：$bpm")
                }
            }
        }
    }

    private suspend fun handleHardwareInfo(data: String) {
        runCatching {
            val info = JSON.parseObject(data, ProtoBufHardwareInfo::class.java)
            val current = _deviceInfo.value ?: DeviceInfo()
            _deviceInfo.value = current.copy(
                version = info.getVersion(),
                model = info.getModel(),
                mac = info.getMac(),
                sn = info.getSn(),
            )
            setEvent("设备信息：${info.getModel()} / ${info.getVersion()}")
        }
    }

    private fun handleRealTime(data: String) {
        scope.launch {
            runCatching {
                val rt = JSON.parseObject(data, ProtoBufRealTimeData::class.java)
                when {
                    rt.isBattery() -> {
                        val current = _deviceInfo.value ?: DeviceInfo()
                        _deviceInfo.value = current.copy(
                            battery = rt.getLevel(),
                            charging = rt.isCharging(),
                        )
                        setEvent("电量 ${rt.getLevel()}%${if (rt.isCharging()) "（充电中）" else ""}")
                    }
                    rt.isSensorData() -> collectRawPacket(rt)
                    rt.isHealthResult() -> {
                        saveVital("heart_rate", rt.getHr().toDouble(), "次/分")
                        saveVital("oxygen_saturation", rt.getSpo2().toDouble(), "%")
                        saveVital("blood_pressure_systolic", rt.getSbp().toDouble(), "mmHg")
                        saveVital("blood_pressure_diastolic", rt.getDbp().toDouble(), "mmHg")
                        saveVital("stress", rt.getStress().toDouble(), "分")
                        saveVital("respiratory_rate", rt.getBreathRate().toDouble(), "次/分")
                        setEvent("一键测量结果：HR ${rt.getHr()} / SpO2 ${rt.getSpo2()}")
                    }
                    rt.isHearth() && rt.getSteps() > 0 -> setEvent("实时步数：${rt.getSteps()}")
                }
            }
        }
    }

    /** 0x70 原始传感器包：映射 sensorType（ACC→16 / PPG→2 / BIOZ→512），登录后批量上传。 */
    private fun collectRawPacket(rt: ProtoBufRealTimeData) {
        val mapped = when (rt.getSensorType()) {
            SENSOR_ACC -> 16
            SENSOR_PPG -> 2
            SENSOR_BIOZ -> 512
            else -> return
        }
        val list = rt.getSensorDataList() ?: IntArray(0)
        val packet = RawSensorPacket(
            sensorType = mapped,
            sensorSeconds = rt.getSensorSeconds().toLong(),
            sensorSeq = rt.getSensorSeq(),
            sensorDataList = list.map { it.toLong() },
            receivedAt = LocalDateTime.now(ZoneId.systemDefault())
                .format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")),
        )
        val size = synchronized(rawBuffer) {
            rawBuffer.add(packet)
            rawBuffer.size
        }
        if (isSignedIn() && size >= RAW_UPLOAD_BATCH) {
            flushRawPackets()
        }
    }

    private fun flushRawPackets() {
        val packets = synchronized(rawBuffer) {
            val copy = rawBuffer.toList()
            rawBuffer.clear()
            copy
        }
        if (packets.isEmpty()) return
        val client = clientProvider?.invoke() ?: return
        if (!isSignedIn()) return
        val deviceId = currentDeviceId()
        val capture = captureId ?: UUID.randomUUID().toString()
        scope.launch {
            runCatching {
                client.post<RawSensorBatchResponse>(
                    "health/raw-sensor-batches",
                    RawSensorBatchRequest(
                        uploadId = UUID.randomUUID().toString(),
                        captureId = capture,
                        deviceId = deviceId,
                        deviceName = _deviceInfo.value?.model ?: "BIO-7349",
                        packets = packets,
                    ),
                )
            }.onSuccess { setEvent("原始信号已上传 ${packets.size} 包") }
                .onFailure { setEvent("原始信号上传失败：${it.message}") }
        }
    }

    override fun onScanResult(dev: WristBand?) {
        if (dev == null) return
        val item = ScanItem(
            name = dev.getName() ?: "未命名设备",
            address = dev.getAddress() ?: return,
            rssi = dev.getRssi(),
        )
        val updated = _scanResults.value
            .filterNot { it.address == item.address } + item
        _scanResults.value = updated.sortedByDescending { it.rssi }
    }

    override fun onBluetoothInit() {
        setEvent("蓝牙协议初始化完成")
        // 连接后的初始化指令序列（时序同 demo）
        sendCmd(ProtoBufSendBluetoothCmdImpl.getInstance().setTime())
        sendCmd(ProtoBufSendBluetoothCmdImpl.getInstance().getHardwareFeatures())
        sendCmd(ProtoBufSendBluetoothCmdImpl.getInstance().getDataInfo())
        sendCmd(ProtoBufSendBluetoothCmdImpl.getInstance().getBattery())
        sendCmd(ProtoBufSendBluetoothCmdImpl.getInstance().getRealHealthData())
        sendCmd(ProtoBufSendBluetoothCmdImpl.getInstance().setAppHasConnect())
    }

    override fun connectStatue(isConnect: Boolean) {
        if (isConnect) {
            _connectionState.value = "connected"
            setEvent("设备已连接")
        } else {
            _connectionState.value = "disconnected"
            setEvent("设备已断开")
        }
    }

    override fun onDiscoverService(serviceUUID: String?) = Unit

    override fun onDiscoverCharacter(characterUUID: String?) = Unit

    override fun onCommonSend(data: ByteArray?) = Unit

    override fun onCmdReceive(data: ByteArray?) = Unit

    override fun onCharacteristicChange(address: String?) = Unit

    override fun onBluetoothError() {
        setEvent("蓝牙错误")
    }

    override fun onPreConnect() {
        _connectionState.value = "connecting"
        setEvent("正在连接…")
    }

    override fun noCallback() = Unit

    override fun onConnectionStateChanged(state: Int, newState: Int) = Unit

    override fun onSdkAutoReconnectTimesOut() {
        setEvent("自动重连超时")
        _connectionState.value = "disconnected"
    }
}
