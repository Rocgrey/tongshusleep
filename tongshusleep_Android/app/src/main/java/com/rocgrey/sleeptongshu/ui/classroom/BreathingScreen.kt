package com.rocgrey.sleeptongshu.ui.classroom

import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.rocgrey.sleeptongshu.LocalRootNav
import com.rocgrey.sleeptongshu.ui.theme.LocalSleepPalette
import kotlin.math.ceil

/** 4-7-8 呼吸练习（对应 iOS BreathingView）。 */
@Composable
fun BreathingScreen() {
    val palette = LocalSleepPalette.current
    val nav = LocalRootNav.current
    val context = LocalContext.current

    val phases = listOf(
        Triple("吸气", 4, palette.teal),
        Triple("屏息", 7, palette.rem),
        Triple("呼气", 8, palette.mint),
    )
    val cycleSeconds = phases.sumOf { it.second }

    var running by remember { mutableStateOf(false) }
    var elapsed by remember { mutableFloatStateOf(0f) }
    var cycles by remember { mutableIntStateOf(0) }
    var reducedMotion by remember {
        mutableStateOf(
            Settings.Global.getFloat(
                context.contentResolver,
                Settings.Global.ANIMATOR_DURATION_SCALE,
                1f,
            ) == 0f,
        )
    }

    // 帧计时驱动循环
    LaunchedEffect(running) {
        if (!running) return@LaunchedEffect
        var last = 0L
        while (true) {
            withFrameNanos { now ->
                if (last == 0L) {
                    last = now
                } else {
                    elapsed += (now - last) / 1_000_000_000f
                    last = now
                }
            }
            if (elapsed >= cycleSeconds) {
                elapsed -= cycleSeconds
                cycles += 1
            }
        }
    }

    // 计算当前阶段
    var phaseIndex = 0
    var phaseElapsed = elapsed
    for (i in phases.indices) {
        if (phaseElapsed < phases[i].second) {
            phaseIndex = i
            break
        }
        phaseElapsed -= phases[i].second
        phaseIndex = i
    }
    val (phaseName, phaseSeconds, phaseColor) = phases[phaseIndex]
    val phaseRemaining = (phaseSeconds - phaseElapsed).coerceAtLeast(0.0)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Text("4-7-8 呼吸", style = MaterialTheme.typography.titleLarge, color = palette.ink)
        Text(
            "吸气 4 秒 · 屏息 7 秒 · 呼气 8 秒",
            style = MaterialTheme.typography.bodyMedium,
            color = palette.muted,
        )

        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(260.dp)) {
            if (reducedMotion) {
                // 系统"减少动画"：纯文本计时降级
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(phaseName, style = MaterialTheme.typography.titleLarge, color = phaseColor)
                    Text(
                        "${ceil(phaseRemaining).toInt()} 秒",
                        style = MaterialTheme.typography.bodyLarge,
                        color = palette.muted,
                    )
                }
            } else {
                Canvas(modifier = Modifier.fillMaxSize()) {
                    val stroke = Stroke(width = 14.dp.toPx(), cap = StrokeCap.Round)
                    val inset = stroke.width + 6.dp.toPx()
                    val diameter = size.minDimension - inset * 2
                    // 背景环
                    drawCircle(
                        color = palette.line,
                        radius = diameter / 2f,
                        center = Offset(center.x, center.y),
                        style = stroke,
                    )
                    // 当前阶段进度弧
                    val progress = if (phaseSeconds > 0) (phaseElapsed / phaseSeconds).toFloat() else 0f
                    drawArc(
                        color = phaseColor,
                        startAngle = -90f,
                        sweepAngle = 360f * progress,
                        useCenter = false,
                        topLeft = Offset(center.x - diameter / 2f, center.y - diameter / 2f),
                        size = androidx.compose.ui.geometry.Size(diameter, diameter),
                        style = stroke,
                    )
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(phaseName, style = MaterialTheme.typography.titleLarge, color = phaseColor, fontWeight = FontWeight.SemiBold)
                    Text(
                        "${ceil(phaseRemaining).toInt()} 秒",
                        style = MaterialTheme.typography.bodyLarge,
                        color = palette.muted,
                    )
                }
            }
        }

        Text(
            "已完成 $cycles 个循环",
            style = MaterialTheme.typography.bodyMedium,
            color = palette.muted,
        )

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(onClick = {
                if (running) {
                    running = false
                } else {
                    running = true
                }
            }) {
                Text(if (running) "暂停" else "开始")
            }
            Button(onClick = {
                running = false
                elapsed = 0f
                cycles = 0
            }) {
                Text("重置")
            }
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.width(4.dp))
            Text(
                text = "安静坐好，跟着节奏感受呼吸",
                style = MaterialTheme.typography.bodySmall,
                color = palette.muted,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = "返回",
                style = MaterialTheme.typography.labelLarge,
                color = palette.teal,
                modifier = Modifier
                    .padding(4.dp)
                    .clickable { nav.popBackStack() },
            )
        }
        Spacer(Modifier.height(12.dp))
    }
}
