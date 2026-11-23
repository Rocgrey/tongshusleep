package com.rocgrey.sleeptongshu.core.auth

import com.rocgrey.sleeptongshu.core.api.ApiClient
import com.rocgrey.sleeptongshu.core.api.LoginRequest
import com.rocgrey.sleeptongshu.core.api.LoginResponse
import com.rocgrey.sleeptongshu.core.api.MeResponse
import com.rocgrey.sleeptongshu.core.api.MessageResponse
import com.rocgrey.sleeptongshu.core.api.RecoveryConfirm
import com.rocgrey.sleeptongshu.core.api.RecoveryRequest
import com.rocgrey.sleeptongshu.core.api.RecoveryRequestResponse
import com.rocgrey.sleeptongshu.core.api.RegisterRequest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** 账号会话状态：与 iOS AccountStore 语义一致。 */
sealed interface AccountState {
    data object SignedOut : AccountState
    data object Restoring : AccountState
    data class SignedIn(val session: SavedSession) : AccountState
    data class Expired(val reason: String?) : AccountState
}

class AccountStore(private val sessionStore: SessionStore) {

    private val _state = MutableStateFlow<AccountState>(AccountState.Restoring)
    val state: StateFlow<AccountState> = _state

    @Volatile
    private var clientRef: ApiClient? = null

    val client: ApiClient
        get() = clientRef ?: error("ApiClient 尚未初始化")

    fun initialize(baseClientFactory: (token: String?, onUnauthorized: (String?, String) -> Unit) -> ApiClient) {
        val saved = sessionStore.load()
        if (saved == null || isExpired(saved)) {
            if (saved != null) {
                sessionStore.clear()
                _state.value = AccountState.Expired(null)
            } else {
                _state.value = AccountState.SignedOut
            }
            clientRef = baseClientFactory(null) { _, msg -> invalidate(msg) }
        } else {
            // 与 iOS 一致：恢复登录必须经 /auth/me 校验，校验在启动流程中执行
            clientRef = baseClientFactory(saved.accessToken) { _, msg -> invalidate(msg) }
            _state.value = AccountState.SignedIn(saved)
        }
    }

    fun isExpired(session: SavedSession, nowSec: Long = System.currentTimeMillis() / 1000): Boolean =
        nowSec >= session.expiresAt

    suspend fun restoreValidate() {
        val current = _state.value as? AccountState.SignedIn ?: return
        try {
            val me = client.get<MeResponse>("auth/me")
            val refreshed = SavedSession(
                user = MeUser(me.id, me.username, me.email, me.phone, me.createdAt),
                accessToken = current.session.accessToken,
                expiresAt = current.session.expiresAt,
            )
            sessionStore.save(SessionStore.SERVICE_ID, refreshed)
            _state.value = AccountState.SignedIn(refreshed)
        } catch (_: Exception) {
            // 网络失败保留凭证（与 iOS 断网不踢下线一致）；401 已由回调 invalidate
        }
    }

    suspend fun login(phone: String?, email: String?, password: String): MeUser {
        val response = client.post<LoginResponse>("auth/login", LoginRequest(phone.ifBlank { null }, email.ifBlank { null }, password))
        val me = client.get<MeResponse>("auth/me")
        val session = SavedSession(
            user = MeUser(me.id, me.username, me.email, me.phone, me.createdAt),
            accessToken = response.accessToken,
            expiresAt = response.expireAt,
        )
        sessionStore.save(SessionStore.SERVICE_ID, session)
        client.updateToken(response.accessToken)
        _state.value = AccountState.SignedIn(session)
        return session.user
    }

    suspend fun register(username: String, phone: String?, email: String?, password: String): String {
        val response = client.post<MessageResponse>(
            "auth/register",
            RegisterRequest(username, phone.ifBlank { null }, email.ifBlank { null }, password),
        )
        return response.message ?: "注册成功"
    }

    suspend fun logout() {
        try {
            client.postNoBody("auth/logout")
        } catch (_: Exception) {
            // 本地登出优先
        }
        invalidate(null)
    }

    fun invalidate(message: String?) {
        val current = _state.value as? AccountState.SignedIn ?: return
        sessionStore.clear()
        clientRef?.updateToken(null)
        _state.value = AccountState.Expired(message)
    }

    suspend fun requestRecovery(phone: String?, email: String?): RecoveryRequestResponse =
        client.post("auth/password-reset/request", RecoveryRequest(phone.ifBlank { null }, email.ifBlank { null }))

    suspend fun confirmRecovery(requestId: String, code: String, newPassword: String): String {
        val response = client.post<MessageResponse>(
            "auth/password-reset/confirm",
            RecoveryConfirm(requestId, code, newPassword),
        )
        return response.message ?: "密码已重置，请重新登录"
    }

    fun currentUser(): MeUser? =
        (_state.value as? AccountState.SignedIn)?.session?.user

    fun currentToken(): String? =
        (_state.value as? AccountState.SignedIn)?.session?.accessToken

    /** 每用户数据作用域（与 iOS serviceID|user:{id} 同语义），用于本地缓存分目录。 */
    fun userScope(): String {
        val user = currentUser()
        return "${SessionStore.SERVICE_ID}|user:${user?.id ?: 0}"
    }
}
