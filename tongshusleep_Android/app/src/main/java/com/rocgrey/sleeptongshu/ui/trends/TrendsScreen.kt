package com.rocgrey.sleeptongshu.ui.trends

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rocgrey.sleeptongshu.AppContainer
import com.rocgrey.sleeptongshu.LocalAppContainer
import com.rocgrey.sleeptongshu.core.data.DeviceStepEntity
import com.rocgrey.sleeptongshu.core.sleep.SleepRecord
import com.rocgrey.sleeptongshu.core.sleep.SleepRecordMapper
import com.rocgrey.sleeptongshu.core.sleep.SleepSource
import com.rocgrey.sleeptongshu.core.sleep.SleepStage
import com.rocgrey.sleeptongshu.core.steps.StepSync
import com.rocgrey.sleeptongshu.core.steps.StepsSection
import com.rocgrey.sleeptongshu.core.steps.StepsSnapshot
import com.rocgrey.sleeptongshu.ui.sleep.SleepRegularityChart
import com.rocgrey.sleeptongshu.ui.sleep.SleepTrendChart
import com.rocgrey.sleeptongshu.ui.sleep.TrendDay
import com.rocgrey.sleeptongshu.ui.sleep.TrendMetric
import com.rocgrey.sleeptongshu.ui.sleep.TongshuSegmented
import com.rocgrey.sleeptongshu.ui.sleep.formatDuration
import com.rocgrey.sleeptongshu.ui.theme.LocalSleepPalette
import kotlinx.coroutines.flow.map
import java.time.LocalDate
import kotlin.math.roundToInt

private val timeFmt = java.time.format.DateTimeFormatter.ofPattern("HH:mm")

@Composable
fun TrendsScreen() {
    val container = LocalAppContainer.current
    val palette = LocalSleepPalette.current
    val dao = container.database.sleepRecordDao()

    val records by dao.observeAll()
        .map { list -> list.map(SleepRecordMapper::toDomain) }
        .collectAsStateWithLifecycle(initialValue = emptyList<SleepRecord>())
    val goalHours by container.preferences.sleepGoalHours.collectAsStateWithLifecycle(initialValue = 8f)
    val deviceSteps by dao.deviceStepDao().observeAll()
        .collectAsStateWithLifecycle(initialValue = emptyList<DeviceStepEntity>())

    var sectionIndex by remember { mutableStateOf(0) }

    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("趋势", style = MaterialTheme.typography.titleLarge, color = palette.teal)
        TongshuSegmented(
            options = listOf("睡眠", "步数"),
            selectedIndex = sectionIndex,
            onSelect = { sectionIndex = it },
        )
        if (sectionIndex == 0) {
            SleepTrendsSection(records = records, goalHours = goalHours)
        } else {
            StepsTrendsSection(container = container, deviceSteps = deviceSteps)
        }
        Spacer(Modifier.height(8.dp))
    }
}

// ---------------------------------------------------------------------------
// 睡眠趋势
// ---------------------------------------------------------------------------

@Composable
private fun SleepTrendsSection(records: List<SleepRecord>, goalHours: Float) {
    val palette = LocalSleepPalette.current
    val today = remember { LocalDate.now() }
    var days by remember { mutableStateOf(7) }
    var metricIndex by remember { mutableStateOf(0) }
    var sourceIndex by remember { mutableStateOf(0) }
    var selectedDay by remember { mutableStateOf<LocalDate?>(null) }

    TongshuSegmented(
        options = listOf("近 7 天", "近 30 天"),
        selectedIndex = if (days == 7) 0 else 1,
        onSelect = { days = if (it == 0) 7 else 30 },
    )
    TongshuSegmented(
        options = listOf("全部", "设备", "系统健康", "手动"),
        selectedIndex = sourceIndex,
        onSelect = { sourceIndex = it },
    )

    val filtered = records.filter { sleepSourceMatches(it.source, sourceIndex) }
    val byDay = filtered.groupBy { it.day }
    val rangeStart = today.minusDays((days - 1).toLong())

    val metric = TrendMetric.entries[metricIndex]
    TongshuSegmented(
        options = TrendMetric.entries.map { it.label },
        selectedIndex = metricIndex,
        onSelect = { metricIndex = it },
    )

    val trendDays = (days - 1 downTo 0).map { back ->
        val date = today.minusDays(back.toLong())
        val recs = byDay[date].orEmpty()
        val minutes = recs.takeIf { it.isNotEmpty() }
            ?.sumOf { it.asleepMinutes }?.toDouble()?.takeIf { it > 0.0 }
        val effList = recs.mapNotNull { it.efficiency }
        val efficiency = effList
            .takeIf { recs.isNotEmpty() && effList.size == recs.size }
            ?.average()
        val stagedAvailable = recs.all {
            it.minutesOf(setOf(SleepStage.DEEP, SleepStage.REM, SleepStage.LIGHT)) > 0
        }
        val deep = recs.takeIf { it.isNotEmpty() && stagedAvailable }
            ?.sumOf { it.minutesOf(setOf(SleepStage.DEEP)) }?.toDouble()?.takeIf { it > 0.0 }
        TrendDay(date = date, minutes = minutes, efficiency = efficiency, deepMinutes = deep)
    }
    SleepTrendChart(days = trendDays, metric = metric, goalHours = goalHours)

    // 规律性：每晚入睡→结束
    val nights = byDay.entries
        .filter { it.key in rangeStart..today }
        .sortedBy { it.key }
        .mapNotNull { (_, recs) ->
            val record = recs.maxByOrNull { it.asleepMinutes } ?: recs.first()
            val onset = record.sleepOnset ?: record.start
            val endT = record.sleepEnd ?: record.end
            val s = onset.atZone(record.zoneId)
            val e = endT.atZone(record.zoneId)
            val startMin = s.hour * 60 + s.minute
            val endMin = e.hour * 60 + e.minute +
                if (e.toLocalDate().isAfter(s.toLocalDate())) 1440 else 0
            startMin to endMin
        }
    Text("入睡规律", style = MaterialTheme.typography.titleSmall, color = palette.ink)
    SleepRegularityChart(nights = nights)

    // 每日明细行
    Text("每日明细", style = MaterialTheme.typography.titleSmall, color = palette.ink)
    val visibleDays = byDay.entries
        .filter { it.key in rangeStart..today }
        .sortedByDescending { it.key }
    if (visibleDays.isEmpty()) {
        EmptyCard("这个时间段还没有睡眠记录。记录会随设备同步或手动录入自动出现在这里。")
    } else {
        visibleDays.forEach { (date, recs) ->
            val totalMinutes = recs.sumOf { it.asleepMinutes }
            val eff = recs.mapNotNull { it.efficiency }
                .takeIf { it.size == recs.size && recs.isNotEmpty() }?.average()?.roundToInt()
            Surface(
                shape = RoundedCornerShape(12.dp),
                color = palette.surface,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { selectedDay = if (selectedDay == date) null else date },
            ) {
                Row(
                    Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            "${date.monthValue}/${date.dayOfMonth}",
                            style = MaterialTheme.typography.bodyMedium,
                            color = palette.ink,
                        )
                        Text(
                            "${recs.size} 条记录",
                            style = MaterialTheme.typography.labelSmall,
                            color = palette.muted,
                        )
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text(
                            formatDuration(totalMinutes),
                            style = MaterialTheme.typography.bodyMedium,
                            color = palette.ink,
                        )
                        Text(
                            eff?.let { "效率 $it%" } ?: "效率 —",
                            style = MaterialTheme.typography.labelSmall,
                            color = palette.muted,
                        )
                    }
                }
            }
            // 点击展开的详情卡
            if (selectedDay == date) {
                DayDetailCard(records = recs)
            }
        }
    }
}

@Composable
private fun DayDetailCard(records: List<SleepRecord>) {
    val palette = LocalSleepPalette.current
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = palette.surface,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
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
                        "入睡 ${formatDuration(record.asleepMinutes)} · " +
                            "深睡 ${record.minutesOf(setOf(SleepStage.DEEP))} 分 · " +
                            "做梦 ${record.minutesOf(setOf(SleepStage.REM))} 分 · " +
                            "清醒 ${record.awakeMinutes} 分",
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.muted,
                    )
                    record.efficiency?.let {
                        Text(
                            "效率 ${it.roundToInt()}%",
                            style = MaterialTheme.typography.bodySmall,
                            color = palette.muted,
                        )
                    }
                    record.metadata.aisScore?.let {
                        Text(
                            "AIS 总分 $it",
                            style = MaterialTheme.typography.bodySmall,
                            color = palette.muted,
                        )
                    }
                    record.note?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall, color = palette.muted)
                    }
                }
            }
        }
    }
}

private fun sleepSourceMatches(source: SleepSource, index: Int): Boolean = when (index) {
    1 -> source == SleepSource.BAND
    2 -> source == SleepSource.HEALTH_CONNECT
    3 -> source == SleepSource.MANUAL
    else -> true
}

// ---------------------------------------------------------------------------
// 步数趋势
// ---------------------------------------------------------------------------

@Composable
private fun StepsTrendsSection(
    container: AppContainer,
    deviceSteps: List<DeviceStepEntity>,
) {
    val palette = LocalSleepPalette.current
    val context = LocalContext.current
    val accountState by container.accountStore.state.collectAsStateWithLifecycle()
    var days by remember { mutableStateOf(7) }
    var sectionIndex by remember { mutableStateOf(0) }
    val today = remember { LocalDate.now() }

    TongshuSegmented(
        options = listOf("近 7 天", "近 30 天"),
        selectedIndex = if (days == 7) 0 else 1,
        onSelect = { days = if (it == 0) 7 else 30 },
    )
    TongshuSegmented(
        options = StepsSection.entries.map { it.label },
        selectedIndex = sectionIndex,
        onSelect = { sectionIndex = it },
    )

    when (StepsSection.entries[sectionIndex]) {
        StepsSection.DEVICE -> {
            val deviceByDay = remember(deviceSteps) {
                deviceSteps.mapNotNull { entity ->
                    runCatching { LocalDate.parse(entity.day) }.getOrNull()?.let { it to entity }
                }.groupBy(keySelector = { it.first }, valueTransform = { it.second })
            }
            val values = (0 until days).map { back ->
                deviceByDay[today.minusDays(back.toLong())]?.sumOf { it.steps }
            }
            val realZero = values.map { it == 0 } // 设备读数为 0 视为真 0
            val recorded = values.filterNotNull()
            if (recorded.isEmpty()) {
                EmptyCard("还没有蓝牙设备步数记录。连接手环并读取步数后，这里会自动汇总。")
            } else {
                StepsStatsText(values = values, realZero = realZero, days = days)
                StepsBarChart(values = values, realZero = realZero)
            }
        }
        StepsSection.CLOUD -> {
            val stepSync = remember { StepSync(context.applicationContext) { container.apiClient } }
            var snapshot by remember { mutableStateOf<StepsSnapshot?>(null) }
            LaunchedEffect(accountState) {
                snapshot = stepSync.readCache(container.accountStore.userScope())
            }
            val snap = snapshot
            val dayMap = remember(snap) {
                snap?.days?.mapNotNull { row ->
                    runCatching { LocalDate.parse(row.recordDate) }.getOrNull()?.let { it to row }
                }?.toMap()
            }
            val values = (0 until days).map { back ->
                dayMap?.get(today.minusDays(back.toLong()))?.steps
            }
            val realZero = (0 until days).map { back ->
                dayMap?.get(today.minusDays(back.toLong()))?.isRealZero ?: false
            }
            val recorded = values.filterNotNull()
            if (snap == null || recorded.isEmpty()) {
                EmptyCard("还没有账号云端步数数据。登录账号并完成一次同步后，这里会展示缓存的云端步数。")
            } else {
                StepsStatsText(values = values, realZero = realZero, days = days)
                StepsBarChart(values = values, realZero = realZero)
            }
        }
        StepsSection.HEALTH -> {
            // 系统健康（Health Connect）数据由健康模块负责采集，这里只显示占位，不伪造数据。
            EmptyCard("暂无数据：系统健康（Health Connect）步数由健康模块采集，接入后这里会自动展示。")
        }
    }
}

@Composable
private fun StepsStatsText(values: List<Int?>, realZero: List<Boolean>, days: Int) {
    val palette = LocalSleepPalette.current
    val recorded = values.filterNotNull()
    val total = recorded.sum()
    val avg = if (recorded.isNotEmpty()) total.toDouble() / recorded.size else null
    val zeroDays = realZero.count { it }
    Text(
        "近 $days 天累计 $total 步 · 有记录日均 ${avg?.roundToInt() ?: 0} 步 · 真 0 天 $zeroDays 天",
        style = MaterialTheme.typography.bodySmall,
        color = palette.ink,
    )
}

@Composable
private fun StepsBarChart(values: List<Int?>, realZero: List<Boolean>) {
    val palette = LocalSleepPalette.current
    val maxV = (values.filterNotNull().maxOrNull() ?: 0).coerceAtLeast(1000)
    Column {
        Canvas(Modifier.fillMaxWidth().height(160.dp)) {
            val n = values.size.coerceAtLeast(1)
            val slot = size.width / n
            val top = 10.dp.toPx()
            val bottom = size.height - 6.dp.toPx()
            values.forEachIndexed { i, v ->
                val cx = slot * i + slot / 2
                if (v == null) {
                    // 缺失日：只画底部小刻度，不冒充 0
                    drawLine(
                        palette.line,
                        Offset(cx, bottom),
                        Offset(cx, bottom - 4.dp.toPx()),
                        strokeWidth = 2.dp.toPx(),
                    )
                } else {
                    val ratio = (v / maxV.toFloat()).coerceIn(0.008f, 1f)
                    val barH = (bottom - top) * ratio
                    drawRoundRect(
                        color = palette.teal,
                        topLeft = Offset(cx - slot * 0.3f, bottom - barH),
                        size = Size(slot * 0.6f, barH),
                        cornerRadius = CornerRadius(4.dp.toPx()),
                    )
                    if (realZero.getOrElse(i) { false }) {
                        drawCircle(
                            color = Color(0xFFD64545),
                            radius = 3.dp.toPx(),
                            center = Offset(cx, bottom - barH - 8.dp.toPx()),
                        )
                    }
                }
            }
        }
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text("共 ${values.size} 天", style = MaterialTheme.typography.labelSmall, color = palette.muted)
            Text(
                "峰值 ${values.filterNotNull().maxOrNull() ?: 0} 步",
                style = MaterialTheme.typography.labelSmall,
                color = palette.muted,
            )
        }
    }
}

@Composable
private fun EmptyCard(message: String) {
    val palette = LocalSleepPalette.current
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = palette.surface,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(
            message,
            Modifier.padding(16.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.muted,
        )
    }
}
