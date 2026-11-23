package com.rocgrey.sleeptongshu.core.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/** 开机自启动：重排提醒（BOOT_COMPLETED）。 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val appContext = context.applicationContext
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                ReminderScheduler.reschedule(appContext)
            } catch (_: Exception) {
                // 开机重排失败静默处理，App 启动时仍会 install
            } finally {
                pending.finish()
            }
        }
    }
}
