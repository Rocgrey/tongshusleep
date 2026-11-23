package com.rocgrey.sleeptongshu.ui.classroom

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.rocgrey.sleeptongshu.LocalAppContainer
import com.rocgrey.sleeptongshu.LocalRootNav
import com.rocgrey.sleeptongshu.core.api.ClassroomItem
import com.rocgrey.sleeptongshu.ui.theme.LocalSleepPalette

/** 课堂详情：文章正文（简单 markdown 加粗）/ 课程章节列表。 */
@Composable
fun ClassroomDetailScreen(itemId: String) {
    val container = LocalAppContainer.current
    val nav = LocalRootNav.current
    val palette = LocalSleepPalette.current
    val item = remember(itemId) { container.contentStore.byId(itemId) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background),
    ) {
        // 顶部返回栏
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            IconButton(onClick = { nav.popBackStack() }) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "返回",
                    tint = palette.ink,
                )
            }
            Text(
                text = item?.title ?: "详情",
                style = MaterialTheme.typography.titleSmall,
                color = palette.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f).padding(end = 12.dp),
            )
        }

        if (item == null) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("内容不存在或已被移除", style = MaterialTheme.typography.bodyMedium, color = palette.muted)
            }
            return
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            CoverPlaceholder(title = item.title, modifier = Modifier.fillMaxWidth().height(140.dp))
            if (item.kind != "course") {
                item.category?.let {
                    Text(
                        text = it,
                        style = MaterialTheme.typography.labelSmall,
                        color = palette.teal,
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(palette.surface)
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                    )
                }
            }
            Text(item.title, style = MaterialTheme.typography.titleLarge, color = palette.ink)
            item.summary?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, color = palette.muted)
            }

            when (item.kind) {
                "course" -> ChapterList(course = item)
                else -> {
                    val body = item.body ?: item.summary
                    if (body.isNullOrBlank()) {
                        Text("正文暂未提供", style = MaterialTheme.typography.bodyMedium, color = palette.muted)
                    } else {
                        MarkdownBody(body)
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

/** 章节列表（课程详情）。 */
@Composable
private fun ChapterList(course: ClassroomItem) {
    val container = LocalAppContainer.current
    val nav = LocalRootNav.current
    val palette = LocalSleepPalette.current
    val chapters = container.contentStore.chaptersOf(course.id)
    if (chapters.isEmpty()) {
        Text("本章暂未上线，敬请期待", style = MaterialTheme.typography.bodyMedium, color = palette.muted)
        return
    }
    chapters.forEachIndexed { index, chapter ->
        val playable = chapter.mediaUrl?.startsWith("https://") == true
        Surface(
            shape = RoundedCornerShape(14.dp),
            color = palette.surface,
            modifier = Modifier
                .fillMaxWidth()
                .clickable(enabled = playable) {
                    nav.navigate("classroom/video/${chapter.id}")
                },
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(12.dp)) {
                Text(
                    text = "${index + 1}",
                    style = MaterialTheme.typography.titleSmall,
                    color = palette.teal,
                    modifier = Modifier.width(28.dp),
                )
                Column(Modifier.weight(1f)) {
                    Text(chapter.title, style = MaterialTheme.typography.titleSmall, color = palette.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    val seconds = chapter.duration?.toInt()
                    Text(
                        text = if (seconds != null && seconds > 0) {
                            "%02d:%02d".format(seconds / 60, seconds % 60)
                        } else {
                            if (playable) "点击播放" else "暂无视频"
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.muted,
                    )
                }
                Icon(
                    Icons.Filled.PlayArrow,
                    contentDescription = null,
                    tint = if (playable) palette.teal else palette.muted,
                )
            }
        }
    }
}

/**
 * 简易正文渲染：空行分段，段落内支持 **加粗** 标记。
 * （对应 iOS 端对 body 的轻量 markdown 渲染口径。）
 */
@Composable
private fun MarkdownBody(body: String) {
    val palette = LocalSleepPalette.current
    val paragraphs = remember(body) {
        body.split(Regex("\n\\s*\n")).map { it.trim() }.filter { it.isNotEmpty() }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        paragraphs.forEach { paragraph ->
            Text(
                text = remember(paragraph) { buildAnnotatedString(paragraph) },
                style = MaterialTheme.typography.bodyLarge,
                color = palette.ink,
            )
        }
    }
}

/** 把 **text** 解析为加粗 span。 */
private fun buildAnnotatedString(text: String): AnnotatedString = buildAnnotatedString {
    var index = 0
    val bold = SpanStyle(fontWeight = FontWeight.Bold)
    while (index < text.length) {
        val start = text.indexOf("**", index)
        if (start < 0) {
            append(text.substring(index))
            break
        }
        val end = text.indexOf("**", start + 2)
        if (end < 0) {
            append(text.substring(index))
            break
        }
        append(text.substring(index, start))
        pushStyle(bold)
        append(text.substring(start + 2, end))
        pop()
        index = end + 2
    }
}
