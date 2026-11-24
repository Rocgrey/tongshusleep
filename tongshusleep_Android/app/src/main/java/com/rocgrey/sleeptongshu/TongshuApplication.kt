package com.rocgrey.sleeptongshu

import android.app.Application
import com.rocgrey.sleeptongshu.core.api.ApiClient
import com.rocgrey.sleeptongshu.core.auth.AccountStore
import com.rocgrey.sleeptongshu.core.auth.SessionStore
import com.rocgrey.sleeptongshu.core.classroom.ContentStore
import com.rocgrey.sleeptongshu.core.data.AppDatabase
import com.rocgrey.sleeptongshu.core.data.AppPreferences

/** 全局服务定位器：替代 iOS 的环境对象注入。 */
class AppContainer(app: Application) {
    val database: AppDatabase = AppDatabase.get(app)
    val preferences: AppPreferences = AppPreferences(app)
    val sessionStore: SessionStore = SessionStore(app)
    val accountStore: AccountStore = AccountStore(sessionStore)

    private val appContext = app.applicationContext

    val apiClient: ApiClient = ApiClient(
        baseUrl = com.rocgrey.sleeptongshu.BuildConfig.SLEEP_API_BASE_URL,
        gatewayCode = com.rocgrey.sleeptongshu.BuildConfig.SLEEP_GATEWAY_SHARE_CODE,
        accessToken = null,
        onUnauthorized = { _, msg -> accountStore.invalidate(msg) },
    )

    val contentStore: ContentStore = ContentStore(appContext) { apiClient }
}

/** CompositionLocal 入口。 */
val LocalAppContainer = androidx.compose.runtime.staticCompositionLocalOf<AppContainer> {
    error("AppContainer 未提供")
}

class TongshuApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        // 注入云端能力（登录判定/上传客户端）给 Iwown 通道
        com.rocgrey.sleeptongshu.core.ble.IwownSdkManager.attach(container)
        try {
            com.rocgrey.sleeptongshu.core.ble.IwownSdkManager.init(this)
        } catch (e: Exception) {
            // SDK 初始化失败不影响 App 其他功能
            android.util.Log.e("TongshuApp", "Iwown SDK init failed", e)
        }
        container.accountStore.initialize { token, onUnauthorized ->
            ApiClient(
                baseUrl = com.rocgrey.sleeptongshu.BuildConfig.SLEEP_API_BASE_URL,
                gatewayCode = com.rocgrey.sleeptongshu.BuildConfig.SLEEP_GATEWAY_SHARE_CODE,
                accessToken = token,
                onUnauthorized = onUnauthorized,
            )
        }
        // 安装本地提醒（对应 iOS ReminderService.install）
        com.rocgrey.sleeptongshu.core.reminders.ReminderScheduler.install(this)
    }
}
