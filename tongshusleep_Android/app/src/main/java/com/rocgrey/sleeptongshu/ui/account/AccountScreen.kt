package com.rocgrey.sleeptongshu.ui.account

import android.Manifest
import android.content.Context
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rocgrey.sleeptongshu.LocalAppContainer
import com.rocgrey.sleeptongshu.core.api.ApiException
import com.rocgrey.sleeptongshu.core.api.JsonCodec
import com.rocgrey.sleeptongshu.core.api.SleepRecordAck
import com.rocgrey.sleeptongshu.core.auth.AccountState
import com.rocgrey.sleeptongshu.core.data.AppPreferences
import com.rocgrey.sleeptongshu.core.reminders.ReminderScheduler
import com.rocgrey.sleeptongshu.core.sleep.SleepFormat
import com.rocgrey.sleeptongshu.core.sleep.SleepRecord
import com.rocgrey.sleeptongshu.core.sleep.SleepRecordMapper
import com.rocgrey.sleeptongshu.core.sync.AutomaticSync
import com.rocgrey.sleeptongshu.ui.classroom.formatMinuteOfDay
import com.rocgrey.sleeptongshu.ui.theme.AppAppearance
import com.rocgrey.sleeptongshu.ui.theme.LocalSleepPalette
import kotlinx.coroutines.launch

/** 账号页：登录/注册/找回密码/提醒设置/睡眠上报（对应 iOS AccountView 等）。 */
@Composable
fun AccountScreen() {
    val container = LocalAppContainer.current
    val palette = LocalSleepPalette.current
    val state by container.accountStore.state.collectAsStateWithLifecycle(
        initialValue = AccountState.Restoring,
    )

    Surface(modifier = Modifier.fillMaxSize(), color = palette.background) {
        when (state) {
            AccountState.Restoring -> {
                Column(
                    modifier = Modifier.fillMaxSize().padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    CircularProgressIndicator()
                    Spacer(Modifier.height(12.dp))
                    Text("正在恢复登录状态…", style = MaterialTheme.typography.bodyMedium, color = palette.muted)
                }
            }
            is AccountState.SignedIn -> {
                SignedInPanel(session = (state as AccountState.SignedIn).session)
            }
            is AccountState.Expired -> {
                AuthPanel(expiredReason = (state as AccountState.Expired).reason)
            }
            AccountState.SignedOut -> {
                AuthPanel(expiredReason = null)
            }
        }
    }
}

// ---------- 已登录 ----------

@Composable
private fun SignedInPanel(session: com.rocgrey.sleeptongshu.core.auth.SavedSession) {
    val container = LocalAppContainer.current
    val context = LocalContext.current
    val palette = LocalSleepPalette.current
    val scope = rememberCoroutineScope()

    var showLogoutDialog by remember { mutableStateOf(false) }
    val automaticSync by container.preferences.automaticHealthSync.collectAsStateWithLifecycle(initialValue = true)
    val user = session.user

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("账号", style = MaterialTheme.typography.titleLarge, color = palette.ink)
        Surface(shape = RoundedCornerShape(16.dp), color = palette.surface, modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(user.username, style = MaterialTheme.typography.titleMedium, color = palette.ink)
                Text(
                    text = user.phone ?: user.email ?: "未绑定手机或邮箱",
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.muted,
                )
                user.createdAt?.let {
                    Text("注册时间：$it", style = MaterialTheme.typography.bodySmall, color = palette.muted)
                }
            }
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("自动同步睡眠数据", style = MaterialTheme.typography.bodyLarge, color = palette.ink)
                Text("登录状态下自动上传睡眠与步数", style = MaterialTheme.typography.bodySmall, color = palette.muted)
            }
            Switch(
                checked = automaticSync,
                onCheckedChange = { scope.launch { container.preferences.setAutomaticHealthSync(it) } },
            )
        }

        Text("提醒设置", style = MaterialTheme.typography.titleMedium, color = palette.ink)
        AccountReminderSection()

        Text("睡眠上报", style = MaterialTheme.typography.titleMedium, color = palette.ink)
        SleepUploadSection()

        OutlinedButton(
            onClick = { showLogoutDialog = true },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("退出登录", color = palette.rose)
        }
        Spacer(Modifier.height(24.dp))
    }

    if (showLogoutDialog) {
        AlertDialog(
            onDismissRequest = { showLogoutDialog = false },
            title = { Text("退出登录") },
            text = { Text("退出后本地数据仍会保留，远程同步将暂停。") },
            confirmButton = {
                TextButton(onClick = {
                    showLogoutDialog = false
                    scope.launch { container.accountStore.logout() }
                }) { Text("退出") }
            },
            dismissButton = {
                TextButton(onClick = { showLogoutDialog = false }) { Text("取消") }
            },
        )
    }
}

/** 提醒设置（账号页自写实现）：开关 + 时间步进 + 远程推送 + 通知权限。 */
@Composable
private fun AccountReminderSection() {
    val container = LocalAppContainer.current
    val context = LocalContext.current
    val palette = LocalSleepPalette.current
    val scope = rememberCoroutineScope()

    val prefs: AppPreferences = container.preferences
    val daily by prefs.dailyReminder.collectAsStateWithLifecycle(initialValue = false)
    val bedtime by prefs.bedtimeReminder.collectAsStateWithLifecycle(initialValue = false)
    val dailyMinute by prefs.dailyMinute.collectAsStateWithLifecycle(initialValue = 1200)
    val bedtimeMinute by prefs.bedtimeMinute.collectAsStateWithLifecycle(initialValue = 1320)
    val remote by prefs.remoteReminders.collectAsStateWithLifecycle(initialValue = false)
    val appearance by prefs.appearance.collectAsStateWithLifecycle(initialValue = AppAppearance.FRESH)

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            scope.launch { ReminderScheduler.reschedule(context) }
        }
    }

    fun applyReminders(newDaily: Boolean, newBedtime: Boolean, dailyMin: Int, bedtimeMin: Int, newRemote: Boolean) {
        scope.launch {
            prefs.setReminders(newDaily, newBedtime, dailyMin, bedtimeMin, newRemote)
            ReminderScheduler.reschedule(context)
        }
        // 通知运行时权限：开启任一提醒时申请
        if ((newDaily || newBedtime) && Build.VERSION.SDK_INT >= 33 &&
            androidx.core.content.ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    Surface(shape = RoundedCornerShape(16.dp), color = palette.surface, modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("每日阅读提醒", style = MaterialTheme.typography.bodyLarge, color = palette.ink)
                    Text("每天 ${formatMinuteOfDay(dailyMinute)} 提醒今日阅读", style = MaterialTheme.typography.bodySmall, color = palette.muted)
                }
                Switch(checked = daily, onCheckedChange = { applyReminders(it, bedtime, dailyMinute, bedtimeMinute, remote) })
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("时间", style = MaterialTheme.typography.bodyMedium, color = palette.muted, modifier = Modifier.weight(1f))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    FilterChip(
                        selected = false,
                        onClick = { applyReminders(daily, bedtime, (dailyMinute - 30 + 1440) % 1440, bedtimeMinute, remote) },
                        label = { Text("-30 分") },
                    )
                    Text(formatMinuteOfDay(dailyMinute), style = MaterialTheme.typography.titleSmall, color = palette.ink)
                    FilterChip(
                        selected = false,
                        onClick = { applyReminders(daily, bedtime, (dailyMinute + 30) % 1440, bedtimeMinute, remote) },
                        label = { Text("+30 分") },
                    )
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("睡前提醒", style = MaterialTheme.typography.bodyLarge, color = palette.ink)
                    Text("每天 ${formatMinuteOfDay(bedtimeMinute)} 提醒准备休息", style = MaterialTheme.typography.bodySmall, color = palette.muted)
                }
                Switch(checked = bedtime, onCheckedChange = { applyReminders(daily, it, dailyMinute, bedtimeMinute, remote) })
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("时间", style = MaterialTheme.typography.bodyMedium, color = palette.muted, modifier = Modifier.weight(1f))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    FilterChip(
                        selected = false,
                        onClick = { applyReminders(daily, bedtime, dailyMinute, (bedtimeMinute - 30 + 1440) % 1440, remote) },
                        label = { Text("-30 分") },
                    )
                    Text(formatMinuteOfDay(bedtimeMinute), style = MaterialTheme.typography.titleSmall, color = palette.ink)
                    FilterChip(
                        selected = false,
                        onClick = { applyReminders(daily, bedtime, dailyMinute, (bedtimeMinute + 30) % 1440, remote) },
                        label = { Text("+30 分") },
                    )
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("远程推送提醒", style = MaterialTheme.typography.bodyLarge, color = palette.ink)
                    Text("登录后同步提醒偏好到服务器", style = MaterialTheme.typography.bodySmall, color = palette.muted)
                }
                Switch(checked = remote, onCheckedChange = { applyReminders(daily, bedtime, dailyMinute, bedtimeMinute, it) })
            }
            Text(
                text = "远程推送需集成 FCM 后启用；当前仅本地提醒与偏好同步生效。",
                style = MaterialTheme.typography.bodySmall,
                color = palette.muted,
            )
            Text(
                text = "当前外观：${appearance.label}",
                style = MaterialTheme.typography.bodySmall,
                color = palette.muted,
            )
        }
    }
}

/** 睡眠上报：最近 7 条记录、单条手动上传、最近回执。 */
@Composable
private fun SleepUploadSection() {
    val container = LocalAppContainer.current
    val context = LocalContext.current
    val palette = LocalSleepPalette.current
    val scope = rememberCoroutineScope()

    var records by remember { mutableStateOf<List<SleepRecord>>(emptyList()) }
    var lastAck by remember { mutableStateOf<SleepRecordAck?>(null) }
    var statusById by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var latestAck by remember { mutableStateOf<SleepRecordAck?>(null) }

    LaunchedEffect(Unit) {
        try {
            val domain = container.database.sleepRecordDao().all().map { SleepRecordMapper.toDomain(it) }
            records = domain.take(7)
            // 恢复最近一次上传回执
            val prefs = context.getSharedPreferences("sleepUploadV1", Context.MODE_PRIVATE)
            for (record in records) {
                val raw = prefs.getString("sleepUploadV1.${record.id}", null) ?: continue
                latestAck = runCatching { JsonCodec.json.decodeFromString<SleepRecordAck>(raw) }.getOrNull() ?: latestAck
            }
        } catch (_: Exception) {
        }
    }

    val sync = remember { AutomaticSync(context.applicationContext) { container.apiClient } }

    fun upload(record: SleepRecord) {
        statusById = statusById + (record.id to "上传中…")
        scope.launch {
            try {
                val ack = sync.uploadLegacy(record)
                context.getSharedPreferences("sleepUploadV1", Context.MODE_PRIVATE)
                    .edit()
                    .putString("sleepUploadV1.${record.id}", JsonCodec.json.encodeToString(SleepRecordAck.serializer(), ack))
                    .apply()
                latestAck = ack
                statusById = statusById + (record.id to "已上传 #${ack.id}")
            } catch (e: Exception) {
                statusById = statusById + (record.id to "上传失败：${e.message ?: "网络错误"}")
            }
        }
    }

    Surface(shape = RoundedCornerShape(16.dp), color = palette.surface, modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (records.isEmpty()) {
                Text("暂无睡眠记录，可在睡眠页手动添加", style = MaterialTheme.typography.bodyMedium, color = palette.muted)
            } else {
                records.forEach { record ->
                    val zone = record.zoneId
                    val startText = record.start.atZone(zone).format(SleepFormat.recordDateTime)
                    val endText = record.end.atZone(zone).format(SleepFormat.recordDateTime)
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(
                                    text = record.day.format(SleepFormat.recordDate),
                                    style = MaterialTheme.typography.titleSmall,
                                    color = palette.ink,
                                )
                                Text(
                                    text = "$startText → $endText · 入睡 ${record.asleepMinutes} 分",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = palette.muted,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                            Button(onClick = { upload(record) }) {
                                Text("上传这条")
                            }
                        }
                        statusById[record.id]?.let {
                            Text(it, style = MaterialTheme.typography.bodySmall, color = palette.muted)
                        }
                    }
                }
            }
            latestAck?.let {
                Spacer(Modifier.height(4.dp))
                Text(
                    text = "最近一次上传回执：记录 #${it.id}（用户 ${it.userId}）",
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.teal,
                )
            }
            Text(
                text = "手动上传走旧版直传接口，与自动同步互不影响。",
                style = MaterialTheme.typography.bodySmall,
                color = palette.muted,
            )
        }
    }
}

// ---------- 登录 / 注册 / 找回密码 ----------

@Composable
private fun AuthPanel(expiredReason: String?) {
    val palette = LocalSleepPalette.current
    var mode by rememberSaveable { mutableIntStateOf(0) } // 0 登录 / 1 注册 / 2 找回密码

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("账号", style = MaterialTheme.typography.titleLarge, color = palette.ink)
        expiredReason?.let {
            Text(
                text = "登录已过期：$it",
                style = MaterialTheme.typography.bodyMedium,
                color = palette.rose,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(palette.surface)
                    .padding(12.dp),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = mode == 0,
                onClick = { mode = 0 },
                label = { Text("登录") },
            )
            FilterChip(
                selected = mode == 1,
                onClick = { mode = 1 },
                label = { Text("注册") },
            )
            FilterChip(
                selected = mode == 2,
                onClick = { mode = 2 },
                label = { Text("找回密码") },
            )
        }
        when (mode) {
            0 -> LoginSection(onSwitch = { mode = 2 })
            1 -> RegisterSection()
            else -> RecoverySection()
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun LoginSection(onSwitch: () -> Unit) {
    val container = LocalAppContainer.current
    val palette = LocalSleepPalette.current
    val scope = rememberCoroutineScope()

    var usePhone by rememberSaveable { mutableStateOf(true) }
    var account by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = usePhone,
                onClick = { usePhone = true },
                label = { Text("手机号") },
            )
            FilterChip(
                selected = !usePhone,
                onClick = { usePhone = false },
                label = { Text("邮箱") },
            )
        }
        OutlinedTextField(
            value = account,
            onValueChange = { account = it },
            label = { Text(if (usePhone) "手机号" else "邮箱") },
            keyboardOptions = KeyboardOptions(keyboardType = if (usePhone) KeyboardType.Phone else KeyboardType.Email),
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("密码") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            modifier = Modifier.fillMaxWidth(),
        )
        error?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = palette.rose)
        }
        Button(
            onClick = {
                loading = true
                error = null
                scope.launch {
                    try {
                        container.accountStore.login(
                            phone = if (usePhone) account else null,
                            email = if (usePhone) null else account,
                            password = password,
                        )
                    } catch (e: ApiException) {
                        error = e.message ?: "登录失败"
                    } catch (e: Exception) {
                        error = e.message ?: "网络错误，请稍后重试"
                    } finally {
                        loading = false
                    }
                }
            },
            enabled = !loading && account.isNotBlank() && password.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (loading) {
                CircularProgressIndicator(modifier = Modifier.width(18.dp).height(18.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(8.dp))
            }
            Text("登录")
        }
        Text(
            text = "忘记密码？切换到「找回密码」",
            style = MaterialTheme.typography.bodySmall,
            color = palette.teal,
            modifier = Modifier.clickable { onSwitch() },
        )
    }
}

@Composable
private fun RegisterSection() {
    val container = LocalAppContainer.current
    val palette = LocalSleepPalette.current
    val scope = rememberCoroutineScope()

    var usePhone by rememberSaveable { mutableStateOf(true) }
    var username by rememberSaveable { mutableStateOf("") }
    var account by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var confirm by rememberSaveable { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var success by remember { mutableStateOf<String?>(null) }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = usePhone,
                onClick = { usePhone = true },
                label = { Text("手机号") },
            )
            FilterChip(
                selected = !usePhone,
                onClick = { usePhone = false },
                label = { Text("邮箱") },
            )
        }
        OutlinedTextField(
            value = username,
            onValueChange = { username = it },
            label = { Text("用户名") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = account,
            onValueChange = { account = it },
            label = { Text(if (usePhone) "手机号" else "邮箱") },
            keyboardOptions = KeyboardOptions(keyboardType = if (usePhone) KeyboardType.Phone else KeyboardType.Email),
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("密码（至少 8 位）") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = confirm,
            onValueChange = { confirm = it },
            label = { Text("确认密码") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            modifier = Modifier.fillMaxWidth(),
        )
        error?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = palette.rose)
        }
        success?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = palette.teal)
        }
        Button(
            onClick = {
                error = null
                success = null
                if (username.isBlank()) {
                    error = "请输入用户名"
                    return@Button
                }
                if (account.isBlank()) {
                    error = if (usePhone) "请输入手机号" else "请输入邮箱"
                    return@Button
                }
                if (password.length < 8) {
                    error = "密码长度至少 8 位"
                    return@Button
                }
                if (password != confirm) {
                    error = "两次输入的密码不一致"
                    return@Button
                }
                loading = true
                scope.launch {
                    try {
                        container.accountStore.register(
                            username = username,
                            phone = if (usePhone) account else null,
                            email = if (usePhone) null else account,
                            password = password,
                        )
                        success = "注册成功，请用新账号登录"
                        username = ""
                        account = ""
                        password = ""
                        confirm = ""
                    } catch (e: ApiException) {
                        error = e.message ?: "注册失败"
                    } catch (e: Exception) {
                        error = e.message ?: "网络错误，请稍后重试"
                    } finally {
                        loading = false
                    }
                }
            },
            enabled = !loading,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(if (loading) "提交中…" else "注册")
        }
    }
}

@Composable
private fun RecoverySection() {
    val container = LocalAppContainer.current
    val palette = LocalSleepPalette.current
    val scope = rememberCoroutineScope()

    var usePhone by rememberSaveable { mutableStateOf(true) }
    var account by rememberSaveable { mutableStateOf("") }
    var requestId by rememberSaveable { mutableStateOf<String?>(null) }
    var retrySeconds by rememberSaveable { mutableIntStateOf(0) }
    var code by rememberSaveable { mutableStateOf("") }
    var newPassword by rememberSaveable { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var success by remember { mutableStateOf<String?>(null) }

    // retry_after 倒计时
    LaunchedEffect(retrySeconds) {
        if (retrySeconds > 0) {
            kotlinx.coroutines.delay(1000)
            retrySeconds -= 1
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = usePhone,
                onClick = { usePhone = true },
                label = { Text("手机") },
            )
            FilterChip(
                selected = !usePhone,
                onClick = { usePhone = false },
                label = { Text("邮箱") },
            )
        }
        OutlinedTextField(
            value = account,
            onValueChange = { account = it },
            label = { Text(if (usePhone) "手机号" else "邮箱") },
            keyboardOptions = KeyboardOptions(keyboardType = if (usePhone) KeyboardType.Phone else KeyboardType.Email),
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedButton(
            onClick = {
                loading = true
                error = null
                success = null
                scope.launch {
                    try {
                        val response = container.accountStore.requestRecovery(
                            phone = if (usePhone) account else null,
                            email = if (usePhone) null else account,
                        )
                        requestId = response.requestId
                        retrySeconds = response.retryAfter
                        success = "验证码已发送，请查收"
                    } catch (e: ApiException) {
                        error = e.message ?: "发送失败"
                    } catch (e: Exception) {
                        error = e.message ?: "网络错误，请稍后重试"
                    } finally {
                        loading = false
                    }
                }
            },
            enabled = !loading && account.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(if (retrySeconds > 0) "重新发送（${retrySeconds}s）" else "发送验证码")
        }

        if (requestId != null) {
            OutlinedTextField(
                value = code,
                onValueChange = { code = it.take(6) },
                label = { Text("6 位验证码") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = newPassword,
                onValueChange = { newPassword = it },
                label = { Text("新密码（至少 8 位）") },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                modifier = Modifier.fillMaxWidth(),
            )
            Button(
                onClick = {
                    loading = true
                    error = null
                    success = null
                    scope.launch {
                        try {
                            val message = container.accountStore.confirmRecovery(
                                requestId = requestId!!,
                                code = code,
                                newPassword = newPassword,
                            )
                            success = message.ifBlank { "密码已重置，请用新密码重新登录" }
                        } catch (e: ApiException) {
                            error = e.message ?: "重置失败"
                        } catch (e: Exception) {
                            error = e.message ?: "网络错误，请稍后重试"
                        } finally {
                            loading = false
                        }
                    }
                },
                enabled = !loading && code.length == 6 && newPassword.length >= 8,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("重置密码")
            }
        }
        error?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = palette.rose)
        }
        success?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = palette.teal)
        }
    }
}
