package com.rocgrey.sleeptongshu.ui.monitoring

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rocgrey.sleeptongshu.LocalAppContainer
import com.rocgrey.sleeptongshu.core.ble.BioLocalSleepCalculator
import com.rocgrey.sleeptongshu.core.ble.EncryptedBandChannel
import com.rocgrey.sleeptongshu.core.ble.GattVitalsClient
import com.rocgrey.sleeptongshu.core.ble.IwownProbeChannel
import com.rocgrey.sleeptongshu.core.ble.StBandChannel
import com.rocgrey.sleeptongshu.core.ble.VeepooChannel
import com.rocgrey.sleeptongshu.core.monitor.PhoneMonitorResultBus
import com.rocgrey.sleeptongshu.core.monitor.PhoneMonitorService
import com.rocgrey.sleeptongshu.core.sleep.SleepBackup
import com.rocgrey.sleeptongshu.core.sleep.SleepRecordMapper
import com.rocgrey.sleeptongshu.core.sleep.SleepSource
import com.rocgrey.sleeptongshu.ui.theme.LocalSleepPalette
import java.io.File
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.launch

/** 监测页（对应 iOS MonitoringView）：手机监测 + BLE 设备 + 厂商通道 + 本地数据。 */
@Composable
fun MonitoringScreen() {
    val container = LocalAppContainer.current
    val context = LocalContext.current
    val palette = LocalSleepPalette.current
    val scope = rememberCoroutineScope()
    val prefs = container.preferences
    val db = container.database

    // ---------- 手机监测 ----------
    val running by PhoneMonitorService.running.collectAsStateWithLifecycle()
    val minutes by PhoneMonitorService.minuteCount.collectAsStateWithLifecycle()
    val phoneNight by PhoneMonitorResultBus.latest.collectAsStateWithLifecycle()
    val saveVoice by prefs.saveCandidateVoice.collectAsStateWithLifecycle(initialValue = false)
    var message by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf<String?>(null) }

    val audioLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            PhoneMonitorService.start(context)
        } else {
            message = "需要麦克风权限才能进行手机监测"
        }
    }

    // ---------- BLE 设备 ----------
    var vitals by remember { mutableStateOf(listOf<com.rocgrey.sleeptongshu.core.data.WearableVitalEntity>()) }
    val bleClient = remember {
        GattVitalsClient(context) { entity ->
            scope.launch {
                db.wearableVitalDao().insertAll(listOf(entity))
                vitals = db.wearableVitalDao().all()
            }
        }
    }
    val gattStatus by bleClient.status.collectAsStateWithLifecycle()
    val scanned by bleClient.devices.collectAsStateWithLifecycle()
    val scanning by bleClient.scanning.collectAsStateWithLifecycle()

    val bleLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { result ->
        bleClient.startScan()
    }

    // ---------- 备份导入 ----------
    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            try {
                val text = context.contentResolver.openInputStream(uri)
                    ?.use { it.readBytes().toString(Charsets.UTF_8) }
                    ?: error("无法读取所选文件")
                val existing = db.sleepRecordDao().all().map { it.id }.toSet()
                val imported = SleepBackup.import(text, existing)
                imported.forEach { db.sleepRecordDao().upsert(SleepRecordMapper.toEntity(it)) }
                message = "导入完成：新增 ${imported.size} 条记录"
            } catch (e: Exception) {
                message = "导入失败：${e.message}"
            }
        }
    }

    // ---------- 厂商通道（架构预留，全部未接入） ----------
    val vendorChannels = remember {
        listOf(
            VeepooChannel(),
            IwownProbeChannel(),
            StBandChannel(),
            EncryptedBandChannel(),
            BioLocalSleepCalculator(),
        )
    }

    // ---------- 睡眠目标 ----------
    val goalHours by prefs.sleepGoalHours.collectAsStateWithLifecycle(initialValue = 8f)
    var goalText by remember(goalHours) { mutableStateOf(goalHours.toString()) }

    LaunchedEffect(Unit) {
        vitals = db.wearableVitalDao().all()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("监测", style = MaterialTheme.typography.headlineSmall)

        // ---------- 手机监测面板 ----------
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("手机监测", style = MaterialTheme.typography.titleMedium)
                Text(
                    "用手机麦克风与加速度计记录夜间环境声音与体动，停止后按静默窗启发式估算入睡时长。" +
                        if (PhoneMonitorService.CLASSIFIER_AVAILABLE) "" else "（本版本无声音分类：鼾声/说话时长不统计）",
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.muted,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(
                        onClick = {
                            val granted = ContextCompat.checkSelfPermission(
                                context,
                                Manifest.permission.RECORD_AUDIO,
                            ) == PackageManager.PERMISSION_GRANTED
                            if (granted) {
                                PhoneMonitorService.start(context)
                            } else {
                                audioLauncher.launch(Manifest.permission.RECORD_AUDIO)
                            }
                        },
                        enabled = !running,
                    ) {
                        Text("开始监测")
                    }
                    Button(
                        onClick = { PhoneMonitorService.stop(context) },
                        enabled = running,
                    ) {
                        Text("停止监测")
                    }
                }
                if (running) {
                    Text(
                        "监测中：已聚合 $minutes 分钟",
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.mint,
                    )
                }
                phoneNight?.let { night ->
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(
                            modifier = Modifier.padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text("最近一夜（手机监测）", style = MaterialTheme.typography.titleSmall)
                            Text(
                                "估算入睡后时长：" + (night.estimatedMinutes?.let {
                                    "${it / 60}小时${it % 60}分"
                                } ?: "未检出明确入睡点"),
                            )
                            Text("音频采集：${night.audioSeconds ?: 0} 秒")
                            Text("体动样本：${night.movementSamples ?: 0} 次")
                            Text(
                                "鼾声/说话：未统计（无声音分类器）",
                                style = MaterialTheme.typography.bodySmall,
                                color = palette.muted,
                            )
                        }
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("保存候选语音", style = MaterialTheme.typography.titleSmall)
                        Text(
                            "仅保存偏好设置；本轮版本不做录音文件保存。",
                            style = MaterialTheme.typography.bodySmall,
                            color = palette.muted,
                        )
                    }
                    Switch(
                        checked = saveVoice,
                        onCheckedChange = { checked ->
                            scope.launch { prefs.setSaveCandidateVoice(checked) }
                        },
                    )
                }
            }
        }

        // ---------- BLE 设备面板 ----------
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("蓝牙设备（标准 GATT）", style = MaterialTheme.typography.titleMedium)
                Text(
                    "扫描附近设备，连接后可读取电量、型号、心率、血压与血氧。" +
                        "Android 12+ 需要蓝牙扫描与连接权限。",
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.muted,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(onClick = { bleLauncher.launch(blePermissions()) }) {
                        Text(if (scanning) "扫描中…" else "扫描设备")
                    }
                    if (scanning) {
                        TextButton(onClick = { bleClient.stopScan() }) { Text("停止扫描") }
                    }
                }
                if (scanned.isEmpty()) {
                    Text(
                        if (scanning) "正在搜索附近设备…" else "暂无扫描结果",
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.muted,
                    )
                }
                scanned.forEach { device ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(device.name, style = MaterialTheme.typography.bodyMedium)
                            Text(
                                device.address,
                                style = MaterialTheme.typography.bodySmall,
                                color = palette.muted,
                            )
                        }
                        TextButton(onClick = { bleClient.stopScan(); bleClient.connect(device.address) }) {
                            Text("连接")
                        }
                    }
                }
                Text(gattStatus.message, style = MaterialTheme.typography.bodySmall)
            }
        }

        // ---------- 厂商通道卡片 ----------
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("厂商通道", style = MaterialTheme.typography.titleMedium)
                vendorChannels.forEach { channel ->
                    val status by channel.status.collectAsStateWithLifecycle()
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(channel.name, style = MaterialTheme.typography.bodyMedium)
                            Text(
                                status.message,
                                style = MaterialTheme.typography.bodySmall,
                                color = palette.muted,
                            )
                        }
                        Button(
                            onClick = { },
                            enabled = channel.isAvailable,
                        ) {
                            Text("连接")
                        }
                    }
                }
            }
        }

        // ---------- 本地数据 ----------
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("本地数据", style = MaterialTheme.typography.titleMedium)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = goalText,
                        onValueChange = { goalText = it },
                        label = { Text("睡眠目标（小时）") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = {
                        val value = goalText.toFloatOrNull()
                        if (value != null && value in 1f..14f) {
                            scope.launch { prefs.setSleepGoalHours(value) }
                            message = "睡眠目标已保存：$value 小时"
                        } else {
                            message = "请输入 1-14 之间的小时数"
                        }
                    }) {
                        Text("保存")
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    TextButton(onClick = {
                        scope.launch {
                            try {
                                val records = db.sleepRecordDao().all()
                                    .map { SleepRecordMapper.toDomain(it) }
                                val text = SleepBackup.export(
                                    records,
                                    LocalDateTime.now()
                                        .format(java.time.format.DateTimeFormatter.ISO_LOCAL_DATE_TIME),
                                )
                                val file = File(
                                    context.cacheDir,
                                    "tongshu-sleep-backup-${System.currentTimeMillis()}.json",
                                )
                                file.writeText(text)
                                message = "已导出到：${file.absolutePath}"
                            } catch (e: Exception) {
                                message = "导出失败：${e.message}"
                            }
                        }
                    }) {
                        Text("备份导出")
                    }
                    TextButton(onClick = {
                        importLauncher.launch(arrayOf("application/json", "text/plain", "*/*"))
                    }) {
                        Text("备份导入")
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    TextButton(onClick = { confirmDelete = "sample" }) {
                        Text("删除示例数据", color = palette.rose)
                    }
                    TextButton(onClick = { confirmDelete = "all" }) {
                        Text("删除全部数据", color = palette.rose)
                    }
                }
            }
        }

        // ---------- 设备体征历史 ----------
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text("设备体征历史", style = MaterialTheme.typography.titleMedium)
                if (vitals.isEmpty()) {
                    Text(
                        "暂无设备读数。连接标准 GATT 设备后自动记录。",
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.muted,
                    )
                }
                vitals.take(50).forEach { vital ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            "${vitalLabel(vital.kind)}（${vital.deviceId.takeLast(6)}）",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Text(
                            "${formatValue(vital.value)} ${vital.unit} · " +
                                formatDateTime(vital.recordAt),
                            style = MaterialTheme.typography.bodySmall,
                            color = palette.muted,
                        )
                    }
                }
            }
        }

        message?.let { text ->
            Text(text, style = MaterialTheme.typography.bodySmall, color = palette.mint)
        }
    }

    confirmDelete?.let { action ->
        AlertDialog(
            onDismissRequest = { confirmDelete = null },
            title = {
                Text(if (action == "sample") "删除示例数据" else "删除全部睡眠数据")
            },
            text = {
                Text(
                    if (action == "sample") {
                        "将删除所有来源为示例的睡眠记录，删除后无法恢复。"
                    } else {
                        "将删除本地全部睡眠记录，删除后无法恢复。建议先导出备份。"
                    },
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    val target = confirmDelete
                    confirmDelete = null
                    scope.launch {
                        try {
                            if (target == "sample") {
                                val sampleIds = db.sleepRecordDao().all()
                                    .filter { it.source == SleepSource.SAMPLE.key }
                                    .map { it.id }
                                sampleIds.forEach { db.sleepRecordDao().delete(it) }
                                message = "已删除 ${sampleIds.size} 条示例数据"
                            } else {
                                db.sleepRecordDao().deleteAll()
                                message = "已删除全部睡眠数据"
                            }
                        } catch (e: Exception) {
                            message = "删除失败：${e.message}"
                        }
                    }
                }) {
                    Text("删除", color = palette.rose)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = null }) { Text("取消") }
            },
        )
    }
}

private fun blePermissions(): Array<String> =
    if (android.os.Build.VERSION.SDK_INT >= 31) {
        arrayOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
        )
    } else {
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }

private fun vitalLabel(kind: String): String = when (kind) {
    "battery" -> "电量"
    "heart_rate" -> "心率"
    "blood_pressure_systolic" -> "收缩压"
    "blood_pressure_diastolic" -> "舒张压"
    "oxygen_saturation" -> "血氧"
    "pulse" -> "脉率"
    else -> kind
}

private fun formatValue(value: Double): String {
    val rounded = (value * 10).toLong() / 10.0
    return if (rounded == rounded.toLong().toDouble()) {
        rounded.toLong().toString()
    } else {
        rounded.toString()
    }
}

private fun formatDateTime(epochMs: Long): String =
    LocalDateTime.ofInstant(Instant.ofEpochMilli(epochMs), ZoneId.systemDefault())
        .format(DateTimeFormatter.ofPattern("MM-dd HH:mm"))
