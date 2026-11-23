package com.rocgrey.sleeptongshu.core.sleep

import com.rocgrey.sleeptongshu.core.data.SleepRecordEntity
import kotlinx.serialization.encodeToString
import java.time.Instant
import java.time.ZoneId

/** Room 实体与领域模型互转。 */
object SleepRecordMapper {

    fun toEntity(record: SleepRecord): SleepRecordEntity = SleepRecordEntity(
        id = record.id,
        startEpochMs = record.start.toEpochMilli(),
        endEpochMs = record.end.toEpochMilli(),
        zoneId = record.zoneId.id,
        source = record.source.key,
        segmentsJson = SleepCodec.segmentsToJson(record.segments),
        heartSamplesJson = SleepCodec.heartsToJson(record.heartSamples),
        averageHeartRate = record.averageHeartRate,
        averageSpO2 = record.averageSpO2,
        averageRespiratoryRate = record.averageRespiratoryRate,
        note = record.note,
        metadataJson = SleepCodec.metadataToJson(record.metadata),
        aisScore = record.metadata.aisScore,
    )

    fun toDomain(entity: SleepRecordEntity): SleepRecord = SleepRecord(
        id = entity.id,
        start = Instant.ofEpochMilli(entity.startEpochMs),
        end = Instant.ofEpochMilli(entity.endEpochMs),
        zoneId = ZoneId.of(entity.zoneId),
        source = SleepSource.fromKey(entity.source),
        segments = SleepCodec.segmentsFromJson(entity.segmentsJson),
        heartSamples = SleepCodec.heartsFromJson(entity.heartSamplesJson),
        averageHeartRate = entity.averageHeartRate,
        averageSpO2 = entity.averageSpO2,
        averageRespiratoryRate = entity.averageRespiratoryRate,
        note = entity.note,
        metadata = SleepCodec.metadataFromJson(entity.metadataJson),
    )
}

/** 备份 v2：与 iOS SleepBackup 兼容的导出/导入 JSON。 */
object SleepBackup {
    private val json = kotlinx.serialization.json.Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    @kotlinx.serialization.Serializable
    data class BackupSegment(val stage: String, val start: Long, val end: Long)

    @kotlinx.serialization.Serializable
    data class BackupHeart(val at: Long, val bpm: Double)

    @kotlinx.serialization.Serializable
    data class BackupRecord(
        val id: String,
        val start: Long,
        val end: Long,
        val zoneId: String,
        val source: String,
        val segments: List<BackupSegment> = emptyList(),
        val heartSamples: List<BackupHeart> = emptyList(),
        val averageHeartRate: Double? = null,
        val averageSpO2: Double? = null,
        val averageRespiratoryRate: Double? = null,
        val note: String? = null,
        val aisScore: Int? = null,
        val metadata: String? = null,
    )

    @kotlinx.serialization.Serializable
    data class BackupFile(
        val version: Int = 2,
        val exportedAt: String,
        val records: List<BackupRecord>,
    )

    const val MAX_BYTES = 10 * 1024 * 1024

    fun export(records: List<SleepRecord>, exportedAt: String): String {
        val file = BackupFile(
            exportedAt = exportedAt,
            records = records.map {
                BackupRecord(
                    id = it.id, start = it.start.toEpochMilli(), end = it.end.toEpochMilli(),
                    zoneId = it.zoneId.id, source = it.source.key,
                    segments = it.segments.map { s -> BackupSegment(s.stage, s.start, s.end) },
                    heartSamples = it.heartSamples.map { h -> BackupHeart(h.at, h.bpm) },
                    averageHeartRate = it.averageHeartRate,
                    averageSpO2 = it.averageSpO2,
                    averageRespiratoryRate = it.averageRespiratoryRate,
                    note = it.note, aisScore = it.metadata.aisScore,
                    metadata = SleepCodec.metadataToJson(it.metadata),
                )
            },
        )
        val text = json.encodeToString(BackupFile.serializer(), file)
        require(text.toByteArray(Charsets.UTF_8).size <= MAX_BYTES) { "备份超过 10MB 上限" }
        return text
    }

    /** 导入：同 id 跳过，返回可入库的记录。 */
    fun import(text: String, existingIds: Set<String>): List<SleepRecord> {
        val file = json.decodeFromString(BackupFile.serializer(), text)
        require(file.version in 1..2) { "不支持的备份版本" }
        return file.records.filter { it.id !in existingIds }.map { b ->
            SleepRecord(
                id = b.id,
                start = Instant.ofEpochMilli(b.start),
                end = Instant.ofEpochMilli(b.end),
                zoneId = ZoneId.of(b.zoneId),
                source = SleepSource.fromKey(b.source),
                segments = b.segments.map { SleepSegment(it.stage, it.start, it.end) },
                heartSamples = b.heartSamples.map { HeartSample(it.at, it.bpm) },
                averageHeartRate = b.averageHeartRate,
                averageSpO2 = b.averageSpO2,
                averageRespiratoryRate = b.averageRespiratoryRate,
                note = b.note,
                metadata = b.metadata?.let { SleepCodec.metadataFromJson(it) } ?: SleepMetadata(aisScore = b.aisScore),
            )
        }
    }
}
