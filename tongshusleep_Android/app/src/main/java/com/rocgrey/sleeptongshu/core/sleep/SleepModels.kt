package com.rocgrey.sleeptongshu.core.sleep

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** 与 iOS SleepModels.swift 对齐的睡眠领域模型。 */
enum class SleepStage(val label: String) {
    AWAKE("清醒"),
    REM("做梦"),
    LIGHT("浅睡"),
    DEEP("深睡"),
    UNSPECIFIED("未分期"),
    IN_BED("卧床"),
    UNOBSERVED("未观测");

    companion object {
        fun fromName(name: String?): SleepStage =
            entries.firstOrNull { it.name.equals(name, true) } ?: UNSPECIFIED
    }
}

enum class SleepSource(val key: String, val label: String) {
    SAMPLE("sample", "示例"),
    MANUAL("manual", "手动"),
    HEALTH_CONNECT("healthKit", "系统健康"),
    BAND("band", "设备"),
    PHONE("phone", "手机");

    companion object {
        fun fromKey(key: String?): SleepSource =
            entries.firstOrNull { it.key == key } ?: MANUAL
    }
}

@Serializable
data class SleepSegment(val stage: String, val start: Long, val end: Long) {
    val stageEnum: SleepStage get() = SleepStage.fromName(stage)
}

@Serializable
data class HeartSample(val at: Long, val bpm: Double)

/** 记录元信息（JSON 存储，向后兼容）。 */
@Serializable
data class SleepMetadata(
    val aisScore: Int? = null,
    val externalSource: String? = null,
    val externalId: String? = null,
    val phoneNight: PhoneNight? = null,
    val healthSleep: Boolean = false,
    val encryptedBand: String? = null,
    val bioNight: Boolean = false,
)

@Serializable
data class PhoneNight(
    val estimatedMinutes: Int? = null,
    val audioSeconds: Int? = null,
    val snoreSeconds: Int? = null,
    val speechSeconds: Int? = null,
    val movementSamples: Int? = null,
)

/** 运行期睡眠记录。 */
data class SleepRecord(
    val id: String,
    val start: Instant,
    val end: Instant,
    val zoneId: ZoneId,
    val source: SleepSource,
    val segments: List<SleepSegment>,
    val heartSamples: List<HeartSample>,
    val averageHeartRate: Double?,
    val averageSpO2: Double?,
    val averageRespiratoryRate: Double?,
    val note: String?,
    val metadata: SleepMetadata,
) {
    /** 按原始时区的结束日标签（iOS sleepDay 语义）。 */
    val day: LocalDate get() = LocalDate.ofInstant(end, zoneId)

    /** 入睡点：第一段非清醒/卧床阶段起点。 */
    val sleepOnset: Instant?
        get() = segments.firstOrNull {
            it.stageEnum !in setOf(SleepStage.AWAKE, SleepStage.IN_BED, SleepStage.UNOBSERVED)
        }?.let { Instant.ofEpochMilli(it.start) }

    /** 睡眠结束点：最后一段入睡阶段终点。 */
    val sleepEnd: Instant?
        get() = segments.lastOrNull {
            it.stageEnum !in setOf(SleepStage.AWAKE, SleepStage.IN_BED, SleepStage.UNOBSERVED)
        }?.let { Instant.ofEpochMilli(it.end) }

    /** 卧床分钟数：整段记录时长。 */
    val inBedMinutes: Int
        get() = (((end.toEpochMilli() - start.toEpochMilli()) / 60000L)).toInt().coerceAtLeast(0)

    /** 入睡分钟数：phone 来源用估算，其余按分期求和。 */
    val asleepMinutes: Int
        get() = if (source == SleepSource.PHONE) {
            metadata.phoneNight?.estimatedMinutes ?: 0
        } else {
            minutesOf(setOf(SleepStage.REM, SleepStage.LIGHT, SleepStage.DEEP))
        }

    /** 夜间清醒分钟数。 */
    val awakeMinutes: Int
        get() = minutesOf(setOf(SleepStage.AWAKE))

    /** 夜间清醒次数（清醒段数，最后一段除外）。 */
    val awakenings: Int
        get() = segments.count { it.stageEnum == SleepStage.AWAKE && it.end < end.toEpochMilli() - 60_000 }

    /** 睡眠效率：需要完整覆盖（无未观测段）才有意义。 */
    val efficiency: Double?
        get() {
            val total = (end.toEpochMilli() - start.toEpochMilli())
            val unobserved = minutesOf(setOf(SleepStage.UNOBSERVED, SleepStage.UNSPECIFIED))
            if (unobserved > 0 || total <= 0) return null
            if (asleepMinutes <= 0) return null
            return asleepMinutes * 100.0 / (total / 60000.0)
        }

    /** 参考分：与 iOS 一致，仅手动/手机来源计算。 */
    val score: Int?
        get() = when (source) {
            SleepSource.MANUAL, SleepSource.PHONE -> {
                val eff = efficiency ?: 0.0
                ((asleepMinutes / 480.0 * 100 * 0.6 + eff * 0.4)).toInt().coerceIn(0, 100)
            }
            else -> null
        }

    fun minutesOf(stages: Set<SleepStage>): Int =
        segments.filter { it.stageEnum in stages }
            .sumOf { ((it.end - it.start) / 60000L).coerceAtLeast(0L) }
            .toInt()

    fun shareOf(stages: Set<SleepStage>): Double? {
        val asleep = asleepMinutes
        if (asleep <= 0) return null
        return minutesOf(stages) * 100.0 / asleep
    }
}

/** 手动记录：只有入睡/起床时间。 */
fun buildManualRecord(
    start: Instant,
    end: Instant,
    zone: ZoneId,
    note: String?,
    aisScore: Int?,
    id: String = java.util.UUID.randomUUID().toString(),
): SleepRecord {
    val metadata = SleepMetadata(aisScore = aisScore)
    return SleepRecord(
        id = id,
        start = start,
        end = end,
        zoneId = zone,
        source = SleepSource.MANUAL,
        segments = listOf(SleepSegment("unspecified", start.toEpochMilli(), end.toEpochMilli())),
        heartSamples = emptyList(),
        averageHeartRate = null,
        averageSpO2 = null,
        averageRespiratoryRate = null,
        note = note,
        metadata = metadata,
    )
}

object SleepCodec {
    private val json = Json { ignoreUnknownKeys = true }

    fun segmentsToJson(segments: List<SleepSegment>): String = json.encodeToString(segments)
    fun segmentsFromJson(raw: String): List<SleepSegment> =
        try { json.decodeFromString(raw) } catch (_: Exception) { emptyList() }

    fun heartsToJson(samples: List<HeartSample>): String = json.encodeToString(samples)
    fun heartsFromJson(raw: String): List<HeartSample> =
        try { json.decodeFromString(raw) } catch (_: Exception) { emptyList() }

    fun metadataToJson(metadata: SleepMetadata): String = json.encodeToString(metadata)
    fun metadataFromJson(raw: String): SleepMetadata =
        try { json.decodeFromString(raw) } catch (_: Exception) { SleepMetadata() }
}

object SleepFormat {
    val recordDate: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
    val recordDateTime: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
}
