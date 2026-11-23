package com.rocgrey.sleeptongshu.core.auth

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** 与 iOS KeychainAccountStorage 对齐：仅本机、解锁后可读。 */
@Serializable
data class SavedSession(
    val user: MeUser,
    val accessToken: String,
    val expiresAt: Long,
)

@Serializable
data class MeUser(
    val id: Long,
    val username: String,
    val email: String? = null,
    val phone: String? = null,
    val createdAt: String? = null,
)

@Serializable
private data class StoredAccount(
    val serviceId: String,
    val session: SavedSession,
)

class SessionStore(context: Context) {
    private val json = Json { ignoreUnknownKeys = true }

    private val prefs by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "tongshu_account_session_v1",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    fun load(): SavedSession? = try {
        prefs.getString(KEY, null)?.let { json.decodeFromString<StoredAccount>(it).session }
    } catch (_: Exception) {
        null
    }

    fun save(serviceId: String, session: SavedSession) {
        prefs.edit().putString(KEY, json.encodeToString(StoredAccount(serviceId, session))).apply()
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        private const val KEY = "session-v1"
        const val SERVICE_ID = "tongshusleep-android"
    }
}
