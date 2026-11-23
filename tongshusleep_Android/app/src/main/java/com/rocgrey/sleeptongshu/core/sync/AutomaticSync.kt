package com.rocgrey.sleeptongshu.core.sync

import android.content.Context
import com.rocgrey.sleeptongshu.core.api.ApiClient
import com.rocgrey.sleeptongshu.core.api.DeviceSyncRequest
import com.rocgrey.sleeptongshu.core.api.DeviceSyncResponse
import com.rocgrey.sleeptongshu.core.api.SleepRecordUpload
import com.rocgrey.sleeptongshu.core.api.SleepRecordAck
import com.rocgrey.sleeptongshu.core.api.StageSpan
import com.rocgrey.sleeptongshu.core.api.SyncCapabilities
import com.rocgrey.sleeptongshu.core.api.SyncDetails
import com.rocgrey.sleeptongshu.core.api.VitalRow
import com.rocgrey.sleeptongshu.core.sleep.SleepFormat
import com.rocgrey.sleeptongshu.core.sleep.SleepRecord
import com.rocgrey.sleeptongshu.core.sleep.SleepStage
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.time.Instant
import java.time.ZoneId

/**
 * 自动同步：与 iOS AutomaticSync.swift 同语义。
 * - 先调 sync-capabilities（版本须 ==1 且幂等）才启用
 * - revision_at 先持久化再发送，中断不丢指印
 * - 回执按 recordKey 存本地
 */
class AutomaticSync(
    private val context: Context,
    private val clientProvider: () -> ApiClient,
) {
    private val json = Json { ignoreUnknownKeys = true }

    @Volatile
    private var capabilitiesOk: Boolean? = null

    suspend fun checkCapabilities(): Boolean {
        val cached = capabilitiesOk
        if (cached != null) return cached
        return try {
            val caps = clientProvider().get<SyncCapabilities>("health/sync-capabilities")
            (caps.deviceSyncVersion == 1 && caps.idempotent).also { capabilitiesOk = it }
        } catch (_: Exception) {
            false
        }
    }

    private fun stampsFile(scope: String) =
        File(context.filesDir, "AutomaticSync/${sha256(scope)}.json").apply { parentFile?.mkdirs() }

    @Serializable
    data class SyncStamps(val stamps: Map<String, String> = emptyMap())

    fun readStamps(scope: String): SyncStamps = try {
        val file = stampsFile(scope)
        if (file.exists()) json.decodeFromString(SyncStamps.serializer(), file.readText()) else SyncStamps()
    } catch (_: Exception) {
        SyncStamps()
    }

    fun writeStamp(scope: String, recordKey: String, revisionAt: String) {
        val stamps = readStamps(scope).stamps + (recordKey to revisionAt)
        runCatching {
            stampsFile(scope).writeText(json.encodeToString(SyncStamps.serializer(), SyncStamps(stamps)))
        }
    }

    fun sha256(value: String): String =
        java.security.MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    /** 把一条睡眠记录推送到 device-sync（kind=sleep）。 */
    suspend fun pushSleepRecord(
        record: SleepRecord,
        scope: String,
        deviceId: String = "phone",
        deviceName: String = "Android 手机",
    ): DeviceSyncResponse {
        val recordKey = "sleep:${record.source.key}:${record.id}"
        val revisionAt = Instant.now().atZone(ZoneId.systemDefault()).format(SleepFormat.recordDateTime)
        // 先持久化再发送（中断恢复语义）
        writeStamp(scope, recordKey, revisionAt)

        val stages = record.segments.map {
            StageSpan(
                stage = it.stage.lowercase(),
                start = Instant.ofEpochMilli(it.start).atZone(record.zoneId).format(SleepFormat.recordDateTime),
                end = Instant.ofEpochMilli(it.end).atZone(record.zoneId).format(SleepFormat.recordDateTime),
            )
        }
        val details = SyncDetails(
            source = record.source.key,
            timeZone = record.zoneId.id,
            start = record.start.atZone(record.zoneId).format(SleepFormat.recordDateTime),
            end = record.end.atZone(record.zoneId).format(SleepFormat.recordDateTime),
            averageHeartRate = record.averageHeartRate,
            averageSpO2 = record.averageSpO2,
            averageRespiratoryRate = record.averageRespiratoryRate,
            sleepEfficiency = record.efficiency,
            awakeMinutes = record.awakeMinutes.takeIf { it > 0 },
            stages = stages,
        )
        val startLocal = record.start.atZone(record.zoneId)
        val endLocal = record.end.atZone(record.zoneId)
        return clientProvider().post(
            "health/device-sync",
            DeviceSyncRequest(
                recordKey = recordKey,
                kind = "sleep",
                recordDate = record.day.format(SleepFormat.recordDate),
                revisionAt = revisionAt,
                deviceId = deviceId,
                deviceName = deviceName,
                sleep = com.rocgrey.sleeptongshu.core.api.SleepUploadPayload(
                    recordDate = record.day.format(SleepFormat.recordDate),
                    sleepStartTime = startLocal.format(SleepFormat.recordDateTime),
                    sleepEndTime = endLocal.format(SleepFormat.recordDateTime),
                    totalDurationMinutes = record.asleepMinutes.takeIf { it > 0 },
                    deepSleepMinutes = record.minutesOf(setOf(SleepStage.DEEP)).takeIf { it > 0 },
                    lightSleepMinutes = record.minutesOf(setOf(SleepStage.LIGHT)).takeIf { it > 0 },
                    remMinutes = record.minutesOf(setOf(SleepStage.REM)).takeIf { it > 0 },
                    awakeTimes = record.awakenings.takeIf { it > 0 },
                    aisScore = record.metadata.aisScore,
                    notes = record.note,
                ),
                details = details,
            ),
        )
    }

    /** 兼容旧接口：health/sleep-record 直传（iOS SleepUploadView）。 */
    suspend fun uploadLegacy(record: SleepRecord): SleepRecordAck {
        val zone = record.zoneId
        return clientProvider().post(
            "health/sleep-record",
            SleepRecordUpload(
                recordDate = record.day.format(SleepFormat.recordDate),
                sleepStartTime = record.start.atZone(zone).format(SleepFormat.recordDateTime),
                sleepEndTime = record.end.atZone(zone).format(SleepFormat.recordDateTime),
                totalDurationMinutes = record.asleepMinutes.takeIf { it > 0 },
                deepSleepMinutes = record.minutesOf(setOf(SleepStage.DEEP)).takeIf { it > 0 },
                lightSleepMinutes = record.minutesOf(setOf(SleepStage.LIGHT)).takeIf { it > 0 },
                remMinutes = record.minutesOf(setOf(SleepStage.REM)).takeIf { it > 0 },
                awakeTimes = record.awakenings.takeIf { it > 0 },
                aisScore = record.metadata.aisScore,
                notes = record.note,
            ),
        )
    }

    /** 设备体征行上传（kind=vitals）。 */
    suspend fun pushVitals(
        recordKey: String,
        recordDate: String,
        vitals: List<VitalRow>,
        scope: String,
        deviceId: String,
        deviceName: String,
    ): DeviceSyncResponse {
        val revisionAt = Instant.now().atZone(ZoneId.systemDefault()).format(SleepFormat.recordDateTime)
        writeStamp(scope, recordKey, revisionAt)
        return clientProvider().post(
            "health/device-sync",
            DeviceSyncRequest(
                recordKey = recordKey,
                kind = "vitals",
                recordDate = recordDate,
                revisionAt = revisionAt,
                deviceId = deviceId,
                deviceName = deviceName,
                vitals = vitals,
            ),
        )
    }
}
