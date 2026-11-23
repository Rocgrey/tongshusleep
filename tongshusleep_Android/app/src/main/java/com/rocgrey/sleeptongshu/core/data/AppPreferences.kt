package com.rocgrey.sleeptongshu.core.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.rocgrey.sleeptongshu.ui.theme.AppAppearance
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "tongshu_prefs")

/** 偏好设置：key 与 iOS AppStorage 同名。 */
class AppPreferences(private val context: Context) {

    private object Keys {
        val APP_APPEARANCE = stringPreferencesKey("appAppearance")
        val SLEEP_GOAL_HOURS = floatPreferencesKey("sleepGoalHours")
        val AUTOMATIC_HEALTH_SYNC = booleanPreferencesKey("automaticHealthSyncV1")
        val PHONE_TRACKING_ENABLED = booleanPreferencesKey("phoneTrackingEnabled")
        val SAVE_CANDIDATE_VOICE = booleanPreferencesKey("saveCandidateVoice")
        val DAILY_REMINDER = booleanPreferencesKey("dailyReminder")
        val BEDTIME_REMINDER = booleanPreferencesKey("bedtimeReminder")
        val DAILY_MINUTE = intPreferencesKey("dailyMinute")
        val BEDTIME_MINUTE = intPreferencesKey("bedtimeMinute")
        val REMOTE_REMINDERS = booleanPreferencesKey("remoteReminders")
        val HAS_SEEDED_DEMO = booleanPreferencesKey("hasSeededDemoV1")
        val HEALTH_PROFILE = stringPreferencesKey("healthManualProfile")
        val HEALTH_REF_AGE = intPreferencesKey("healthReferenceAge")
        val HEALTH_REF_SEX = stringPreferencesKey("healthReferenceSex")
    }

    val appearance: Flow<AppAppearance> =
        context.dataStore.data.map { AppAppearance.fromKey(it[Keys.APP_APPEARANCE]) }

    suspend fun setAppearance(value: AppAppearance) {
        context.dataStore.edit { it[Keys.APP_APPEARANCE] = value.key }
    }

    val sleepGoalHours: Flow<Float> =
        context.dataStore.data.map { it[Keys.SLEEP_GOAL_HOURS] ?: 8f }

    suspend fun setSleepGoalHours(value: Float) {
        context.dataStore.edit { it[Keys.SLEEP_GOAL_HOURS] = value }
    }

    val automaticHealthSync: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.AUTOMATIC_HEALTH_SYNC] ?: true }

    suspend fun setAutomaticHealthSync(value: Boolean) {
        context.dataStore.edit { it[Keys.AUTOMATIC_HEALTH_SYNC] = value }
    }

    val phoneTrackingEnabled: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.PHONE_TRACKING_ENABLED] ?: false }

    suspend fun setPhoneTrackingEnabled(value: Boolean) {
        context.dataStore.edit { it[Keys.PHONE_TRACKING_ENABLED] = value }
    }

    val saveCandidateVoice: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.SAVE_CANDIDATE_VOICE] ?: false }

    suspend fun setSaveCandidateVoice(value: Boolean) {
        context.dataStore.edit { it[Keys.SAVE_CANDIDATE_VOICE] = value }
    }

    val dailyReminder: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.DAILY_REMINDER] ?: false }

    val bedtimeReminder: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.BEDTIME_REMINDER] ?: false }

    val dailyMinute: Flow<Int> = context.dataStore.data.map { it[Keys.DAILY_MINUTE] ?: 1200 }
    val bedtimeMinute: Flow<Int> = context.dataStore.data.map { it[Keys.BEDTIME_MINUTE] ?: 1320 }

    val remoteReminders: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.REMOTE_REMINDERS] ?: false }

    suspend fun setReminders(daily: Boolean, bedtime: Boolean, dailyMin: Int, bedtimeMin: Int, remote: Boolean) {
        context.dataStore.edit {
            it[Keys.DAILY_REMINDER] = daily
            it[Keys.BEDTIME_REMINDER] = bedtime
            it[Keys.DAILY_MINUTE] = dailyMin
            it[Keys.BEDTIME_MINUTE] = bedtimeMin
            it[Keys.REMOTE_REMINDERS] = remote
        }
    }

    val hasSeededDemo: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.HAS_SEEDED_DEMO] ?: false }

    suspend fun setHasSeededDemo(value: Boolean) {
        context.dataStore.edit { it[Keys.HAS_SEEDED_DEMO] = value }
    }
}
