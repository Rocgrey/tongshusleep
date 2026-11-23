package com.rocgrey.sleeptongshu.core.health

import android.content.Context
import androidx.health.connect.client.records.SleepSessionRecord
import com.rocgrey.sleeptongshu.core.sleep.SleepMetadata
import com.rocgrey.sleeptongshu.core.sleep.SleepRecord
import com.rocgrey.sleeptongshu.core.sleep.SleepSegment
import com.rocgrey.sleeptongshu.core.sleep.SleepSource
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json

/** LocalDate 的 ISO 字符串序列化器（kotlinx.serialization 无内置支持）。 */
object LocalDateSerializer : KSerializer<LocalDate> {
    private val format: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE

    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("LocalDate", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: LocalDate) =
        encoder.encodeString(value.format(format))

    override fun deserialize(decoder: Decoder): LocalDate =
        LocalDate.parse(decoder.decodeString(), format)
}

/** 某指标在某一天聚合后的值。 */
@Serializable
data class MetricDay(
    @Serializable(with = LocalDateSerializer::class)
    val date: LocalDate,
    val value: Double,
    val sampleCount: Int,
    val sources: Set<String>,
)

/** 单指标时间序列（按日升序）。 */
@Serializable
data class MetricSeries(
    val metricId: String,
    val days: List<MetricDay>,
)

/** 分期片段（epoch 毫秒）。 */
@Serializable
data class SleepStageSpan(val stage: String, val start: Long, val end: Long)

/**
 * 每晚一条的睡眠摘要：bedTime/wakeTime + 各分期分钟数。
 * 对齐 iOS HealthOverviewAnalysis.daily 中 sleep 项。
 */
@Serializable
data class SleepDaySummary(
    @Serializable(with = LocalDateSerializer::class)
    val day: LocalDate,
    val bedTime: Long,
    val wakeTime: Long,
    val zoneId: String,
    val source: String,
    val segments: List<SleepStageSpan>,
) {
    /** 各分期分钟数（stage 字符串 -> 分钟）。 */
    val stagesMinutes: Map<String, Int>
        get() = segments.groupingBy { it.stage }
            .eachSumOf { (((it.end - it.start) / 60000L).coerceAtLeast(0L)).toInt() }

    /** 入睡分钟数（rem/light/deep 之和）。 */
    val asleepMinutes: Int
        get() = stagesMinutes
            .filterKeys { it in setOf("rem", "light", "deep") }
            .values.sum()

    /** 转成 core.sleep.SleepRecord（source=HEALTH_CONNECT, externalSource="health-connect"），同晚同窗幂等。 */
    fun toSleepRecord(): SleepRecord {
        val id = "hc-$bedTime-$wakeTime"
        return SleepRecord(
            id = id,
            start = Instant.ofEpochMilli(bedTime),
            end = Instant.ofEpochMilli(wakeTime),
            zoneId = ZoneId.of(zoneId),
            source = SleepSource.HEALTH_CONNECT,
            segments = segments.map { SleepSegment(it.stage, it.start, it.end) },
            heartSamples = emptyList(),
            averageHeartRate = null,
            averageSpO2 = null,
            averageRespiratoryRate = null,
            note = null,
            metadata = SleepMetadata(
                externalSource = "health-connect",
                externalId = id,
                healthSleep = true,
            ),
        )
    }
}

/** 一次系统健康读取的完整快照。 */
@Serializable
data class HealthSnapshot(
    val readAt: Long,
    val series: Map<String, MetricSeries> = emptyMap(),
    val sleepDays: List<SleepDaySummary>? = null,
    val error: String? = null,
    /** 步数按日分桶所用时区，固定与 iOS 端一致。 */
    val stepsTimeZone: String = "Asia/Shanghai",
    val stepsReadAt: Long? = null,
    val sleepReadAt: Long? = null,
)

/** 指标展示元信息（总览网格与详情页共用）。 */
data class MetricMeta(
    val id: String,
    val name: String,
    val unit: String,
    val description: String,
)

/** metricId 采用 snake 字符串，与 iOS HealthOverviewAnalysis 一致。 */
val METRIC_META: List<MetricMeta> = listOf(
    MetricMeta("heart_rate", "心率", "次/分", "全天心率样本按日取中位数。"),
    MetricMeta("resting_heart_rate", "静息心率", "次/分", "系统健康静息心率记录。"),
    MetricMeta("hrv", "心率变异性 HRV", "毫秒", "RMSSD 口径的心率变异性，按日取中位数。"),
    MetricMeta("oxygen_saturation", "血氧", "%", "血氧饱和度按日取中位数。"),
    MetricMeta("respiratory_rate", "呼吸率", "次/分", "呼吸频率按日取中位数。"),
    MetricMeta("steps", "步数", "步", "每日累计步数（Asia/Shanghai 时区按日分桶）。"),
    MetricMeta("exercise_minutes", "锻炼时长", "分钟", "锻炼会话每日累计分钟数。"),
    MetricMeta("workout_minutes", "体能训练时长", "分钟", "体能训练每日累计分钟数（Health Connect 与锻炼会话同源）。"),
    MetricMeta("vo2_max", "最大摄氧量", "ml/kg/min", "心肺健康估算值，用于身体年龄估算。"),
    MetricMeta("blood_pressure_systolic", "收缩压", "mmHg", "血压收缩压按日取中位数。"),
    MetricMeta("blood_pressure_diastolic", "舒张压", "mmHg", "血压舒张压按日取中位数。"),
    MetricMeta("distance_km", "距离", "公里", "步行与跑步距离每日累计。"),
    MetricMeta("active_energy", "活动消耗", "千卡", "活动热量每日累计。"),
    MetricMeta("basal_energy", "基础代谢", "千卡/天", "基础代谢率记录（Health Connect 以千卡/天存储）。"),
    MetricMeta("height_cm", "身高", "厘米", "身高记录，用于 BMI 推算。"),
    MetricMeta("bmi", "BMI", "", "由身高与体重推算的体重指数。"),
    MetricMeta("body_fat", "体脂率", "%", "体脂百分比按日取中位数。"),
    MetricMeta("weight_kg", "体重", "公斤", "体重记录。"),
)

/** 聚合规则与快照持久化，对齐 iOS HealthOverviewAnalysis.daily。 */
object HealthOverview {

    const val DAY_ZONE_ID = "Asia/Shanghai"

    fun dayZone(): ZoneId = ZoneId.of(DAY_ZONE_ID)

    /** 通用采样点：value 为该样本/区间的值。 */
    data class SamplePoint(val time: Long, val value: Double, val source: String)

    /** 最近 count 天的日期列表（升序，含今天）。 */
    fun recentDays(count: Int, zone: ZoneId, today: LocalDate = LocalDate.now(zone)): List<LocalDate> =
        (count - 1 downTo 0).map { today.minusDays(it.toLong()) }

    /** 累计型指标（steps/exercise/distance/energy）按日求和，按记录起始时间分桶。 */
    fun aggregateSum(
        points: List<SamplePoint>,
        days: List<LocalDate>,
        zone: ZoneId,
    ): List<MetricDay> {
        val grouped = points.groupBy { LocalDate.ofInstant(Instant.ofEpochMilli(it.time), zone) }
        return days.mapNotNull { day ->
            val list = grouped[day] ?: return@mapNotNull null
            MetricDay(
                date = day,
                value = list.sumOf { it.value },
                sampleCount = list.size,
                sources = list.map { it.source }.toSet(),
            )
        }
    }

    /** 样本型指标（心率/血氧/呼吸率/HRV/血压等）按日取中位数。 */
    fun aggregateMedian(
        points: List<SamplePoint>,
        days: List<LocalDate>,
        zone: ZoneId,
    ): List<MetricDay> {
        val grouped = points.groupBy { LocalDate.ofInstant(Instant.ofEpochMilli(it.time), zone) }
        return days.mapNotNull { day ->
            val list = grouped[day] ?: return@mapNotNull null
            val mid = median(list.map { it.value }) ?: return@mapNotNull null
            MetricDay(
                date = day,
                value = mid,
                sampleCount = list.size,
                sources = list.map { it.source }.toSet(),
            )
        }
    }

    /** 中位数：偶数个时取中间两数均值。 */
    fun median(values: List<Double>): Double? {
        if (values.isEmpty()) return null
        val sorted = values.sorted()
        val mid = sorted.size / 2
        return if (sorted.size % 2 == 1) {
            sorted[mid]
        } else {
            (sorted[mid - 1] + sorted[mid]) / 2.0
        }
    }

    /** Health Connect 分期类型 -> core.sleep.SleepStage 名称。 */
    fun mapSleepStage(stageType: Int): String = when (stageType) {
        SleepSessionRecord.STAGE_TYPE_AWAKE,
        SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED,
        -> "awake"
        SleepSessionRecord.STAGE_TYPE_LIGHT -> "light"
        SleepSessionRecord.STAGE_TYPE_DEEP -> "deep"
        SleepSessionRecord.STAGE_TYPE_REM -> "rem"
        SleepSessionRecord.STAGE_TYPE_SLEEPING -> "unspecified"
        SleepSessionRecord.STAGE_TYPE_OUT_OF_BED -> "in_bed"
        else -> "unobserved"
    }

    private val KNOWN_STAGES = setOf("awake", "light", "deep", "rem")

    /**
     * 每晚自动采用一份"分期较完整"的记录（不把不同来源同晚相加）：
     * 以已知分期（清醒/浅睡/深睡/REM）分钟数最多者胜出，平手时取卧床时长更长的一条。
     */
    fun selectSleepDays(
        records: List<SleepSessionRecord>,
        zone: ZoneId = dayZone(),
    ): List<SleepDaySummary> {
        data class Candidate(val stagedMinutes: Int, val summary: SleepDaySummary)

        val best = LinkedHashMap<LocalDate, Candidate>()
        for (record in records) {
            val day = LocalDate.ofInstant(record.endTime, zone)
            val spans = record.stages.map {
                SleepStageSpan(
                    stage = mapSleepStage(it.stage),
                    start = it.startTime.toEpochMilli(),
                    end = it.endTime.toEpochMilli(),
                )
            }
            val staged = spans.filter { it.stage in KNOWN_STAGES }
                .sumOf { (((it.end - it.start) / 60000L).coerceAtLeast(0L)).toInt() }
            val summary = SleepDaySummary(
                day = day,
                bedTime = record.startTime.toEpochMilli(),
                wakeTime = record.endTime.toEpochMilli(),
                zoneId = zone.id,
                source = record.metadata.dataOrigin.packageName.ifEmpty { "health-connect" },
                segments = spans,
            )
            val previous = best[day]
            val longer = summary.wakeTime - summary.bedTime >
                (previous?.summary?.let { it.wakeTime - it.bedTime } ?: Long.MIN_VALUE)
            if (previous == null || staged > previous.stagedMinutes || (staged == previous.stagedMinutes && longer)) {
                best[day] = Candidate(staged, summary)
            }
        }
        return best.values.sortedBy { it.summary.day }.map { it.summary }
    }
}

/** 快照持久化：context.filesDir/system-health-overview-v1.json。 */
object SnapshotStore {
    const val FILE_NAME = "system-health-overview-v1.json"

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    fun snapshotFile(context: Context): File = File(context.filesDir, FILE_NAME)

    fun writeSnapshot(context: Context, snapshot: HealthSnapshot) {
        runCatching {
            snapshotFile(context).writeText(json.encodeToString(HealthSnapshot.serializer(), snapshot))
        }
    }

    fun readSnapshot(context: Context): HealthSnapshot? = runCatching {
        val file = snapshotFile(context)
        if (!file.exists()) return null
        json.decodeFromString(HealthSnapshot.serializer(), file.readText())
    }.getOrNull()
}

/** 15 分钟节流：距上次读取超过 15 分钟才允许自动刷新。 */
fun shouldAutoRefresh(
    snapshot: HealthSnapshot?,
    nowMillis: Long = System.currentTimeMillis(),
): Boolean {
    if (snapshot == null) return true
    return nowMillis - snapshot.readAt >= 15 * 60 * 1000L
}
