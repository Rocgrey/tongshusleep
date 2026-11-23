package com.rocgrey.sleeptongshu.ui.health

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.rocgrey.sleeptongshu.LocalRootNav
import com.rocgrey.sleeptongshu.core.health.HealthSnapshot
import com.rocgrey.sleeptongshu.core.health.METRIC_META
import com.rocgrey.sleeptongshu.core.health.HealthOverview
import com.rocgrey.sleeptongshu.core.health.SnapshotStore
import com.rocgrey.sleeptongshu.ui.theme.LocalSleepPalette
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/** 指标详情：趋势折线 + 统计 + 90 天覆盖日历。 */
@Composable
fun HealthMetricDetailScreen(metricId: String) {
    val context = LocalContext.current
    val palette = LocalSleepPalette.current
    val nav = LocalRootNav.current
    var snapshot by remember { mutableStateOf<HealthSnapshot?>(null) }
    var rangeDays by remember { mutableIntStateOf(30) }

    LaunchedEffect(Unit) {
        snapshot = SnapshotStore.readSnapshot(context)
    }

    val meta = METRIC_META.firstOrNull { it.id == metricId }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { nav.popBackStack() }) {
                Icon(Icons.Filled.ArrowBack, contentDescription = "返回")
            }
            Text(
                meta?.name ?: "未知指标",
                style = MaterialTheme.typography.titleLarge,
            )
        }

        if (meta == null) {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text("未识别的指标", style = MaterialTheme.typography.titleMedium)
                    Text("指标编号：$metricId", style = MaterialTheme.typography.bodySmall)
                    Text("请返回健康总览重新选择。", style = MaterialTheme.typography.bodySmall)
                }
            }
            return
        }

        Text(
            "单位：${meta.unit.ifEmpty { "无量纲" }}",
            style = MaterialTheme.typography.bodySmall,
        )
        Text(
            meta.description,
            style = MaterialTheme.typography.bodySmall,
            color = palette.muted,
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(7 to "7 天", 30 to "30 天", 90 to "90 天").forEach { (days, label) ->
                TextButton(
                    onClick = { rangeDays = days },
                    enabled = rangeDays != days,
                ) {
                    Text(if (rangeDays == days) "● $label" else label)
                }
            }
        }

        val series = snapshot?.series?.get(metricId)
        if (series == null || series.days.isEmpty()) {
            Card(modifier = Modifier.fillMaxWidth()) {
                Text(
                    "暂无数据，请先在健康总览页从系统健康读取。",
                    modifier = Modifier.padding(16.dp),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            return
        }

        val today = LocalDate.now()
        val windowStart = today.minusDays((rangeDays - 1).toLong())
        val days = series.days.filter { it.date >= windowStart && it.date <= today }
        if (days.isEmpty()) {
            Card(modifier = Modifier.fillMaxWidth()) {
                Text(
                    "近 $rangeDays 天没有数据。",
                    modifier = Modifier.padding(16.dp),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            return
        }

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("近 $rangeDays 天趋势", style = MaterialTheme.typography.titleSmall)
                Canvas(
                    modifier = Modifier.fillMaxWidth().height(180.dp),
                ) {
                    val values = days.map { it.value.toFloat() }
                    val minV = values.minOrNull() ?: 0f
                    val maxV = values.maxOrNull() ?: 1f
                    val span = (maxV - minV).takeIf { it > 0f } ?: 1f
                    val stepX = size.width / days.size.coerceAtLeast(1)
                    fun pointAt(index: Int, value: Float): Offset = Offset(
                        x = index * stepX,
                        y = size.height * (1f - (value - minV) / span),
                    )
                    if (days.size > 1) {
                        val path = Path()
                        days.forEachIndexed { index, day ->
                            val point = pointAt(index, day.value.toFloat())
                            if (index == 0) path.moveTo(point.x, point.y) else path.lineTo(point.x, point.y)
                        }
                        drawPath(path, color = palette.teal, style = Stroke(width = 3.dp.toPx()))
                    }
                    days.forEachIndexed { index, day ->
                        drawCircle(
                            color = palette.teal,
                            radius = 3.dp.toPx(),
                            center = pointAt(index, day.value.toFloat()),
                        )
                    }
                }
                Text(
                    "${days.first().date} ~ ${days.last().date}",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }

        val values = days.map { it.value }
        val minV = values.minOrNull() ?: 0.0
        val maxV = values.maxOrNull() ?: 0.0
        val midV = HealthOverview.median(values) ?: 0.0
        Card(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier.padding(16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                StatItem("最低", minV, meta.unit)
                StatItem("中位", midV, meta.unit)
                StatItem("最高", maxV, meta.unit)
            }
        }

        // 覆盖日历：最近 90 天有数据的日期打点
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text("近 90 天数据覆盖", style = MaterialTheme.typography.titleSmall)
                val covered = series.days.map { it.date }.toSet()
                val start90 = today.minusDays(89)
                val firstMonday = start90.minusDays((start90.dayOfWeek.value - 1).toLong())
                val totalDays = ChronoUnit.DAYS.between(firstMonday, today).toInt() + 1
                val calendarDays = (0 until totalDays).map { firstMonday.plusDays(it.toLong()) }
                calendarDays.chunked(7).forEach { week ->
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        week.forEach { day ->
                            val inWindow = !day.isBefore(start90)
                            val filled = day in covered
                            Box(
                                modifier = Modifier
                                    .size(14.dp)
                                    .clip(CircleShape)
                                    .background(
                                        when {
                                            filled -> palette.teal
                                            inWindow -> palette.line
                                            else -> Color.Transparent
                                        },
                                    ),
                            )
                        }
                    }
                }
                Text(
                    "有数据的天数（近 90 天）：${covered.count { !it.isBefore(start90) }}",
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.muted,
                )
            }
        }
    }
}

@Composable
private fun StatItem(label: String, value: Double, unit: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, style = MaterialTheme.typography.bodySmall)
        Text(
            formatValue(value) + unit.takeIf { it.isNotEmpty() }?.let { " $it" }.orEmpty(),
            style = MaterialTheme.typography.titleMedium,
        )
    }
}

private fun formatValue(value: Double): String {
    val rounded = (value * 10).toLong() / 10.0
    return if (rounded == rounded.toLong().toDouble()) {
        rounded.toLong().toString()
    } else {
        rounded.toString()
    }
}
