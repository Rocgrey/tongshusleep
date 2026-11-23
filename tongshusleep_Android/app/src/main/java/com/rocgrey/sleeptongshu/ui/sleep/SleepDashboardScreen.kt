@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.rocgrey.sleeptongshu.ui.sleep

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rocgrey.sleeptongshu.LocalAppContainer
import com.rocgrey.sleeptongshu.core.auth.AccountState
import com.rocgrey.sleeptongshu.core.data.SleepRecordDao
import com.rocgrey.sleeptongshu.core.sleep.HeartSample
import com.rocgrey.sleeptongshu.core.sleep.SleepMetadata
import com.rocgrey.sleeptongshu.core.sleep.SleepRecord
import com.rocgrey.sleeptongshu.core.sleep.SleepRecordMapper
import com.rocgrey.sleeptongshu.core.sleep.SleepSegment
import com.rocgrey.sleeptongshu.core.sleep.SleepSource
import com.rocgrey.sleeptongshu.core.sleep.SleepStage
import com.rocgrey.sleeptongshu.core.sleep.buildManualRecord
import com.rocgrey.sleeptongshu.core.sync.AutomaticSync
import com.rocgrey.sleeptongshu.ui.theme.LocalSleepPalette
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt
import kotlin.random.Random

// 来源分段：与 iOS device / health / all 对应
private const val FILTER_DEVICE = 0
private const val FILTER_HEALTH = 1
private const val FILTER_ALL = 2

private val dayLabelFmt: DateTimeFormatter = DateTimeFormatter.ofPattern("M月d日 EEEE", Locale.CHINESE)
private val shortDateFmt: DateTimeFormatter = DateTimeFormatter.ofPattern("M月d日")
private val timeFmt: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

@Composable
fun SleepDashboardScreen() {
    val container = LocalAppContainer.current
    val context = LocalContext.current
    val palette = LocalSleepPalette.current
    val dao = container.database.sleepRecordDao()

    val allRecords by dao.observeAll()
        .map { list -> list.map(SleepRecordMapper::toDomain) }
        .collectAsStateWithLifecycle(initialValue = emptyList())
    val goalHours by container.preferences.sleepGoalHours.collectAsStateWithLifecycle(initialValue = 8f)
    val accountState by container.accountStore.state.collectAsStateWithLifecycle()

    // 首次启动示例数据（只种一次）
    LaunchedEffect(Unit) {
        if (!container.preferences.hasSeededDemo.first()) {
            seedDemoRecords(dao)
            container.preferences.setHasSeededDemo(true)
        }
    }

    var selectedDate by remember { mutableStateOf(LocalDate.now()) }
    var filterChoice by remember { mutableStateOf<Int?>(null) }
    val hasBand = allRecords.any { it.source == SleepSource.BAND }
    val effectiveFilter = filterChoice ?: if (hasBand) FILTER_DEVICE else FILTER_ALL

    val nightRecords = allRecords
        .filter { it.day == selectedDate && matchesFilter(it.source, effectiveFilter) }
        .sortedBy { it.start.toEpochMilli() }
    val primary = nightRecords.maxByOrNull { it.asleepMinutes }
        ?: nightRecords.maxByOrNull { it.inBedMinutes }

    var showAisSheet by remember { mutableStateOf(false) }
    var showListSheet by remember { mutableStateOf(false) }
    var showEditorSheet by remember { mutableStateOf(false) }
    var syncing by remember { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    val autoSync = remember {
        AutomaticSync(context.applicationContext) { container.apiClient }
    }

    fun saveManualRecord(bed: LocalTime, wake: LocalTime, note: String) {
        val zone = ZoneId.systemDefault()
        var bedDateTime = selectedDate.atTime(bed)
        val wakeDateTime = selectedDate.atTime(wake)
        if (!wakeDateTime.isAfter(bedDateTime)) bedDateTime = bedDateTime.minusDays(1)
        val record = buildManualRecord(
            start = bedDateTime.atZone(zone).toInstant(),
            end = wakeDateTime.atZone(zone).toInstant(),
            zone = zone,
            note = note.trim().ifEmpty { null },
            aisScore = null,
        )
        showEditorSheet = false
        coroutineScope.launch {
            dao.upsert(SleepRecordMapper.toEntity(record))
            snackbarHostState.showSnackbar("已保存手动记录")
        }
    }

    fun syncNightToCloud() {
        val records = nightRecords
        if (records.isEmpty() || syncing) return
        syncing = true
        coroutineScope.launch {
            val resultText = try {
                if (!autoSync.checkCapabilities()) {
                    "账号云端暂不支持同步（能力校验未通过）"
                } else {
                    val scopeId = container.accountStore.userScope()
                    var ok = 0
                    records.forEach { record ->
                        runCatching { autoSync.pushSleepRecord(record, scopeId) }.onSuccess { ok++ }
                    }
                    "已同步 $ok/${records.size} 条记录到账号云端"
                }
            } catch (e: Exception) {
                "同步失败：${e.message ?: "网络异常"}"
            }
            syncing = false
            snackbarHostState.showSnackbar(resultText)
        }
    }

    Scaffold(snackbarHost = { SnackbarHost(snackbarHostState) }) { innerPadding ->
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(innerPadding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // 品牌头部
            Text(
                "睡眠同书",
                style = MaterialTheme.typography.titleLarge,
                color = palette.teal,
                fontWeight = FontWeight.Bold,
            )

            // 来源分段：设备 / 系统健康 / 全部
            TongshuSegmented(
                options = listOf("设备", "系统健康", "全部"),
                selectedIndex = effectiveFilter,
                onSelect = { filterChoice = it },
            )

            // 日期前后导航
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { selectedDate = selectedDate.minusDays(1) }) {
                    Icon(Icons.Filled.ChevronLeft, contentDescription = "前一天")
                }
                Column(
                    Modifier.weight(1f),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        dayLabelFmt.format(selectedDate),
                        style = MaterialTheme.typography.titleMedium,
                        color = palette.ink,
                    )
                    if (selectedDate == LocalDate.now()) {
                        Text("今天", style = MaterialTheme.typography.labelSmall, color = palette.teal)
                    }
                }
                IconButton(onClick = { selectedDate = selectedDate.plusDays(1) }) {
                    Icon(Icons.Filled.ChevronRight, contentDescription = "后一天")
                }
            }

            // 详情卡
            Surface(
                shape = RoundedCornerShape(18.dp),
                color = palette.surface,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(
                    Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    if (primary == null) {
                        Text("这一天暂无睡眠记录", style = MaterialTheme.typography.titleMedium, color = palette.ink)
                        Text(
                            "可以切换日期查看，或点击下方「手动记录」补录一晚。",
                            style = MaterialTheme.typography.bodySmall,
                            color = palette.muted,
                        )
                    } else {
                        Row(verticalAlignment = Alignment.Bottom) {
                            Text(
                                formatDuration(primary.asleepMinutes),
                                style = MaterialTheme.typography.titleLarge,
                                color = palette.ink,
                            )
                            Spacer(Modifier.weight(1f))
                            Text(
                                "目标 ${formatGoal(goalHours)}",
                                style = MaterialTheme.typography.labelLarge,
                                color = palette.muted,
                            )
                        }
                        val goalMinutes = (goalHours * 60).toInt().coerceAtLeast(1)
                        val progress = ((primary.asleepMinutes.toFloat()) / goalMinutes).coerceIn(0f, 1f)
                        LinearProgressIndicator(
                            progress = { progress },
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(8.dp)
                                .clip(RoundedCornerShape(4.dp)),
                            color = palette.teal,
                            trackColor = palette.line,
                        )
                        // 统计：入睡 / 起床 / 参考分 / 效率 / 清醒次数
                        val onsetText = primary.sleepOnset
                            ?.let { timeFmt.format(it.atZone(primary.zoneId)) }
                            ?: timeFmt.format(primary.start.atZone(primary.zoneId))
                        val endText = primary.sleepEnd
                            ?.let { timeFmt.format(it.atZone(primary.zoneId)) }
                            ?: timeFmt.format(primary.end.atZone(primary.zoneId))
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                            StatCell("入睡", onsetText, Modifier.weight(1f))
                            StatCell("起床", endText, Modifier.weight(1f))
                            StatCell(
                                "参考分",
                                primary.score?.toString() ?: primary.metadata.aisScore?.toString() ?: "—",
                                Modifier.weight(1f),
                            )
                        }
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                            StatCell(
                                "效率",
                                primary.efficiency?.let { "${it.roundToInt()}%" } ?: "—",
                                Modifier.weight(1f),
                            )
                            StatCell("清醒次数", "${primary.awakenings}", Modifier.weight(1f))
                            StatCell("夜间清醒", "${primary.awakeMinutes} 分", Modifier.weight(1f))
                        }
                    }

                    // 操作按钮
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(
                            onClick = { showAisSheet = true },
                            enabled = primary != null,
                            modifier = Modifier.weight(1f),
                        ) { Text("AIS") }
                        OutlinedButton(
                            onClick = { showListSheet = true },
                            enabled = nightRecords.isNotEmpty(),
                            modifier = Modifier.weight(1f),
                        ) { Text("记录列表") }
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(
                            onClick = { showEditorSheet = true },
                            modifier = Modifier.weight(1f),
                        ) { Text("手动记录") }
                        if (accountState is AccountState.SignedIn) {
                            OutlinedButton(
                                onClick = { syncNightToCloud() },
                                enabled = !syncing && nightRecords.isNotEmpty(),
                                modifier = Modifier.weight(1f),
                            ) { Text(if (syncing) "同步中…" else "同步到账号") }
                        }
                    }
                }
            }

            // 阶段时间线
            if (primary != null && primary.segments.isNotEmpty()) {
                SectionTitle("睡眠阶段", palette)
                StageTimeline(
                    segments = primary.segments,
                    start = primary.start.toEpochMilli(),
                    end = primary.end.toEpochMilli(),
                )
            }

            // 阶段占比
            if (primary != null && primary.asleepMinutes > 0) {
                SectionTitle("阶段占比", palette)
                SleepStageBalance(
                    deepMinutes = primary.minutesOf(setOf(SleepStage.DEEP)),
                    lightMinutes = primary.minutesOf(setOf(SleepStage.LIGHT)),
                    remMinutes = primary.minutesOf(setOf(SleepStage.REM)),
                )
            }

            // 夜间体征
            val heartRate = nightRecords.firstNotNullOfOrNull { it.averageHeartRate }
            val spo2 = nightRecords.firstNotNullOfOrNull { it.averageSpO2 }
            if (heartRate != null || spo2 != null) {
                SectionTitle("夜间体征", palette)
                Surface(
                    shape = RoundedCornerShape(16.dp),
                    color = palette.surface,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        Modifier.padding(vertical = 14.dp),
                        horizontalArrangement = Arrangement.SpaceEvenly,
                    ) {
                        StatCell("平均心率", heartRate?.let { "${it.roundToInt()} 次/分" } ?: "—")
                        StatCell("平均血氧", spo2?.let { "${it.roundToInt()}%" } ?: "—")
                    }
                }
            }

            // 心率曲线
            if (primary != null && primary.heartSamples.isNotEmpty()) {
                SectionTitle("心率曲线", palette)
                HeartRateChart(samples = primary.heartSamples, average = primary.averageHeartRate)
            }

            // 这一晚的小结
            SectionTitle("这一晚的小结", palette)
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = palette.surface,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    nightSummary(primary, goalHours),
                    Modifier.padding(14.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.ink,
                )
            }

            Spacer(Modifier.height(8.dp))
        }
    }

    if (showAisSheet) {
        SleepAisSheet(
            currentScore = primary?.metadata?.aisScore,
            onDismiss = { showAisSheet = false },
            onSave = { value ->
                showAisSheet = false
                val record = primary
                if (value != null && record != null) {
                    coroutineScope.launch {
                        dao.upsert(
                            SleepRecordMapper.toEntity(
                                record.copy(metadata = record.metadata.copy(aisScore = value)),
                            ),
                        )
                        snackbarHostState.showSnackbar("已更新 AIS 总分为 $value")
                    }
                }
            },
        )
    }

    if (showListSheet) {
        NightRecordsSheet(records = nightRecords, onDismiss = { showListSheet = false })
    }

    if (showEditorSheet) {
        SleepEditorSheet(
            anchorDate = selectedDate,
            onDismiss = { showEditorSheet = false },
            onSave = ::saveManualRecord,
        )
    }
}

// ---------------------------------------------------------------------------
// 内部组件与工具
// ---------------------------------------------------------------------------

private fun matchesFilter(source: SleepSource, filterIndex: Int): Boolean = when (filterIndex) {
    FILTER_DEVICE -> source == SleepSource.BAND
    FILTER_HEALTH -> source == SleepSource.HEALTH_CONNECT
    else -> true
}

@Composable
private fun SectionTitle(text: String, palette: com.rocgrey.sleeptongshu.ui.theme.SleepPalette) {
    Text(text, style = MaterialTheme.typography.titleSmall, color = palette.ink)
}

@Composable
private fun StatCell(label: String, value: String, modifier: Modifier = Modifier) {
    val palette = LocalSleepPalette.current
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleSmall, color = palette.ink)
        Text(label, style = MaterialTheme.typography.labelSmall, color = palette.muted)
    }
}

private fun nightSummary(record: SleepRecord?, goalHours: Float): String {
    if (record == null || record.asleepMinutes <= 0) {
        return "这一天还没有可展示的睡眠数据，可点击「手动记录」补录一晚。"
    }
    val asleep = record.asleepMinutes
    val deep = record.minutesOf(setOf(SleepStage.DEEP))
    val rem = record.minutesOf(setOf(SleepStage.REM))
    val parts = mutableListOf("这一晚入睡 ${formatDuration(asleep)}")
    if (deep > 0) parts.add("深睡 $deep 分钟（${deep * 100 / asleep}%）")
    if (rem > 0) parts.add("做梦 $rem 分钟")
    if (deep <= 0 && rem <= 0) parts.add("本记录未细分睡眠阶段")
    if (record.awakenings > 0) parts.add("夜间醒来 ${record.awakenings} 次")
    record.efficiency?.let { parts.add("睡眠效率 ${it.roundToInt()}%") }
    val goalMinutes = (goalHours * 60).toInt()
    parts.add(
        if (asleep >= goalMinutes) "已达成 ${formatGoal(goalHours)} 的睡眠目标"
        else "距 ${formatGoal(goalHours)} 的目标还差 ${formatDuration(goalMinutes - asleep)}",
    )
    return parts.joinToString("，") + "。"
}

// ---------------------------------------------------------------------------
// AIS 弹层
// ---------------------------------------------------------------------------

@Composable
private fun SleepAisSheet(
    currentScore: Int?,
    onDismiss: () -> Unit,
    onSave: (Int?) -> Unit,
) {
    val palette = LocalSleepPalette.current
    var input by remember { mutableStateOf(currentScore?.toString() ?: "") }
    var error by remember { mutableStateOf<String?>(null) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("AIS 睡眠自评", style = MaterialTheme.typography.titleMedium, color = palette.ink)
            Text(
                "填写阿森斯失眠量表总分（0–24）；留空表示不修改。",
                style = MaterialTheme.typography.bodySmall,
                color = palette.muted,
            )
            OutlinedTextField(
                value = input,
                onValueChange = { input = it.filter { c -> c.isDigit() }.take(2) },
                label = { Text("总分（0–24，可留空）") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                isError = error != null,
                supportingText = if (error != null) {
                    { Text(error ?: "", color = MaterialTheme.colorScheme.error) }
                } else {
                    null
                },
                modifier = Modifier.fillMaxWidth(),
            )
            Row(
                Modifier.align(Alignment.End),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                TextButton(onClick = onDismiss) { Text("取消") }
                Button(onClick = {
                    val trimmed = input.trim()
                    if (trimmed.isEmpty()) {
                        onSave(null)
                    } else {
                        val value = trimmed.toIntOrNull()
                        if (value == null || value !in 0..24) {
                            error = "请输入 0–24 之间的整数"
                        } else {
                            onSave(value)
                        }
                    }
                }) { Text("保存") }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 记录列表弹层
// ---------------------------------------------------------------------------

@Composable
private fun NightRecordsSheet(records: List<SleepRecord>, onDismiss: () -> Unit) {
    val palette = LocalSleepPalette.current
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "这一晚的记录（${records.size} 条）",
                style = MaterialTheme.typography.titleMedium,
                color = palette.ink,
            )
            records.forEach { record ->
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        "${record.source.label} · " +
                            "${timeFmt.format(record.start.atZone(record.zoneId))} – " +
                            timeFmt.format(record.end.atZone(record.zoneId)),
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.ink,
                    )
                    Text(
                        "入睡 ${formatDuration(record.asleepMinutes)} · 清醒 ${record.awakeMinutes} 分",
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.muted,
                    )
                    record.note?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall, color = palette.muted)
                    }
                }
            }
            if (records.isEmpty()) {
                Text("这一天没有记录。", style = MaterialTheme.typography.bodySmall, color = palette.muted)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 手动记录弹层
// ---------------------------------------------------------------------------

@Composable
private fun SleepEditorSheet(
    anchorDate: LocalDate,
    onDismiss: () -> Unit,
    onSave: (bed: LocalTime, wake: LocalTime, note: String) -> Unit,
) {
    val palette = LocalSleepPalette.current
    var bedTime by remember { mutableStateOf(LocalTime.of(23, 0)) }
    var wakeTime by remember { mutableStateOf(LocalTime.of(7, 0)) }
    var note by remember { mutableStateOf("") }
    var picking by remember { mutableStateOf<Int?>(null) } // 0 = 入睡，1 = 起床

    if (picking != null) {
        TimePickDialog(
            title = if (picking == 0) "选择入睡时间" else "选择起床时间",
            initial = if (picking == 0) bedTime else wakeTime,
            onConfirm = { picked ->
                if (picking == 0) bedTime = picked else wakeTime = picked
                picking = null
            },
            onDismiss = { picking = null },
        )
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("手动记录睡眠", style = MaterialTheme.typography.titleMedium, color = palette.ink)
            Text(
                "起床日期按 ${shortDateFmt.format(anchorDate)} 这一晚计算；" +
                    "若起床早于入睡，入睡会自动按前一晚处理。",
                style = MaterialTheme.typography.bodySmall,
                color = palette.muted,
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { picking = 0 }, modifier = Modifier.weight(1f)) {
                    Text("入睡 ${timeFmt.format(bedTime)}")
                }
                OutlinedButton(onClick = { picking = 1 }, modifier = Modifier.weight(1f)) {
                    Text("起床 ${timeFmt.format(wakeTime)}")
                }
            }
            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                label = { Text("笔记（可选）") },
                modifier = Modifier.fillMaxWidth(),
            )
            Row(
                Modifier.align(Alignment.End),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                TextButton(onClick = onDismiss) { Text("取消") }
                Button(onClick = { onSave(bedTime, wakeTime, note) }) { Text("保存") }
            }
        }
    }
}

@Composable
private fun TimePickDialog(
    title: String,
    initial: LocalTime,
    onConfirm: (LocalTime) -> Unit,
    onDismiss: () -> Unit,
) {
    val state = rememberTimePickerState(
        initialHour = initial.hour,
        initialMinute = initial.minute,
        is24Hour = true,
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { TimePicker(state) },
        confirmButton = {
            TextButton(onClick = { onConfirm(LocalTime.of(state.hour, state.minute)) }) { Text("确定") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        },
    )
}

// ---------------------------------------------------------------------------
// 首次启动示例数据（30 晚 SAMPLE 来源）
// ---------------------------------------------------------------------------

private suspend fun seedDemoRecords(dao: SleepRecordDao) {
    val zone = ZoneId.systemDefault()
    val today = LocalDate.now(zone)
    val random = Random(20260402)
    (29 downTo 0).forEach { back ->
        val endDay = today.minusDays(back.toLong())
        val totalMin = 390 + random.nextInt(121) // 6.5 ~ 8.5 小时
        val deepMin = (totalMin * (0.15 + random.nextDouble() * 0.05)).toInt()
        val remMin = (totalMin * (0.20 + random.nextDouble() * 0.05)).toInt()
        val awakeMin = 6 + random.nextInt(12)
        val lightMin = totalMin - deepMin - remMin - awakeMin
        val lightPart = (lightMin / 5).coerceAtLeast(1)
        val chunks = listOf(
            "light" to lightPart,
            "deep" to deepMin / 2,
            "light" to lightPart,
            "awake" to awakeMin,
            "light" to lightPart,
            "rem" to remMin / 2,
            "light" to lightPart,
            "deep" to deepMin - deepMin / 2,
            "light" to (lightMin - lightPart * 4).coerceAtLeast(0),
            "rem" to remMin - remMin / 2,
        )
        val bedMinute = 22 * 60 + 30 + random.nextLong(-60, 91)
        val bedDateTime = endDay.minusDays(1).atStartOfDay().plusMinutes(bedMinute)
        val start: Instant = bedDateTime.atZone(zone).toInstant()
        val end: Instant = start.plusSeconds(totalMin * 60L)
        var cursor = start.toEpochMilli()
        val segments = chunks.mapNotNull { (stage, minutes) ->
            if (minutes <= 0) return@mapNotNull null
            val seg = SleepSegment(stage, cursor, cursor + minutes * 60_000L)
            cursor += minutes * 60_000L
            seg
        }
        val hearts = (0 until totalMin step 20).map { offset ->
            HeartSample(start.plusSeconds(offset * 60L).toEpochMilli(), 56.0 + random.nextInt(14))
        }
        val record = SleepRecord(
            id = java.util.UUID.randomUUID().toString(),
            start = start,
            end = end,
            zoneId = zone,
            source = SleepSource.SAMPLE,
            segments = segments,
            heartSamples = hearts,
            averageHeartRate = hearts.takeIf { it.isNotEmpty() }?.map { it.bpm }?.average(),
            averageSpO2 = 96.5 + random.nextDouble() * 1.5,
            averageRespiratoryRate = null,
            note = "示例数据，仅用于演示",
            metadata = SleepMetadata(),
        )
        dao.upsert(SleepRecordMapper.toEntity(record))
    }
}
