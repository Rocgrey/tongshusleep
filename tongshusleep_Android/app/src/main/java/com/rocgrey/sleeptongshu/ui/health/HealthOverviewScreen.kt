package com.rocgrey.sleeptongshu.ui.health

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.background
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rocgrey.sleeptongshu.LocalAppContainer
import com.rocgrey.sleeptongshu.LocalRootNav
import com.rocgrey.sleeptongshu.core.health.FitnessAge
import com.rocgrey.sleeptongshu.core.health.HealthConnectManager
import com.rocgrey.sleeptongshu.core.health.HealthSnapshot
import com.rocgrey.sleeptongshu.core.health.METRIC_META
import com.rocgrey.sleeptongshu.core.health.MetricMeta
import com.rocgrey.sleeptongshu.core.health.SnapshotStore
import com.rocgrey.sleeptongshu.core.sleep.SleepRecordMapper
import com.rocgrey.sleeptongshu.ui.theme.LocalSleepPalette
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/** 健康总览（对应 iOS HealthOverviewView）。 */
@Composable
fun HealthOverviewScreen() {
    val container = LocalAppContainer.current
    val context = LocalContext.current
    val palette = LocalSleepPalette.current
    val nav = LocalRootNav.current
    val scope = rememberCoroutineScope()
    val manager = remember { HealthConnectManager(context) }

    var sdkAvailable by remember { mutableStateOf(false) }
    var needsInstall by remember { mutableStateOf(false) }
    var granted by remember { mutableStateOf(emptySet<String>()) }
    var snapshot by remember { mutableStateOf<HealthSnapshot?>(null) }
    var refreshing by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var newCount by remember { mutableIntStateOf(0) }
    val autoSync by container.preferences.automaticHealthSync
        .collectAsStateWithLifecycle(initialValue = true)

    LaunchedEffect(Unit) {
        val status = HealthConnectClient.getSdkStatus(context)
        sdkAvailable = status == HealthConnectClient.SDK_AVAILABLE
        needsInstall = status == HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED
        snapshot = SnapshotStore.readSnapshot(context)
        granted = manager.grantedPermissions()
    }

    fun refresh() {
        if (refreshing) return
        refreshing = true
        scope.launch {
            try {
                val before = snapshot
                val next = manager.readOverview(days = 90)
                SnapshotStore.writeSnapshot(context, next)
                snapshot = next
                granted = manager.grantedPermissions()
                message = next.error
                val beforeCount = (before?.series?.values?.sumOf { it.days.size } ?: 0) +
                    (before?.sleepDays?.size ?: 0)
                val afterCount = next.series.values.sumOf { it.days.size } +
                    (next.sleepDays?.size ?: 0)
                newCount = (afterCount - beforeCount).coerceAtLeast(0)
                // 睡眠导入开关开启时，把每晚摘要转成 SleepRecord 入库（同 externalId 幂等）
                val autoSyncNow = container.preferences.automaticHealthSync.first()
                if (autoSyncNow && !next.sleepDays.isNullOrEmpty()) {
                    val dao = container.database.sleepRecordDao()
                    next.sleepDays.forEach { day ->
                        dao.upsert(SleepRecordMapper.toEntity(day.toSleepRecord()))
                    }
                }
            } catch (e: Exception) {
                message = "读取失败：${e.message}"
            } finally {
                refreshing = false
            }
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        PermissionController.createRequestPermissionResultContract(),
    ) { result ->
        granted = result
        if (result.isNotEmpty()) refresh()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "健康总览",
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = { nav.navigate("account") }) {
                Icon(Icons.Filled.Person, contentDescription = "账号")
            }
        }

        if (!sdkAvailable) {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        if (needsInstall) "设备尚未安装 Health Connect" else "此设备不支持 Health Connect",
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        "健康数据功能依赖 Health Connect 应用，请先安装或更新后重试。",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    if (needsInstall) {
                        Button(onClick = {
                            manager.installOrOpenIntent()?.let { intent ->
                                runCatching { context.startActivity(intent) }
                            }
                        }) {
                            Text("前往安装 Health Connect")
                        }
                    }
                }
            }
        } else if (granted.isEmpty()) {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text("尚未授权读取健康数据", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "需要授权睡眠、心率、血氧、步数等只读权限后才能读取。",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    Button(onClick = { permissionLauncher.launch(manager.permissions) }) {
                        Text("申请健康数据权限")
                    }
                }
            }
        }

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Button(
                        onClick = { refresh() },
                        enabled = sdkAvailable && !refreshing,
                    ) {
                        Text(if (refreshing) "读取中…" else "从系统健康读取")
                    }
                    if (refreshing) {
                        CircularProgressIndicator(
                            modifier = Modifier.width(20.dp).height(20.dp),
                        )
                    }
                }
                snapshot?.let { current ->
                    Text(
                        "最近读取：" + formatDateTime(current.readAt),
                        style = MaterialTheme.typography.bodySmall,
                    )
                    if (newCount > 0) {
                        Text(
                            "本次新增 $newCount 条数据",
                            style = MaterialTheme.typography.bodySmall,
                            color = palette.mint,
                        )
                    }
                }
                message?.let { error ->
                    Text(error, style = MaterialTheme.typography.bodySmall, color = palette.rose)
                }
            }
        }

        snapshot?.let { current ->
            // 最新读数列表
            val keyIds = listOf(
                "steps", "heart_rate", "oxygen_saturation",
                "resting_heart_rate", "hrv",
            )
            val readings = keyIds.mapNotNull { id ->
                current.series[id]?.days?.lastOrNull()?.let { id to it }
            }
            if (readings.isNotEmpty() || !current.sleepDays.isNullOrEmpty()) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text("最新读数", style = MaterialTheme.typography.titleMedium)
                        readings.forEach { (id, day) ->
                            val meta = METRIC_META.firstOrNull { it.id == id }
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text("${meta?.name ?: id}（${day.date}）")
                                Text(formatValue(day.value) + unitSuffix(meta))
                            }
                        }
                        current.sleepDays?.lastOrNull()?.let { day ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text("睡眠（${day.day}）")
                                Text(
                                    "${day.asleepMinutes / 60}小时${day.asleepMinutes % 60}分",
                                )
                            }
                        }
                    }
                }
            }

            // 身体年龄卡（FRIEND 参考 + 探索性）
            val vo2 = current.series["vo2_max"]?.days?.lastOrNull()?.value
            val exploratory = FitnessAge.exploratory(current)
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text("身体年龄估算", style = MaterialTheme.typography.titleMedium)
                    if (vo2 == null) {
                        Text(
                            "暂无最大摄氧量数据，无法估算身体年龄。",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                            Column {
                                Text("男性参考", style = MaterialTheme.typography.bodySmall)
                                Text(
                                    "${FitnessAge.bodyAgeFromVo2(vo2, male = true)} 岁",
                                    style = MaterialTheme.typography.headlineSmall,
                                )
                            }
                            Column {
                                Text("女性参考", style = MaterialTheme.typography.bodySmall)
                                Text(
                                    "${FitnessAge.bodyAgeFromVo2(vo2, male = false)} 岁",
                                    style = MaterialTheme.typography.headlineSmall,
                                )
                            }
                        }
                    }
                    Text(
                        FitnessAge.BODY_AGE_NOTE,
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.muted,
                    )
                    if (exploratory.age != null) {
                        Text(
                            "探索性年龄：${exploratory.age} 岁（近 7 天综合得分 " +
                                "${((exploratory.averageScore ?: 0.0) * 10).roundToInt() / 10.0}）",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        Text(
                            "参与指标：" + exploratory.usedItems.joinToString(separator = "、"),
                            style = MaterialTheme.typography.bodySmall,
                        )
                    } else {
                        Text(
                            "探索性年龄：近 7 天数据不足（同日至少需要 2 项指标）",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    Text(
                        exploratory.note,
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.muted,
                    )
                }
            }
        }

        Text("指标速览", style = MaterialTheme.typography.titleMedium)
        val gridItems = METRIC_META.mapNotNull { meta ->
            snapshot?.series?.get(meta.id)?.let { meta to it }
        }
        gridItems.chunked(2).forEach { rowItems ->
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                rowItems.forEach { (meta, series) ->
                    Card(
                        onClick = { nav.navigate("health/metric/${meta.id}") },
                        modifier = Modifier.weight(1f),
                    ) {
                        Column(
                            modifier = Modifier.padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text(meta.name, style = MaterialTheme.typography.bodySmall)
                            val latest = series.days.lastOrNull()
                            Text(
                                if (latest != null) {
                                    formatValue(latest.value) + unitSuffix(meta)
                                } else {
                                    "暂无数据"
                                },
                                style = MaterialTheme.typography.titleMedium,
                            )
                        }
                    }
                }
                if (rowItems.size == 1) Spacer(modifier = Modifier.weight(1f))
            }
        }
        if (gridItems.isEmpty()) {
            Text(
                "暂无指标数据，请先从系统健康读取。",
                style = MaterialTheme.typography.bodySmall,
                color = palette.muted,
            )
        }

        // 睡眠导入开关
        Card(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("自动导入睡眠", style = MaterialTheme.typography.titleSmall)
                    Text(
                        "读取成功后把系统健康睡眠写入睡眠记录（同一条记录幂等去重）。",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Switch(
                    checked = autoSync,
                    onCheckedChange = { checked ->
                        scope.launch { container.preferences.setAutomaticHealthSync(checked) }
                    },
                )
            }
        }
    }
}

private fun formatDateTime(epochMs: Long): String =
    LocalDateTime.ofInstant(Instant.ofEpochMilli(epochMs), ZoneId.systemDefault())
        .format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm"))

private fun unitSuffix(meta: MetricMeta?): String =
    meta?.unit?.takeIf { it.isNotEmpty() }?.let { " $it" } ?: ""

private fun formatValue(value: Double): String {
    val rounded = (value * 10).roundToInt() / 10.0
    return if (rounded == rounded.toLong().toDouble()) {
        rounded.toLong().toString()
    } else {
        rounded.toString()
    }
}
