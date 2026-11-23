package com.rocgrey.sleeptongshu.ui.classroom

import android.content.Intent
import android.net.Uri
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Air
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Nightlight
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rocgrey.sleeptongshu.LocalAppContainer
import com.rocgrey.sleeptongshu.LocalRootNav
import com.rocgrey.sleeptongshu.core.data.AppPreferences
import com.rocgrey.sleeptongshu.core.reminders.ReminderScheduler
import com.rocgrey.sleeptongshu.ui.theme.AppAppearance
import com.rocgrey.sleeptongshu.ui.theme.LocalSleepPalette
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.util.Locale

/** 睡眠课堂首页（对应 iOS SleepClassroomView）。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SleepClassroomScreen() {
    val container = LocalAppContainer.current
    val context = LocalContext.current
    val nav = LocalRootNav.current
    val palette = LocalSleepPalette.current
    val scope = rememberCoroutineScope()

    var items by remember { mutableStateOf(container.contentStore.all()) }
    var catalogInitialized by remember { mutableStateOf(container.contentStore.isCatalogInitialized()) }
    var showSettings by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        container.contentStore.refresh(force = false, userScope = container.accountStore.userScope())
        items = container.contentStore.all()
        catalogInitialized = container.contentStore.isCatalogInitialized()
    }

    val prefs = container.preferences
    val appearance by prefs.appearance.collectAsStateWithLifecycle(initialValue = AppAppearance.FRESH)
    val dailyReminder by prefs.dailyReminder.collectAsStateWithLifecycle(initialValue = false)
    val bedtimeReminder by prefs.bedtimeReminder.collectAsStateWithLifecycle(initialValue = false)
    val dailyMinute by prefs.dailyMinute.collectAsStateWithLifecycle(initialValue = 1200)
    val bedtimeMinute by prefs.bedtimeMinute.collectAsStateWithLifecycle(initialValue = 1320)
    val remoteReminders by prefs.remoteReminders.collectAsStateWithLifecycle(initialValue = false)
    val saveCandidateVoice by prefs.saveCandidateVoice.collectAsStateWithLifecycle(initialValue = false)

    Box(modifier = Modifier.fillMaxSize().background(palette.background)) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            if (!catalogInitialized) {
                item {
                    Text(
                        text = "内容服务暂不可用，当前显示本机保存内容",
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.muted,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(palette.surface)
                            .padding(12.dp),
                    )
                }
            }
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "睡眠课堂",
                        style = MaterialTheme.typography.titleLarge,
                        color = palette.ink,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(onClick = { showSettings = true }) {
                        Icon(Icons.Filled.Settings, contentDescription = "设置", tint = palette.muted)
                    }
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.School, contentDescription = null, tint = palette.teal, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("课程", style = MaterialTheme.typography.titleMedium, color = palette.ink)
                    }
                    val courses = items.filter { it.kind == "course" }.sortedBy { it.sortOrder }
                    if (courses.isEmpty()) {
                        Text("暂无课程内容", style = MaterialTheme.typography.bodyMedium, color = palette.muted)
                    } else {
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            items(courses.size) { index ->
                                val course = courses[index]
                                val chapters = container.contentStore.chaptersOf(course.id)
                                val playable = chapters.firstOrNull { it.mediaUrl?.startsWith("https://") == true }
                                Column(
                                    modifier = Modifier
                                        .width(170.dp)
                                        .clip(RoundedCornerShape(16.dp))
                                        .background(palette.surface)
                                        .clickable {
                                            if (playable != null) {
                                                nav.navigate("classroom/video/${playable.id}")
                                            } else {
                                                nav.navigate("classroom/article/${course.id}")
                                            }
                                        }
                                        .padding(10.dp),
                                ) {
                                    CoverPlaceholder(title = course.title, modifier = Modifier.fillMaxWidth().height(96.dp))
                                    Spacer(Modifier.height(8.dp))
                                    Text(
                                        text = course.title,
                                        style = MaterialTheme.typography.titleSmall,
                                        color = palette.ink,
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    Spacer(Modifier.height(4.dp))
                                    Text(
                                        text = if (chapters.isEmpty()) "图文课程" else "共 ${chapters.size} 章",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = palette.muted,
                                    )
                                }
                            }
                        }
                    }
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.MenuBook, contentDescription = null, tint = palette.teal, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("阅读", style = MaterialTheme.typography.titleMedium, color = palette.ink)
                    }
                    val daily = container.contentStore.dailyArticle(LocalDate.now())
                    val articleList = buildList {
                        daily?.let { add(it) }
                        items.filter { it.kind == "article" }.sortedBy { it.sortOrder }.forEach { article ->
                            if (none { it.id == article.id }) add(article)
                        }
                    }.distinctBy { it.id }
                    if (articleList.isEmpty()) {
                        Text("暂无阅读内容", style = MaterialTheme.typography.bodyMedium, color = palette.muted)
                    } else {
                        articleList.forEachIndexed { index, article ->
                            val isDaily = index == 0 && daily != null && articleList[0].id == daily.id
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(14.dp))
                                    .background(palette.surface)
                                    .clickable { nav.navigate("classroom/article/${article.id}") }
                                    .padding(12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(Modifier.weight(1f)) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        if (isDaily) {
                                            Text(
                                                text = "今日阅读",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = palette.background,
                                                modifier = Modifier
                                                    .clip(RoundedCornerShape(6.dp))
                                                    .background(palette.teal)
                                                    .padding(horizontal = 6.dp, vertical = 2.dp),
                                            )
                                            Spacer(Modifier.width(6.dp))
                                        }
                                        Text(
                                            text = article.title,
                                            style = MaterialTheme.typography.titleSmall,
                                            color = palette.ink,
                                            maxLines = 2,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    }
                                    article.summary?.let {
                                        Spacer(Modifier.height(4.dp))
                                        Text(it, style = MaterialTheme.typography.bodySmall, color = palette.muted, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                    }
                                    article.category?.let {
                                        Spacer(Modifier.height(6.dp))
                                        Text(
                                            text = it,
                                            style = MaterialTheme.typography.labelSmall,
                                            color = palette.teal,
                                            modifier = Modifier
                                                .clip(RoundedCornerShape(6.dp))
                                                .background(palette.background)
                                                .padding(horizontal = 6.dp, vertical = 2.dp),
                                        )
                                    }
                                }
                                Icon(Icons.Filled.ChevronRight, contentDescription = null, tint = palette.muted)
                            }
                        }
                    }
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("助眠", style = MaterialTheme.typography.titleMedium, color = palette.ink)
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        RelaxCard(icon = Icons.Filled.Air, label = "4-7-8 呼吸", modifier = Modifier.weight(1f)) {
                            nav.navigate("breathing")
                        }
                        RelaxCard(icon = Icons.Filled.MusicNote, label = "白噪音", modifier = Modifier.weight(1f)) {
                            nav.navigate("noise")
                        }
                        RelaxCard(icon = Icons.Filled.Nightlight, label = "晚安卡", modifier = Modifier.weight(1f)) {
                            nav.navigate("goodnight")
                        }
                    }
                    val relaxItems = items.filter { it.kind in setOf("noise", "breathing", "goodnight") }.sortedBy { it.sortOrder }
                    relaxItems.forEach { relax ->
                        val route = when (relax.kind) {
                            "noise" -> "noise"
                            "breathing" -> "breathing"
                            "goodnight" -> "goodnight"
                            else -> null
                        } ?: return@forEach
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(14.dp))
                                .background(palette.surface)
                                .clickable { nav.navigate(route) }
                                .padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(relax.title, style = MaterialTheme.typography.titleSmall, color = palette.ink)
                                relax.summary?.let {
                                    Text(it, style = MaterialTheme.typography.bodySmall, color = palette.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                }
                            }
                            Icon(Icons.Filled.ChevronRight, contentDescription = null, tint = palette.muted)
                        }
                    }
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.ShoppingCart, contentDescription = null, tint = palette.teal, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("产品", style = MaterialTheme.typography.titleMedium, color = palette.ink)
                    }
                    val products = items
                        .filter { it.kind == "product" && com.rocgrey.sleeptongshu.core.api.ApiClient.isJdUrl(it.externalUrl) }
                        .sortedBy { it.sortOrder }
                    if (products.isEmpty()) {
                        Text("暂无推荐产品", style = MaterialTheme.typography.bodyMedium, color = palette.muted)
                    } else {
                        products.forEach { product ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(14.dp))
                                    .background(palette.surface)
                                    .clickable { openExternal(context, product.externalUrl) }
                                    .padding(12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(Modifier.weight(1f)) {
                                    Text(product.title, style = MaterialTheme.typography.titleSmall, color = palette.ink)
                                    product.summary?.let {
                                        Text(it, style = MaterialTheme.typography.bodySmall, color = palette.muted, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                    }
                                }
                                Icon(Icons.Filled.OpenInNew, contentDescription = "京东购买", tint = palette.teal)
                            }
                        }
                    }
                }
            }
            item { Spacer(Modifier.height(8.dp)) }
        }

        if (showSettings) {
            ModalBottomSheet(onDismissRequest = { showSettings = false }) {
                ClassroomSettingsPanel(
                    appearance = appearance,
                    dailyReminder = dailyReminder,
                    bedtimeReminder = bedtimeReminder,
                    dailyMinute = dailyMinute,
                    bedtimeMinute = bedtimeMinute,
                    remoteReminders = remoteReminders,
                    saveCandidateVoice = saveCandidateVoice,
                    onAppearance = { scope.launch { container.preferences.setAppearance(it) } },
                    onRemindersChange = { daily, bedtime, dailyMin, bedtimeMin, remote ->
                        scope.launch {
                            container.preferences.setReminders(daily, bedtime, dailyMin, bedtimeMin, remote)
                            ReminderScheduler.reschedule(context)
                        }
                    },
                    onSaveCandidateVoice = { scope.launch { container.preferences.setSaveCandidateVoice(it) } },
                )
            }
        }
    }
}

@Composable
private fun RelaxCard(icon: ImageVector, label: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val palette = LocalSleepPalette.current
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(palette.surface)
            .clickable(onClick = onClick)
            .padding(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(icon, contentDescription = null, tint = palette.teal, modifier = Modifier.size(28.dp))
        Text(label, style = MaterialTheme.typography.titleSmall, color = palette.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

private fun openExternal(context: android.content.Context, url: String?) {
    if (url.isNullOrBlank()) return
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    } catch (_: Exception) {
    }
}

/** 课堂设置面板：外观 / 提醒 / 远程推送 / 候选语音。 */
@Composable
private fun ClassroomSettingsPanel(
    appearance: AppAppearance,
    dailyReminder: Boolean,
    bedtimeReminder: Boolean,
    dailyMinute: Int,
    bedtimeMinute: Int,
    remoteReminders: Boolean,
    saveCandidateVoice: Boolean,
    onAppearance: (AppAppearance) -> Unit,
    onRemindersChange: (daily: Boolean, bedtime: Boolean, dailyMin: Int, bedtimeMin: Int, remote: Boolean) -> Unit,
    onSaveCandidateVoice: (Boolean) -> Unit,
) {
    val palette = LocalSleepPalette.current
    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("设置", style = MaterialTheme.typography.titleMedium, color = palette.ink)
        Text("外观", style = MaterialTheme.typography.titleSmall, color = palette.ink)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AppAppearance.entries.forEach { option ->
                FilterChip(
                    selected = appearance == option,
                    onClick = { onAppearance(option) },
                    label = { Text(option.label) },
                )
            }
        }
        ReminderRows(
            daily = dailyReminder,
            bedtime = bedtimeReminder,
            dailyMinute = dailyMinute,
            bedtimeMinute = bedtimeMinute,
            remote = remoteReminders,
            onChange = onRemindersChange,
        )
        Text(
            text = "远程推送需要服务器下发通知；本端未集成 FCM 前仅会同步提醒偏好到服务器。",
            style = MaterialTheme.typography.bodySmall,
            color = palette.muted,
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("保存候选语音", style = MaterialTheme.typography.bodyLarge, color = palette.ink)
                Text("监测过程中保留原始候选语音片段", style = MaterialTheme.typography.bodySmall, color = palette.muted)
            }
            Switch(checked = saveCandidateVoice, onCheckedChange = { onSaveCandidateVoice(it) })
        }
    }
}

/** 提醒开关与时间行（课堂设置与账号页共用逻辑的课堂侧实现）。 */
@Composable
internal fun ReminderRows(
    daily: Boolean,
    bedtime: Boolean,
    dailyMinute: Int,
    bedtimeMinute: Int,
    remote: Boolean,
    onChange: (daily: Boolean, bedtime: Boolean, dailyMin: Int, bedtimeMin: Int, remote: Boolean) -> Unit,
) {
    val palette = LocalSleepPalette.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("每日阅读提醒", style = MaterialTheme.typography.bodyLarge, color = palette.ink)
                Text("每天 ${formatMinuteOfDay(dailyMinute)} 提醒今日阅读", style = MaterialTheme.typography.bodySmall, color = palette.muted)
            }
            Switch(checked = daily, onCheckedChange = { onChange(it, bedtime, dailyMinute, bedtimeMinute, remote) })
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("时间", style = MaterialTheme.typography.bodyMedium, color = palette.muted, modifier = Modifier.weight(1f))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                FilterChip(
                    selected = false,
                    onClick = {
                        val next = ((dailyMinute - 30 + 1440) % 1440)
                        onChange(daily, bedtime, next, bedtimeMinute, remote)
                    },
                    label = { Text("-30 分") },
                )
                Text(formatMinuteOfDay(dailyMinute), style = MaterialTheme.typography.titleSmall, color = palette.ink)
                FilterChip(
                    selected = false,
                    onClick = {
                        val next = ((dailyMinute + 30) % 1440)
                        onChange(daily, bedtime, next, bedtimeMinute, remote)
                    },
                    label = { Text("+30 分") },
                )
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("睡前提醒", style = MaterialTheme.typography.bodyLarge, color = palette.ink)
                Text("每天 ${formatMinuteOfDay(bedtimeMinute)} 提醒准备休息", style = MaterialTheme.typography.bodySmall, color = palette.muted)
            }
            Switch(checked = bedtime, onCheckedChange = { onChange(daily, it, dailyMinute, bedtimeMinute, remote) })
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("时间", style = MaterialTheme.typography.bodyMedium, color = palette.muted, modifier = Modifier.weight(1f))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                FilterChip(
                    selected = false,
                    onClick = {
                        val next = ((bedtimeMinute - 30 + 1440) % 1440)
                        onChange(daily, bedtime, dailyMinute, next, remote)
                    },
                    label = { Text("-30 分") },
                )
                Text(formatMinuteOfDay(bedtimeMinute), style = MaterialTheme.typography.titleSmall, color = palette.ink)
                FilterChip(
                    selected = false,
                    onClick = {
                        val next = ((bedtimeMinute + 30) % 1440)
                        onChange(daily, bedtime, dailyMinute, next, remote)
                    },
                    label = { Text("+30 分") },
                )
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("远程推送提醒", style = MaterialTheme.typography.bodyLarge, color = palette.ink)
                Text("登录后同步提醒偏好到服务器", style = MaterialTheme.typography.bodySmall, color = palette.muted)
            }
            Switch(checked = remote, onCheckedChange = { onChange(daily, bedtime, dailyMinute, bedtimeMinute, it) })
        }
    }
}

/** 分钟数（0..1439）转 HH:mm 文案。 */
internal fun formatMinuteOfDay(minute: Int): String {
    val safe = minute.coerceIn(0, 1439)
    return String.format(Locale.US, "%02d:%02d", safe / 60, safe % 60)
}

/** 主题色渐变 + 首字占位封面（Android 无 iOS 资源图）。 */
@Composable
internal fun CoverPlaceholder(title: String, modifier: Modifier = Modifier, colors: List<Color>? = null) {
    val palette = LocalSleepPalette.current
    val gradient = colors ?: listOf(palette.teal, palette.mint)
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Brush.linearGradient(gradient)),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = title.take(1).ifBlank { "课" },
            style = MaterialTheme.typography.titleLarge,
            color = Color.White,
            fontWeight = FontWeight.SemiBold,
        )
    }
}
