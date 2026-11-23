@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.rocgrey.sleeptongshu.ui.sleep

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.rocgrey.sleeptongshu.core.sleep.HeartSample
import com.rocgrey.sleeptongshu.core.sleep.SleepSegment
import com.rocgrey.sleeptongshu.core.sleep.SleepStage
import com.rocgrey.sleeptongshu.ui.theme.LocalSleepPalette
import com.rocgrey.sleeptongshu.ui.theme.SleepPalette
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

// ---------------------------------------------------------------------------
// 共享小工具
// ---------------------------------------------------------------------------

/** 分钟数转「X小时Y分 / Y分钟」。 */
internal fun formatDuration(totalMinutes: Int): String {
    val m = totalMinutes.coerceAtLeast(0)
    val h = m / 60
    val min = m % 60
    return if (h > 0) "${h}小时${min}分" else "${min}分钟"
}

/** 目标小时数转「8小时 / 7.5小时」。 */
internal fun formatGoal(hours: Float): String =
    if (hours == hours.toInt().toFloat()) "${hours.toInt()}小时"
    else String.format(Locale.CHINESE, "%.1f小时", hours)

/** 阶段在时间线中的行层级：清醒最高，深睡最低。 */
private fun stageLevel(stage: SleepStage): Int = when (stage) {
    SleepStage.AWAKE, SleepStage.IN_BED -> 0
    SleepStage.REM -> 1
    SleepStage.LIGHT, SleepStage.UNSPECIFIED -> 2
    SleepStage.DEEP, SleepStage.UNOBSERVED -> 3
}

/** 阶段颜色：深睡 deep / 浅睡 mint / 做梦 rem / 清醒 awake / 其他 muted。 */
private fun stageColor(stage: SleepStage, palette: SleepPalette): Color = when (stage) {
    SleepStage.AWAKE, SleepStage.IN_BED -> palette.awake
    SleepStage.REM -> palette.rem
    SleepStage.LIGHT -> palette.mint
    SleepStage.DEEP -> palette.deep
    SleepStage.UNSPECIFIED, SleepStage.UNOBSERVED -> palette.muted
}

private const val TIMELINE_LEVELS = 4

/** 图例小圆点 + 文本。 */
@Composable
internal fun LegendDot(color: Color, label: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier
                .size(9.dp)
                .clip(CircleShape)
                .background(color),
        )
        Spacer(Modifier.width(5.dp))
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = LocalSleepPalette.current.muted,
        )
    }
}

/** 与 iOS 分段控件一致的手写分段条（无新增依赖）。 */
@Composable
internal fun TongshuSegmented(
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalSleepPalette.current
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = palette.line.copy(alpha = 0.55f),
    ) {
        Row(Modifier.padding(3.dp)) {
            options.forEachIndexed { index, label ->
                val selected = index == selectedIndex
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(9.dp))
                        .background(if (selected) palette.teal else Color.Transparent)
                        .clickable { onSelect(index) }
                        .padding(vertical = 8.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        label,
                        style = MaterialTheme.typography.labelLarge,
                        color = if (selected) Color.White else palette.ink,
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// StageTimeline：分段水平时间线，点击段查看详情
// ---------------------------------------------------------------------------

@Composable
fun StageTimeline(
    segments: List<SleepSegment>,
    start: Long,
    end: Long,
    modifier: Modifier = Modifier,
) {
    val palette = LocalSleepPalette.current
    var selected by remember { mutableStateOf<SleepSegment?>(null) }
    val duration = (end - start).coerceAtLeast(1L)
    val timeFmt = DateTimeFormatter.ofPattern("HH:mm")

    Column(modifier) {
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(92.dp)
                .pointerInput(segments, start, end) {
                    detectTapGestures { offset ->
                        val w = size.width.toFloat()
                        val pad = 4.dp.toPx()
                        val rowH = (size.height - 8.dp.toPx()) / TIMELINE_LEVELS
                        val rel = ((offset.x - pad) / (w - pad * 2)).coerceIn(0f, 1f)
                        val ms = start + (rel * duration).toLong()
                        val row = (((offset.y - 4.dp.toPx()) / rowH).toInt()).coerceIn(0, TIMELINE_LEVELS - 1)
                        selected = segments.firstOrNull {
                            ms >= it.start && ms <= it.end && stageLevel(it.stageEnum) == row
                        }
                    }
                },
        ) {
            val w = size.width
            val h = size.height
            val pad = 4.dp.toPx()
            val rowH = (h - pad * 2) / TIMELINE_LEVELS
            // 背景行
            for (i in 0 until TIMELINE_LEVELS) {
                drawRect(
                    color = palette.line.copy(alpha = 0.35f),
                    topLeft = Offset(pad, pad + i * rowH),
                    size = Size(w - pad * 2, rowH - 2.dp.toPx()),
                )
            }
            segments.forEach { seg ->
                val s0 = ((seg.start - start).toFloat() / duration).coerceIn(0f, 1f)
                val s1 = ((seg.end - start).toFloat() / duration).coerceIn(0f, 1f)
                val level = stageLevel(seg.stageEnum)
                drawRoundRect(
                    color = stageColor(seg.stageEnum, palette),
                    topLeft = Offset(pad + s0 * (w - pad * 2), pad + level * rowH + 1.dp.toPx()),
                    size = Size(
                        ((s1 - s0) * (w - pad * 2)).coerceAtLeast(2.dp.toPx()),
                        (rowH - 4.dp.toPx()).coerceAtLeast(2.dp.toPx()),
                    ),
                    cornerRadius = CornerRadius(4.dp.toPx()),
                )
            }
        }
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                timeFmt.format(Instant.ofEpochMilli(start).atZone(ZoneId.systemDefault())),
                style = MaterialTheme.typography.labelSmall,
                color = palette.muted,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                LegendDot(palette.awake, "清醒")
                LegendDot(palette.rem, "做梦")
                LegendDot(palette.mint, "浅睡")
                LegendDot(palette.deep, "深睡")
            }
            Text(
                timeFmt.format(Instant.ofEpochMilli(end).atZone(ZoneId.systemDefault())),
                style = MaterialTheme.typography.labelSmall,
                color = palette.muted,
            )
        }
    }

    selected?.let { seg ->
        val minutes = (((seg.end - seg.start) / 60000L)).toInt()
        ModalBottomSheet(onDismissRequest = { selected = null }) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier
                            .size(11.dp)
                            .clip(CircleShape)
                            .background(stageColor(seg.stageEnum, palette)),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        seg.stageEnum.label,
                        style = MaterialTheme.typography.titleMedium,
                        color = palette.ink,
                    )
                }
                Text(
                    "时段：" +
                        timeFmt.format(Instant.ofEpochMilli(seg.start).atZone(ZoneId.systemDefault())) +
                        " – " +
                        timeFmt.format(Instant.ofEpochMilli(seg.end).atZone(ZoneId.systemDefault())),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.ink,
                )
                Text(
                    "时长：${formatDuration(minutes)}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.ink,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// SleepStageBalance：环形占比图，中心显示总时长
// ---------------------------------------------------------------------------

@Composable
fun SleepStageBalance(
    deepMinutes: Int,
    lightMinutes: Int,
    remMinutes: Int,
    modifier: Modifier = Modifier,
) {
    val palette = LocalSleepPalette.current
    val total = deepMinutes + lightMinutes + remMinutes
    Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(modifier = Modifier.size(132.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.size(132.dp)) {
                val stroke = 16.dp.toPx()
                val inset = stroke / 2 + 2.dp.toPx()
                val arcSize = Size(size.width - inset * 2, size.height - inset * 2)
                val topLeft = Offset(inset, inset)
                if (total <= 0) {
                    drawArc(
                        color = palette.line,
                        startAngle = 0f,
                        sweepAngle = 360f,
                        useCenter = false,
                        topLeft = topLeft,
                        size = arcSize,
                        style = Stroke(width = stroke),
                    )
                } else {
                    var angle = -90f
                    listOf(
                        Triple(palette.deep, deepMinutes),
                        Triple(palette.rem, remMinutes),
                        Triple(palette.mint, lightMinutes),
                    ).forEach { (color, minutes) ->
                        if (minutes > 0) {
                            val sweep = 360f * minutes / total
                            drawArc(
                                color = color,
                                startAngle = angle,
                                sweepAngle = sweep,
                                useCenter = false,
                                topLeft = topLeft,
                                size = arcSize,
                                style = Stroke(width = stroke),
                            )
                            angle += sweep
                        }
                    }
                }
            }
            Text(
                formatDuration(total),
                style = MaterialTheme.typography.titleSmall,
                color = palette.ink,
            )
        }
        Spacer(Modifier.width(18.dp))
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            BalanceLegendRow(palette.deep, "深睡", deepMinutes, total)
            BalanceLegendRow(palette.rem, "做梦", remMinutes, total)
            BalanceLegendRow(palette.mint, "浅睡", lightMinutes, total)
        }
    }
}

@Composable
private fun BalanceLegendRow(color: Color, label: String, minutes: Int, total: Int) {
    val palette = LocalSleepPalette.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier
                .size(9.dp)
                .clip(CircleShape)
                .background(color),
        )
        Spacer(Modifier.width(6.dp))
        val pct = if (total > 0) minutes * 100 / total else 0
        Text(
            "$label $minutes 分 · $pct%",
            style = MaterialTheme.typography.bodySmall,
            color = palette.ink,
        )
    }
}

// ---------------------------------------------------------------------------
// HeartRateChart：面积 + 折线，Y 轴 40 到 max(bpm+5, 85)
// ---------------------------------------------------------------------------

@Composable
fun HeartRateChart(
    samples: List<HeartSample>,
    average: Double?,
    modifier: Modifier = Modifier,
) {
    val palette = LocalSleepPalette.current
    val sorted = remember(samples) { samples.sortedBy { it.at } }
    if (sorted.isEmpty()) {
        Text(
            "暂无心率样本",
            style = MaterialTheme.typography.bodySmall,
            color = palette.muted,
            modifier = modifier,
        )
        return
    }
    val minT = sorted.first().at.toFloat()
    val maxT = sorted.last().at.toFloat()
    val spanT = (maxT - minT).coerceAtLeast(60_000f)
    val yMin = 40f
    val yMax = (sorted.maxOf { it.bpm } + 5.0).coerceAtLeast(85.0).toFloat()
    val yMid = (yMin + yMax) / 2f

    Column(modifier) {
        Row(Modifier.fillMaxWidth().height(140.dp)) {
            Column(
                Modifier
                    .width(30.dp)
                    .fillMaxHeight(),
                verticalArrangement = Arrangement.SpaceBetween,
                horizontalAlignment = Alignment.End,
            ) {
                Text("${yMax.toInt()}", style = MaterialTheme.typography.labelSmall, color = palette.muted)
                Text("${yMid.toInt()}", style = MaterialTheme.typography.labelSmall, color = palette.muted)
                Text("${yMin.toInt()}", style = MaterialTheme.typography.labelSmall, color = palette.muted)
            }
            Canvas(Modifier.weight(1f).fillMaxHeight()) {
                val w = size.width
                val top = 8.dp.toPx()
                val bottom = size.height - 8.dp.toPx()
                fun px(t: Float) = ((t - minT) / spanT) * w
                fun py(b: Float) = bottom - ((b.coerceIn(yMin, yMax) - yMin) / (yMax - yMin)) * (bottom - top)
                listOf(yMin, yMid, yMax).forEach { grid ->
                    drawLine(palette.line, Offset(0f, py(grid)), Offset(w, py(grid)), strokeWidth = 1.dp.toPx())
                }
                val line = Path()
                sorted.forEachIndexed { i, s ->
                    val x = px(s.at.toFloat())
                    val y = py(s.bpm.toFloat())
                    if (i == 0) line.moveTo(x, y) else line.lineTo(x, y)
                }
                val area = Path().apply {
                    addPath(line)
                    lineTo(px(maxT), bottom)
                    lineTo(px(minT), bottom)
                    close()
                }
                drawPath(area, palette.rose.copy(alpha = 0.22f))
                drawPath(line, palette.rose, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
                average?.let { avg ->
                    drawLine(
                        palette.teal,
                        Offset(0f, py(avg.toFloat())),
                        Offset(w, py(avg.toFloat())),
                        strokeWidth = 1.5f.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 8f)),
                    )
                }
            }
        }
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            LegendDot(palette.rose, "夜间心率")
            average?.let { LegendDot(palette.teal, "平均 ${it.roundToInt()} 次/分") }
        }
    }
}

// ---------------------------------------------------------------------------
// SleepTrendChart：按日柱图（时长 / 效率 / 深睡），目标虚线
// ---------------------------------------------------------------------------

/** 与 iOS 趋势页三个指标对应。 */
enum class TrendMetric(val label: String) {
    DURATION("时长"),
    EFFICIENCY("效率"),
    DEEP("深睡"),
}

/** 单日趋势值；null 表示该日无有效数据（缺失，不冒充 0）。 */
data class TrendDay(
    val date: java.time.LocalDate,
    val minutes: Double?,
    val efficiency: Double?,
    val deepMinutes: Double?,
)

@Composable
fun SleepTrendChart(
    days: List<TrendDay>,
    metric: TrendMetric,
    goalHours: Float,
    modifier: Modifier = Modifier,
) {
    val palette = LocalSleepPalette.current
    Column(modifier) {
        Canvas(Modifier.fillMaxWidth().height(170.dp)) {
            val n = days.size.coerceAtLeast(1)
            val slot = size.width / n
            val top = 10.dp.toPx()
            val bottom = size.height - 8.dp.toPx()
            val values = days.map { day ->
                when (metric) {
                    TrendMetric.DURATION -> day.minutes?.div(60.0)
                    TrendMetric.EFFICIENCY -> day.efficiency?.div(100.0)
                    TrendMetric.DEEP -> day.deepMinutes?.div(60.0)
                }
            }
            val scaleMax = when (metric) {
                TrendMetric.EFFICIENCY -> 1.0
                TrendMetric.DURATION ->
                    maxOf(values.filterNotNull().maxOrNull() ?: 0.0, goalHours.toDouble()) * 1.15
                TrendMetric.DEEP ->
                    maxOf(values.filterNotNull().maxOrNull() ?: 0.0, 0.5) * 1.15
            }.coerceAtLeast(0.5)
            values.forEachIndexed { i, v ->
                val cx = slot * i + slot / 2
                if (v == null) {
                    drawLine(
                        palette.line,
                        Offset(cx, bottom),
                        Offset(cx, bottom - 4.dp.toPx()),
                        strokeWidth = 2.dp.toPx(),
                    )
                } else {
                    val ratio = (v / scaleMax).coerceIn(0.01, 1.0).toFloat()
                    val barH = (bottom - top) * ratio
                    drawRoundRect(
                        color = palette.teal,
                        topLeft = Offset(cx - slot * 0.32f, bottom - barH),
                        size = Size(slot * 0.64f, barH),
                        cornerRadius = CornerRadius(3.dp.toPx()),
                    )
                }
            }
            if (metric == TrendMetric.DURATION) {
                val gy = bottom - ((goalHours / scaleMax).coerceIn(0.0, 1.0).toFloat() * (bottom - top))
                drawLine(
                    palette.rose,
                    Offset(0f, gy),
                    Offset(size.width, gy),
                    strokeWidth = 1.5f.dp.toPx(),
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 8f)),
                )
            }
        }
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                days.firstOrNull()?.let { "${it.date.monthValue}/${it.date.dayOfMonth}" } ?: "",
                style = MaterialTheme.typography.labelSmall,
                color = palette.muted,
            )
            Text(
                when (metric) {
                    TrendMetric.DURATION -> "虚线：目标 ${formatGoal(goalHours)}"
                    TrendMetric.EFFICIENCY -> "效率按 0–100% 展示"
                    TrendMetric.DEEP -> "每日深睡时长"
                },
                style = MaterialTheme.typography.labelSmall,
                color = palette.muted,
            )
            Text(
                days.lastOrNull()?.let { "${it.date.monthValue}/${it.date.dayOfMonth}" } ?: "",
                style = MaterialTheme.typography.labelSmall,
                color = palette.muted,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// SleepRegularityChart：每晚入睡→结束水平条，X 轴 0–24 点，凌晨段折叠到左侧
// ---------------------------------------------------------------------------

/**
 * nights：每项为 (入睡分钟, 结束分钟)。
 * 结束若在次日，结束分钟应加上 1440（如图表会把超过 1440 的部分折叠到 0 点之后）。
 */
@Composable
fun SleepRegularityChart(
    nights: List<Pair<Int, Int>>,
    modifier: Modifier = Modifier,
) {
    val palette = LocalSleepPalette.current
    if (nights.isEmpty()) {
        Text(
            "暂无规律性数据",
            style = MaterialTheme.typography.bodySmall,
            color = palette.muted,
            modifier = modifier,
        )
        return
    }
    Column(modifier) {
        Canvas(
            Modifier
                .fillMaxWidth()
                .height((nights.size * 11).dp.coerceAtMost(240.dp)),
        ) {
            val padH = 2.dp.toPx()
            val w = size.width - padH * 2
            val rowH = size.height / nights.size
            val barH = (rowH - 3.dp.toPx()).coerceAtLeast(2.dp.toPx())
            fun px(minute: Float) = padH + (minute / 1440f) * w
            listOf(0, 360, 720, 1080, 1440).forEach { m ->
                drawLine(
                    palette.line,
                    Offset(px(m.toFloat()), 0f),
                    Offset(px(m.toFloat()), size.height),
                    strokeWidth = 1.dp.toPx(),
                )
            }
            nights.forEachIndexed { i, night ->
                val (startMin, endMin) = night
                val y = rowH * i + (rowH - barH) / 2
                val s = startMin.coerceIn(0, 1440)
                val e = endMin.coerceIn(0, 2160)
                if (e > 1440) {
                    // 跨日：前半夜 + 折叠到 0 点之后的凌晨段
                    drawRoundRect(
                        color = palette.mint,
                        topLeft = Offset(px(s.toFloat()), y),
                        size = Size((px(1440f) - px(s.toFloat())).coerceAtLeast(1.dp.toPx()), barH),
                        cornerRadius = CornerRadius(2.dp.toPx()),
                    )
                    drawRoundRect(
                        color = palette.mint,
                        topLeft = Offset(px(0f), y),
                        size = Size(px((e - 1440).toFloat()).coerceAtLeast(1.dp.toPx()), barH),
                        cornerRadius = CornerRadius(2.dp.toPx()),
                    )
                } else {
                    drawRoundRect(
                        color = palette.mint,
                        topLeft = Offset(px(s.toFloat()), y),
                        size = Size((px(e.toFloat()) - px(s.toFloat())).coerceAtLeast(1.dp.toPx()), barH),
                        cornerRadius = CornerRadius(2.dp.toPx()),
                    )
                }
            }
        }
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            listOf("0点", "6点", "12点", "18点", "24点").forEach { label ->
                Text(label, style = MaterialTheme.typography.labelSmall, color = palette.muted)
            }
        }
    }
}
