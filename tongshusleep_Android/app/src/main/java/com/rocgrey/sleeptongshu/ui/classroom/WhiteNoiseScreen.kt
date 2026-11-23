package com.rocgrey.sleeptongshu.ui.classroom

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rocgrey.sleeptongshu.core.audio.WhiteNoisePlayer
import com.rocgrey.sleeptongshu.ui.theme.LocalSleepPalette

/** 白噪音播放页（对应 iOS WhiteNoiseView）。 */
@Composable
fun WhiteNoiseScreen() {
    val context = LocalContext.current
    val palette = LocalSleepPalette.current
    val isPlaying by WhiteNoisePlayer.isPlaying.collectAsStateWithLifecycle()
    val remainingSeconds by WhiteNoisePlayer.remainingSeconds.collectAsStateWithLifecycle()

    val durationOptions = listOf(5, 15, 30, 45, 60, 90)
    var selectedMinutes by androidx.compose.runtime.remember { androidx.compose.runtime.mutableIntStateOf(30) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Text("白噪音", style = MaterialTheme.typography.titleLarge, color = palette.ink)
        Text(
            "用均匀的白噪音盖过环境杂音，帮助入睡",
            style = MaterialTheme.typography.bodyMedium,
            color = palette.muted,
        )

        // 播放/停止大按钮
        Box(contentAlignment = Alignment.Center) {
            Box(
                modifier = Modifier
                    .size(160.dp)
                    .clip(CircleShape)
                    .background(
                        androidx.compose.ui.graphics.Brush.radialGradient(
                            listOf(palette.teal, palette.mint),
                        ),
                    ),
            )
            androidx.compose.material3.IconButton(onClick = {
                if (isPlaying) {
                    WhiteNoisePlayer.stop()
                } else {
                    WhiteNoisePlayer.start(context, selectedMinutes)
                }
            }, modifier = Modifier.size(96.dp)) {
                Icon(
                    imageVector = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    contentDescription = if (isPlaying) "停止" else "播放",
                    tint = androidx.compose.ui.graphics.Color.White,
                    modifier = Modifier.size(48.dp),
                )
            }
        }

        // 倒计时
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = when {
                    !isPlaying -> "未在播放"
                    remainingSeconds == null -> "不限时播放"
                    else -> "剩余 ${WhiteNoisePlayer.formatRemaining(remainingSeconds!!)}"
                },
                style = MaterialTheme.typography.titleMedium,
                color = palette.ink,
            )
            if (remainingSeconds != null && remainingSeconds!! <= 10) {
                Text(
                    "即将结束，音量渐弱",
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.rose,
                )
            }
        }

        // 时长选择
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("定时停止", style = MaterialTheme.typography.titleSmall, color = palette.ink)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                durationOptions.take(3).forEach { minutes ->
                    FilterChip(
                        selected = selectedMinutes == minutes,
                        onClick = {
                            selectedMinutes = minutes
                            if (isPlaying) WhiteNoisePlayer.start(context, minutes)
                        },
                        label = { Text("$minutes 分钟") },
                    )
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                durationOptions.drop(3).forEach { minutes ->
                    FilterChip(
                        selected = selectedMinutes == minutes,
                        onClick = {
                            selectedMinutes = minutes
                            if (isPlaying) WhiteNoisePlayer.start(context, minutes)
                        },
                        label = { Text("$minutes 分钟") },
                    )
                }
            }
        }

        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Filled.MusicNote, contentDescription = null, tint = palette.teal, modifier = Modifier.size(16.dp))
            Text(
                "播放期间保持音频焦点，短暂打断不会停止",
                style = MaterialTheme.typography.bodySmall,
                color = palette.muted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f).padding(start = 6.dp),
            )
        }
    }
}
