package com.rocgrey.sleeptongshu.core.steps

import android.content.Context
import com.rocgrey.sleeptongshu.core.api.ApiClient
import com.rocgrey.sleeptongshu.core.api.StepDayRow
import com.rocgrey.sleeptongshu.core.api.StepRecordsResponse
import com.rocgrey.sleeptongshu.core.api.StepUploadRequest
import com.rocgrey.sleeptongshu.core.api.StepUploadResponse
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.security.MessageDigest
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** 服务器按 Asia/Shanghai 分日（与 iOS StepDates 一致）。 */
val STEP_ZONE: ZoneId = ZoneId.of("Asia/Shanghai")
val STEP_DATE_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")

/** 三类步数来源，与 iOS AccountStepsSection 分段一致。 */
enum class StepsSection(val label: String) {
    DEVICE("蓝牙设备"),
    CLOUD("账号云端"),
    HEALTH("系统健康"),
}

data class StepsSnapshot(
    val days: List<StepDayRow>,
    val totalSteps: Long,
    val avgSteps: Double?,
    val daysWithRecord: Int,
    val daysRealZero: Int,
    val daysMissing: Int,
    val rangeIncomplete: Boolean,
)

/** 账号云端步数：逐日 upsert 上传后再 fetch；重复同步不累加。 */
class StepSync(
    private val context: Context,
    private val clientProvider: () -> ApiClient,
) {
    private val json = Json { ignoreUnknownKeys = true }

    fun cacheFile(scope: String): File =
        File(context.filesDir, "AccountSteps/${sha256(scope)}.json").apply { parentFile?.mkdirs() }

    fun sha256(value: String): String =
        MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    /** 上传一天步数（healthkit / wearable 来源）。 */
    suspend fun uploadDay(
        date: LocalDate,
        steps: Int,
        source: String,
        dataTime: String,
        timezone: String = "Asia/Shanghai",
        sourceId: String? = null,
    ): StepUploadResponse {
        require(steps in 0..200_000) { "步数超出范围" }
        val response = clientProvider().post<StepUploadResponse>(
            "health/step-record",
            StepUploadRequest(
                recordDate = date.format(STEP_DATE_FORMAT),
                steps = steps,
                source = source,
                sourceId = sourceId,
                dataTime = dataTime,
                timezone = timezone,
            ),
        )
        return response
    }

    suspend fun fetch(start: LocalDate, end: LocalDate): StepsSnapshot? {
        val range = "start_date=${start.format(STEP_DATE_FORMAT)}&end_date=${end.format(STEP_DATE_FORMAT)}"
        val response = clientProvider().get<StepRecordsResponse>("health/step-records?$range")
        val summary = response.summary ?: return null
        return StepsSnapshot(
            days = response.days,
            totalSteps = summary.totalSteps ?: 0,
            avgSteps = summary.avgSteps,
            daysWithRecord = summary.daysWithRecord ?: 0,
            daysRealZero = summary.daysRealZero ?: 0,
            daysMissing = summary.daysMissing ?: 0,
            rangeIncomplete = summary.rangeIncomplete ?: false,
        )
    }

    /** 「同步」语义：先上传逐日记录（真 0 有效），再回读服务器汇总。 */
    suspend fun sync(
        scope: String,
        localDays: List<Pair<LocalDate, Int?>>?,
        source: String,
    ): StepsSnapshot? {
        localDays?.forEach { (date, steps) ->
            // 缺失日期不上传、不冒充 0；真 0 有效
            val value = steps ?: return@forEach
            if (value !in 0..200_000) return@forEach
            runCatching {
                uploadDay(
                    date = date,
                    steps = value,
                    source = source,
                    dataTime = "${date.atStartOfDay(STEP_ZONE).format(STEP_DATE_FORMAT)} 23:59:59",
                )
            }
        }
        val snapshot = fetch(LocalDate.now(STEP_ZONE).minusDays(29), LocalDate.now(STEP_ZONE))
        snapshot?.let { saveCache(scope, it) }
        return snapshot
    }

    fun saveCache(scope: String, snapshot: StepsSnapshot) {
        runCatching { cacheFile(scope).writeText(json.encodeToString(StepsSnapshot.serializer(), snapshot)) }
    }

    fun readCache(scope: String): StepsSnapshot? = try {
        val file = cacheFile(scope)
        if (file.exists()) json.decodeFromString(StepsSnapshot.serializer(), file.readText()) else null
    } catch (_: Exception) {
        null
    }
}
