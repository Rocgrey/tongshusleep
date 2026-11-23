package com.rocgrey.sleeptongshu.core.api

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** 与后端契约严格对齐；日期 yyyy-MM-dd，日期时间 yyyy-MM-dd HH:mm:ss。 */

@Serializable
data class LoginRequest(
    val phone: String? = null,
    val email: String? = null,
    val password: String,
)

@Serializable
data class LoginResponse(
    @SerialName("access_token") val accessToken: String,
    @SerialName("token_type") val tokenType: String,
    @SerialName("expire_at") val expireAt: Long,
)

@Serializable
data class RegisterRequest(
    val username: String,
    val phone: String? = null,
    val email: String? = null,
    val password: String,
)

@Serializable
data class MessageResponse(val message: String? = null)

@Serializable
data class MeResponse(
    val id: Long,
    val username: String,
    val email: String? = null,
    val phone: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
)

@Serializable
data class RecoveryRequest(val phone: String? = null, val email: String? = null)

@Serializable
data class RecoveryRequestResponse(
    @SerialName("request_id") val requestId: String,
    @SerialName("expires_at") val expiresAt: String,
    @SerialName("retry_after") val retryAfter: Int,
    val message: String? = null,
)

@Serializable
data class RecoveryConfirm(
    @SerialName("request_id") val requestId: String,
    val code: String,
    @SerialName("new_password") val newPassword: String,
)

@Serializable
data class SleepRecordUpload(
    @SerialName("record_date") val recordDate: String,
    @SerialName("sleep_start_time") val sleepStartTime: String,
    @SerialName("sleep_end_time") val sleepEndTime: String,
    @SerialName("total_duration_minutes") val totalDurationMinutes: Int? = null,
    @SerialName("sleep_score") val sleepScore: Int? = null,
    @SerialName("deep_sleep_minutes") val deepSleepMinutes: Int? = null,
    @SerialName("light_sleep_minutes") val lightSleepMinutes: Int? = null,
    @SerialName("rem_minutes") val remMinutes: Int? = null,
    @SerialName("awake_times") val awakeTimes: Int? = null,
    @SerialName("ais_score") val aisScore: Int? = null,
    val notes: String? = null,
    @SerialName("extra_meta") val extraMeta: String? = null,
)

@Serializable
data class SleepRecordAck(val id: Long, @SerialName("user_id") val userId: Long)

@Serializable
data class StepUploadRequest(
    @SerialName("record_date") val recordDate: String,
    val steps: Int,
    val source: String,
    @SerialName("source_id") val sourceId: String? = null,
    @SerialName("data_time") val dataTime: String,
    val timezone: String,
)

@Serializable
data class StepRecordRow(
    val id: Long,
    @SerialName("user_id") val userId: Long,
    @SerialName("record_date") val recordDate: String,
    val steps: Int,
    val source: String,
)

@Serializable
data class StepUploadResponse(
    @SerialName("record_id") val recordId: Long,
    val applied: Boolean,
    val reason: String? = null,
    val record: StepRecordRow? = null,
)

@Serializable
data class StepDayRow(
    @SerialName("record_date") val recordDate: String,
    val steps: Int,
    val source: String,
    @SerialName("source_id") val sourceId: String? = null,
    @SerialName("data_time") val dataTime: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("is_today") val isToday: Boolean = false,
    @SerialName("is_real_zero") val isRealZero: Boolean = false,
)

@Serializable
data class StepSummary(
    @SerialName("start_date") val startDate: String? = null,
    @SerialName("end_date") val endDate: String? = null,
    @SerialName("days_in_range") val daysInRange: Int? = null,
    @SerialName("days_with_record") val daysWithRecord: Int? = null,
    @SerialName("days_real_zero") val daysRealZero: Int? = null,
    @SerialName("days_missing") val daysMissing: Int? = null,
    @SerialName("range_incomplete") val rangeIncomplete: Boolean? = null,
    @SerialName("total_steps") val totalSteps: Long? = null,
    @SerialName("avg_steps") val avgSteps: Double? = null,
)

@Serializable
data class StepRecordsResponse(val days: List<StepDayRow> = emptyList(), val summary: StepSummary? = null)

@Serializable
data class SyncCapabilities(
    @SerialName("device_sync_version") val deviceSyncVersion: Int,
    val idempotent: Boolean,
)

@Serializable
data class VitalRow(
    val id: String,
    val kind: String,
    val value: Double,
    @SerialName("record_at") val recordAt: String,
    val unit: String,
)

@Serializable
data class StageSpan(val stage: String, val start: String, val end: String)

@Serializable
data class SyncDetails(
    val source: String,
    @SerialName("time_zone") val timeZone: String,
    val start: String? = null,
    val end: String? = null,
    @SerialName("average_heart_rate") val averageHeartRate: Double? = null,
    @SerialName("average_spo2") val averageSpO2: Double? = null,
    @SerialName("average_respiratory_rate") val averageRespiratoryRate: Double? = null,
    @SerialName("average_hrv") val averageHrv: Double? = null,
    @SerialName("average_stress") val averageStress: Double? = null,
    @SerialName("average_systolic") val averageSystolic: Double? = null,
    @SerialName("average_diastolic") val averageDiastolic: Double? = null,
    @SerialName("sleep_efficiency") val sleepEfficiency: Double? = null,
    @SerialName("awake_minutes") val awakeMinutes: Int? = null,
    @SerialName("sleep_input_minutes") val sleepInputMinutes: Int? = null,
    @SerialName("average_basis") val averageBasis: String? = null,
    val stages: List<StageSpan> = emptyList(),
)

@Serializable
data class SleepUploadPayload(
    @SerialName("record_date") val recordDate: String? = null,
    @SerialName("sleep_start_time") val sleepStartTime: String? = null,
    @SerialName("sleep_end_time") val sleepEndTime: String? = null,
    @SerialName("total_duration_minutes") val totalDurationMinutes: Int? = null,
    @SerialName("sleep_score") val sleepScore: Int? = null,
    @SerialName("deep_sleep_minutes") val deepSleepMinutes: Int? = null,
    @SerialName("light_sleep_minutes") val lightSleepMinutes: Int? = null,
    @SerialName("rem_minutes") val remMinutes: Int? = null,
    @SerialName("awake_times") val awakeTimes: Int? = null,
    @SerialName("ais_score") val aisScore: Int? = null,
    val notes: String? = null,
)

@Serializable
data class StepUploadPayload(
    @SerialName("record_date") val recordDate: String,
    val steps: Int,
    val source: String,
    @SerialName("source_id") val sourceId: String? = null,
    @SerialName("data_time") val dataTime: String,
    val timezone: String,
)

@Serializable
data class DeviceSyncRequest(
    @SerialName("record_key") val recordKey: String,
    val kind: String,
    @SerialName("record_date") val recordDate: String,
    @SerialName("revision_at") val revisionAt: String,
    @SerialName("device_id") val deviceId: String? = null,
    @SerialName("device_name") val deviceName: String? = null,
    val sleep: SleepUploadPayload? = null,
    val steps: StepUploadPayload? = null,
    val vitals: List<VitalRow> = emptyList(),
    val details: SyncDetails? = null,
)

@Serializable
data class DeviceSyncResponse(val id: Long, @SerialName("user_id") val userId: Long, val applied: Boolean)

@Serializable
data class RawSensorPacket(
    @SerialName("sensorType") val sensorType: Int,
    @SerialName("sensorSeconds") val sensorSeconds: Long,
    @SerialName("sensorSeq") val sensorSeq: Int? = null,
    @SerialName("sensorDataList") val sensorDataList: List<Long> = emptyList(),
    @SerialName("receivedAt") val receivedAt: String? = null,
    @SerialName("notificationBase64") val notificationBase64: String? = null,
)

@Serializable
data class RawSensorBatchRequest(
    @SerialName("upload_id") val uploadId: String,
    @SerialName("capture_id") val captureId: String,
    @SerialName("device_id") val deviceId: String,
    @SerialName("device_name") val deviceName: String,
    val source: String = "android_ble",
    @SerialName("timestamp_encoding") val timestampEncoding: String = "device_seconds_unverified",
    val packets: List<RawSensorPacket>,
)

@Serializable
data class RawSensorBatchResponse(
    val id: Long,
    @SerialName("user_id") val userId: Long,
    @SerialName("upload_id") val uploadId: String,
    @SerialName("packet_count") val packetCount: Int,
    val applied: Boolean,
)

@Serializable
data class ClassroomItem(
    val id: String,
    val title: String,
    val summary: String? = null,
    val body: String? = null,
    val kind: String,
    val category: String? = null,
    val cover: String? = null,
    @SerialName("media_url") val mediaUrl: String? = null,
    val duration: Double? = null,
    @SerialName("preview_seconds") val previewSeconds: Int? = null,
    @SerialName("parent_id") val parentId: String? = null,
    @SerialName("sort_order") val sortOrder: Int = 0,
    val route: String? = null,
    val featured: Boolean = false,
    @SerialName("updated_at") val updatedAt: Long? = null,
    @SerialName("external_url") val externalUrl: String? = null,
)

@Serializable
data class ContentItemsResponse(
    val items: List<ClassroomItem> = emptyList(),
    val total: Int = 0,
    @SerialName("catalog_initialized") val catalogInitialized: Boolean? = null,
)

@Serializable
data class NotificationPreferencesUpdate(
    val daily: Boolean,
    val bedtime: Boolean,
    @SerialName("daily_minute") val dailyMinute: Int,
    @SerialName("bedtime_minute") val bedtimeMinute: Int,
    val timezone: String,
)

@Serializable
data class DeviceRegisterRequest(val token: String, val environment: String)

@Serializable
data class DeviceUnregisterRequest(val token: String)
