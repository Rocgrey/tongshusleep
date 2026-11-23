package com.rocgrey.sleeptongshu.core.reminders

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.rocgrey.sleeptongshu.BuildConfig
import com.rocgrey.sleeptongshu.MainActivity
import com.rocgrey.sleeptongshu.core.api.ApiClient
import com.rocgrey.sleeptongshu.core.api.NotificationPreferencesUpdate
import com.rocgrey.sleeptongshu.core.auth.SessionStore
import com.rocgrey.sleeptongshu.core.data.AppPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.LocalDateTime
import java.time.LocalTime

/**
 * 本地提醒调度（对应 iOS SleepReminders / ReminderService）：
 * - 两个 UniqueWork：daily 与 bedtime，OneTimeWorkRequest + initialDelay 指向下一个触发时刻；
 *   Worker 触发后自行重排下一次（等效 PeriodicWorkRequest 24 小时，且避免首日双触发）。
 * - 开关关闭时 cancelUniqueWork。
 * - 远程推送偏好：开关开启且已登录时 PUT notifications/preferences；
 *   FCM 未集成（token 为空串）时不注册设备，UI 层提示。
 */
object ReminderScheduler {
    const val DAILY_WORK = "tongshu-daily-reminder"
    const val BEDTIME_WORK = "tongshu-bedtime-reminder"
    const val CHANNEL_ID = "reminders"
    const val DAILY_NOTIFICATION_ID = 1001
    const val BEDTIME_NOTIFICATION_ID = 1002
    const val KEY_KIND = "kind"
    const val KIND_DAILY = "daily"
    const val KIND_BEDTIME = "bedtime"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** Application.onCreate 调用：按当前偏好安装/取消两个提醒。 */
    fun install(context: Context) {
        val appContext = context.applicationContext
        scope.launch { reschedule(appContext) }
    }

    /** 设置变更后重排（UI 层调用），同时同步远程推送偏好。 */
    suspend fun reschedule(context: Context) {
        val appContext = context.applicationContext
        val prefs = AppPreferences(appContext)
        val daily = prefs.dailyReminder.first()
        val bedtime = prefs.bedtimeReminder.first()
        val dailyMinute = prefs.dailyMinute.first()
        val bedtimeMinute = prefs.bedtimeMinute.first()
        val remote = prefs.remoteReminders.first()

        val wm = WorkManager.getInstance(appContext)
        scheduleOne(wm, KIND_DAILY, DAILY_WORK, daily, dailyMinute)
        scheduleOne(wm, KIND_BEDTIME, BEDTIME_WORK, bedtime, bedtimeMinute)
        syncRemotePreferences(appContext, daily, bedtime, dailyMinute, bedtimeMinute, remote)
    }

    private fun scheduleOne(
        wm: WorkManager,
        kind: String,
        uniqueName: String,
        enabled: Boolean,
        minuteOfDay: Int,
    ) {
        if (!enabled) {
            wm.cancelUniqueWork(uniqueName)
            return
        }
        val delay = delayUntilNext(minuteOfDay)
        val request = OneTimeWorkRequest.Builder(ReminderWorker::class.java)
            .setInitialDelay(delay)
            .setInputData(androidx.work.workDataOf(KEY_KIND to kind))
            .build()
        wm.enqueueUniqueWork(uniqueName, ExistingWorkPolicy.REPLACE, request)
    }

    /** 距下一个 minuteOfDay 触发时刻的延时（含 0 点归一）。 */
    fun delayUntilNext(minuteOfDay: Int): Duration {
        val safe = minuteOfDay.coerceIn(0, 24 * 60 - 1)
        val time = LocalTime.of(safe / 60, safe % 60)
        val now = LocalDateTime.now()
        var next = now.toLocalDate().atTime(time)
        if (!next.isAfter(now)) next = next.plusDays(1)
        return Duration.between(now, next)
    }

    /**
     * 远程推送偏好：开关开启且已登录时 PUT notifications/preferences。
     * 本工程未集成 FCM SDK，设备注册（POST notifications/devices）跳过；
     * 与 iOS APNs 未配置状态一致，UI 层需说明。
     */
    private suspend fun syncRemotePreferences(
        context: Context,
        daily: Boolean,
        bedtime: Boolean,
        dailyMinute: Int,
        bedtimeMinute: Int,
        remote: Boolean,
    ) {
        if (!remote) return
        val session = SessionStore(context).load() ?: return
        if (session.expiresAt <= System.currentTimeMillis() / 1000) return
        try {
            val client = ApiClient(
                baseUrl = BuildConfig.SLEEP_API_BASE_URL,
                gatewayCode = BuildConfig.SLEEP_GATEWAY_SHARE_CODE,
                accessToken = session.accessToken,
            )
            client.put(
                "notifications/preferences",
                NotificationPreferencesUpdate(
                    daily = daily,
                    bedtime = bedtime,
                    dailyMinute = dailyMinute,
                    bedtimeMinute = bedtimeMinute,
                    timezone = "Asia/Shanghai",
                ),
            )
            // FCM token 为空串时不调用设备注册（未集成 FCM SDK）
        } catch (_: Exception) {
            // 远程同步失败不影响本地提醒
        }
    }
}

/** 触发提醒的 Worker：发通知并在结束后重排下一次（等效 24 小时周期）。 */
class ReminderWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val context = applicationContext
        val kind = inputData.getString(ReminderScheduler.KEY_KIND) ?: ReminderScheduler.KIND_DAILY
        val prefs = AppPreferences(context)
        val enabled = if (kind == ReminderScheduler.KIND_BEDTIME) {
            prefs.bedtimeReminder.first()
        } else {
            prefs.dailyReminder.first()
        }
        if (enabled) notify(context, kind)
        // 通知或跳过后，重排下一次触发
        ReminderScheduler.reschedule(context)
        return Result.success()
    }

    private suspend fun notify(context: Context, kind: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(ReminderScheduler.CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    ReminderScheduler.CHANNEL_ID,
                    "睡眠提醒",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply { description = "每日阅读与睡前提醒" },
            )
        }
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pending = PendingIntent.getActivity(
            context,
            kind.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val (title, text) = if (kind == ReminderScheduler.KIND_BEDTIME) {
            "该准备休息啦" to "夜深了，点击打开 App，用晚安卡和助眠练习放松入睡。"
        } else {
            "睡眠小课堂" to "今天的内容已更新，点击打开 App 继续学习。"
        }
        val notification = NotificationCompat.Builder(context, ReminderScheduler.CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        try {
            val id = if (kind == ReminderScheduler.KIND_BEDTIME) {
                ReminderScheduler.BEDTIME_NOTIFICATION_ID
            } else {
                ReminderScheduler.DAILY_NOTIFICATION_ID
            }
            NotificationManagerCompat.from(context).notify(id, notification)
        } catch (_: SecurityException) {
        }
    }
}

/** 兜底广播接收器（manifest 已注册）：被触发时重排。 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val appContext = context.applicationContext
        ReminderScheduler.install(appContext)
    }
}
