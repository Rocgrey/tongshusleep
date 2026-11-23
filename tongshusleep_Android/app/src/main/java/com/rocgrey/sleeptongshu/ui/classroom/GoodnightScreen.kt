package com.rocgrey.sleeptongshu.ui.classroom

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import com.rocgrey.sleeptongshu.LocalAppContainer
import com.rocgrey.sleeptongshu.LocalRootNav
import com.rocgrey.sleeptongshu.ui.theme.LocalSleepPalette
import java.time.LocalDate

/** 晚安卡（对应 iOS GoodnightView）。 */
@Composable
fun GoodnightScreen() {
    val container = LocalAppContainer.current
    val nav = LocalRootNav.current
    val palette = LocalSleepPalette.current

    val (title, body) = remember {
        val goodnight = container.contentStore.relaxItems().firstOrNull { it.kind == "goodnight" }
        if (goodnight != null) {
            goodnight.title to (goodnight.body ?: goodnight.summary ?: "")
        } else {
            val daily = container.contentStore.dailyArticle(LocalDate.now())
            if (daily != null) {
                "今日晚安阅读" to (daily.body ?: daily.summary ?: "")
            } else {
                "晚安" to "放下今天，把呼吸放慢，愿你一夜好眠。"
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        // 晚安卡占位图：主题色渐变
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(180.dp)
                .clip(RoundedCornerShape(20.dp))
                .background(
                    androidx.compose.ui.graphics.Brush.linearGradient(
                        listOf(palette.deep, palette.teal, palette.mint),
                    ),
                ),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "晚 安",
                style = MaterialTheme.typography.titleLarge,
                color = androidx.compose.ui.graphics.Color.White,
            )
        }

        Text(title, style = MaterialTheme.typography.titleMedium, color = palette.ink)
        if (body.isBlank()) {
            Text("今晚先好好休息", style = MaterialTheme.typography.bodyMedium, color = palette.muted)
        } else {
            Text(
                text = body,
                style = MaterialTheme.typography.bodyLarge,
                color = palette.ink,
                textAlign = TextAlign.Start,
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(onClick = { nav.navigate("breathing") }, modifier = Modifier.weight(1f)) {
                Text("开始呼吸练习")
            }
            Button(onClick = { nav.navigate("noise") }, modifier = Modifier.weight(1f)) {
                Text("播放白噪音")
            }
        }

        Spacer(Modifier.height(12.dp))
    }
}
