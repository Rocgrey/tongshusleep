package com.rocgrey.sleeptongshu.ui.classroom

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ScreenRotation
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.rocgrey.sleeptongshu.LocalAppContainer
import com.rocgrey.sleeptongshu.LocalRootNav
import com.rocgrey.sleeptongshu.core.api.ClassroomItem
import com.rocgrey.sleeptongshu.core.data.LearningProgressEntity
import com.rocgrey.sleeptongshu.ui.theme.LocalSleepPalette
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** 课程视频播放（对应 iOS ClassroomVideoView）：进度恢复/保存、章节切换、横竖屏。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClassroomVideoScreen(itemId: String) {
    val container = LocalAppContainer.current
    val nav = LocalRootNav.current
    val context = LocalContext.current
    val palette = LocalSleepPalette.current
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current

    val baseItem = remember(itemId) { container.contentStore.byId(itemId) }
    var activeId by remember(itemId) { mutableStateOf(resolvePlayableId(container, baseItem, itemId)) }
    val activeItem = remember(activeId) { activeId?.let { container.contentStore.byId(it) } }
    val mediaUrl = activeItem?.mediaUrl?.takeIf { it.startsWith("https://") }

    var isLandscape by remember { mutableStateOf(false) }
    var showChapters by remember { mutableStateOf(false) }

    val chapters = remember(baseItem?.id, activeId) {
        val course = if (baseItem?.kind == "course") baseItem else
            activeItem?.parentId?.let { container.contentStore.byId(it) }
        course?.let { container.contentStore.chaptersOf(it.id) } ?: emptyList()
    }

    fun progressKey(targetItemId: String): String =
        container.contentStore.sha256(container.accountStore.userScope() + "|" + targetItemId)

    fun saveProgress(targetItemId: String, player: ExoPlayer?) {
        val p = player ?: return
        val durationMs = p.duration
        val positionMs = p.currentPosition
        if (durationMs <= 0 || positionMs <= 0) return
        scope.launch {
            container.database.learningProgressDao().upsert(
                LearningProgressEntity(
                    itemKey = progressKey(targetItemId),
                    seconds = positionMs / 1000.0,
                    duration = durationMs / 1000.0,
                    updatedAt = System.currentTimeMillis(),
                ),
            )
        }
    }

    // 播放器实例
    val player = remember { ExoPlayer.Builder(context).build() }

    // 装载媒体与播放状态
    DisposableEffect(mediaUrl) {
        if (mediaUrl != null) {
            player.setMediaItem(MediaItem.fromUri(mediaUrl))
            player.prepare()
            player.playWhenReady = true
        }
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_READY) {
                    // 准备完成后恢复上次进度
                    val targetId = activeId
                    if (targetId != null) {
                        scope.launch {
                            try {
                                val progress = container.database.learningProgressDao().byKey(progressKey(targetId))
                                if (progress != null && progress.seconds > 1.0 && progress.seconds < progress.duration) {
                                    player.seekTo((progress.seconds * 1000).toLong())
                                }
                            } catch (_: Exception) {
                            }
                        }
                    }
                }
                if (state == Player.STATE_ENDED) {
                    // 播放完成：进度标记到全片长
                    val duration = player.duration
                    if (duration > 0) {
                        scope.launch {
                            container.database.learningProgressDao().upsert(
                                LearningProgressEntity(
                                    itemKey = progressKey(activeId ?: itemId),
                                    seconds = duration / 1000.0,
                                    duration = duration / 1000.0,
                                    updatedAt = System.currentTimeMillis(),
                                ),
                            )
                        }
                    }
                }
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }

    // 每 5 秒保存一次
    LaunchedEffect(activeId) {
        if (activeId == null) return@LaunchedEffect
        while (isActive) {
            kotlinx.coroutines.delay(5000)
            saveProgress(activeId, player)
        }
    }

    // 生命周期暂停/停止时保存
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_PAUSE || event == Lifecycle.Event.ON_STOP) {
                saveProgress(activeId ?: itemId, player)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            saveProgress(activeId ?: itemId, player)
        }
    }

    // 离开页面释放播放器
    DisposableEffect(Unit) {
        onDispose { player.release() }
    }

    if (isLandscape) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(android.graphics.Color.BLACK),
        ) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply { this.player = player }
                },
                modifier = Modifier.fillMaxSize(),
                update = { view -> view.player = player },
            )
            IconButton(
                onClick = {
                    isLandscape = false
                    findActivity(context)?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_USER_PORTRAIT
                },
                modifier = Modifier.align(Alignment.TopEnd),
            ) {
                Icon(Icons.Filled.Close, contentDescription = "退出横屏", tint = androidx.compose.ui.graphics.Color.White)
            }
        }
        return
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            IconButton(onClick = { nav.popBackStack() }) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回", tint = palette.ink)
            }
            Text(
                text = activeItem?.title ?: baseItem?.title ?: "课程视频",
                style = MaterialTheme.typography.titleSmall,
                color = palette.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = {
                isLandscape = true
                findActivity(context)?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            }) {
                Icon(Icons.Filled.ScreenRotation, contentDescription = "横屏播放", tint = palette.ink)
            }
            if (chapters.isNotEmpty()) {
                IconButton(onClick = { showChapters = true }) {
                    Icon(Icons.AutoMirrored.Filled.List, contentDescription = "章节列表", tint = palette.ink)
                }
            }
        }

        if (baseItem == null || mediaUrl == null) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        if (baseItem == null) "内容不存在或已被移除" else "该章节暂无可播放的视频",
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.muted,
                    )
                    Spacer(Modifier.height(8.dp))
                    Text("仅支持 HTTPS 视频源", style = MaterialTheme.typography.bodySmall, color = palette.muted)
                }
            }
            return
        }

        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply { this.player = player }
            },
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(16f / 9f),
            update = { view -> view.player = player },
        )

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(activeItem?.title ?: "", style = MaterialTheme.typography.titleMedium, color = palette.ink)
            activeItem?.summary?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, color = palette.muted)
            }
            baseItem.summary?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = palette.muted)
            }
        }
    }

    if (showChapters && chapters.isNotEmpty()) {
        ModalBottomSheet(onDismissRequest = { showChapters = false }) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("章节列表", style = MaterialTheme.typography.titleMedium, color = palette.ink)
                chapters.forEachIndexed { index, chapter ->
                    val playable = chapter.mediaUrl?.startsWith("https://") == true
                    Surface(
                        shape = RoundedCornerShape(12.dp),
                        color = if (chapter.id == activeId) palette.background else palette.surface,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(enabled = playable) {
                                saveProgress(activeId ?: itemId, player)
                                activeId = chapter.id
                                showChapters = false
                            },
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.padding(12.dp),
                        ) {
                            Text(
                                text = "${index + 1}",
                                style = MaterialTheme.typography.titleSmall,
                                color = palette.teal,
                                modifier = Modifier.padding(end = 12.dp),
                            )
                            Text(
                                text = chapter.title,
                                style = MaterialTheme.typography.titleSmall,
                                color = palette.ink,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f),
                            )
                            if (!playable) {
                                Text("暂无视频", style = MaterialTheme.typography.bodySmall, color = palette.muted)
                            }
                        }
                    }
                }
            }
        }
    }
}

/** 解析可播放条目 id：直给视频用之；课程取第一章可播章节。 */
private fun resolvePlayableId(
    container: com.rocgrey.sleeptongshu.AppContainer,
    item: ClassroomItem?,
    itemId: String,
): String? {
    if (item == null) return null
    if (item.mediaUrl?.startsWith("https://") == true) return item.id
    if (item.kind == "course") {
        return container.contentStore.chaptersOf(item.id)
            .firstOrNull { it.mediaUrl?.startsWith("https://") == true }?.id
    }
    return null
}

private fun findActivity(context: Context): Activity? {
    var ctx = context
    while (ctx is ContextWrapper) {
        if (ctx is Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}
