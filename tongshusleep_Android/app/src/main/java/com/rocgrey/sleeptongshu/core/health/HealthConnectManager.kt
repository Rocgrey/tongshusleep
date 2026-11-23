package com.rocgrey.sleeptongshu.core.health

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BasalMetabolicRateRecord
import androidx.health.connect.client.records.BloodPressureRecord
import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.HeightRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RespiratoryRateRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.Vo2MaxRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Duration
import java.time.Instant
import kotlin.math.roundToInt
import kotlin.reflect.KClass

/**
 * 系统健康读取（Health Connect），对应 iOS 18 项 HealthKit 权限。
 * 使用 connect-client 1.1.0-alpha.11：getReadPermission(KClass) 返回权限字符串。
 */
class HealthConnectManager(private val context: Context) {

    /** 与 iOS 18 项 HealthKit 类型一一对应的只读权限集。 */
    val permissions: Set<String> = setOf(
        HealthPermission.getReadPermission(SleepSessionRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class),
        HealthPermission.getReadPermission(RestingHeartRateRecord::class),
        HealthPermission.getReadPermission(HeartRateVariabilityRmssdRecord::class),
        HealthPermission.getReadPermission(OxygenSaturationRecord::class),
        HealthPermission.getReadPermission(RespiratoryRateRecord::class),
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        HealthPermission.getReadPermission(Vo2MaxRecord::class),
        HealthPermission.getReadPermission(BloodPressureRecord::class),
        HealthPermission.getReadPermission(DistanceRecord::class),
        HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(BasalMetabolicRateRecord::class),
        HealthPermission.getReadPermission(HeightRecord::class),
        HealthPermission.getReadPermission(BodyFatRecord::class),
        HealthPermission.getReadPermission(WeightRecord::class),
    )

    companion object {
        const val PROVIDER_PACKAGE = "com.google.android.apps.healthdata"

        /** SDK 可用性检查：已安装且可用返回 true。 */
        fun hasHealthConnect(context: Context): Boolean =
            HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE
    }

    fun sdkStatus(): Int = HealthConnectClient.getSdkStatus(context)

    fun clientOrNull(): HealthConnectClient? =
        if (sdkStatus() == HealthConnectClient.SDK_AVAILABLE) {
            HealthConnectClient.getOrCreate(context)
        } else {
            null
        }

    /** 引导安装/更新 Health Connect，或打开其权限说明页。 */
    fun installOrOpenIntent(): Intent? {
        val rationale = Intent("androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE")
            .setPackage(PROVIDER_PACKAGE)
        if (rationale.resolveActivity(context.packageManager) != null) return rationale
        val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$PROVIDER_PACKAGE"))
        if (market.resolveActivity(context.packageManager) != null) return market
        return Intent(
            Intent.ACTION_VIEW,
            Uri.parse("https://play.google.com/store/apps/details?id=$PROVIDER_PACKAGE"),
        )
    }

    /** 当前已授权的权限（失败时视为空集）。 */
    suspend fun grantedPermissions(): Set<String> {
        val client = clientOrNull() ?: return emptySet()
        return try {
            client.permissionController.getGrantedPermissions()
        } catch (_: Exception) {
            emptySet()
        }
    }

    /**
     * 统一读取最近 days 天各类型记录并聚合为快照。
     * 单类型失败不影响其余类型；未授权时返回带 error 的快照，不伪造数据。
     */
    suspend fun readOverview(days: Int = 90): HealthSnapshot {
        val now = System.currentTimeMillis()
        val client = clientOrNull()
            ?: return HealthSnapshot(readAt = now, error = "Health Connect 不可用或未安装")

        val granted = try {
            client.permissionController.getGrantedPermissions()
        } catch (e: Exception) {
            emptySet<String>()
        }
        if (permissions.none { it in granted }) {
            return HealthSnapshot(readAt = now, error = "尚未授权读取健康数据，请先申请权限")
        }

        val zone = HealthOverview.dayZone()
        val dayList = HealthOverview.recentDays(days, zone)
        val filter = TimeRangeFilter.between(
            Instant.ofEpochMilli(now - days * 24L * 60 * 60 * 1000),
            Instant.ofEpochMilli(now),
        )
        val errors = mutableListOf<String>()
        val series = linkedMapOf<String, MetricSeries>()

        fun put(metricId: String, metricDays: List<MetricDay>) {
            if (metricDays.isNotEmpty()) series[metricId] = MetricSeries(metricId, metricDays)
        }

        // 睡眠：每晚采用一份分期较完整的记录
        val sleepRecords = readRecords(client, SleepSessionRecord::class, filter, errors)
        val sleepDays = HealthOverview.selectSleepDays(sleepRecords, zone)

        // 样本型：按日中位数
        val heartPoints = readRecords(client, HeartRateRecord::class, filter, errors)
            .flatMap { record ->
                record.samples.map {
                    HealthOverview.SamplePoint(it.time.toEpochMilli(), it.beatsPerMinute.toDouble(), origin(record))
                }
            }
        put("heart_rate", HealthOverview.aggregateMedian(heartPoints, dayList, zone))

        val rhrPoints = readRecords(client, RestingHeartRateRecord::class, filter, errors)
            .map { HealthOverview.SamplePoint(it.time.toEpochMilli(), it.beatsPerMinute.toDouble(), origin(it)) }
        put("resting_heart_rate", HealthOverview.aggregateMedian(rhrPoints, dayList, zone))

        val hrvPoints = readRecords(client, HeartRateVariabilityRmssdRecord::class, filter, errors)
            .map { HealthOverview.SamplePoint(it.time.toEpochMilli(), it.heartRateVariabilityMillis, origin(it)) }
        put("hrv", HealthOverview.aggregateMedian(hrvPoints, dayList, zone))

        val spo2Points = readRecords(client, OxygenSaturationRecord::class, filter, errors)
            .map { HealthOverview.SamplePoint(it.time.toEpochMilli(), it.percentage.value, origin(it)) }
        put("oxygen_saturation", HealthOverview.aggregateMedian(spo2Points, dayList, zone))

        val rrPoints = readRecords(client, RespiratoryRateRecord::class, filter, errors)
            .map { HealthOverview.SamplePoint(it.time.toEpochMilli(), it.rate, origin(it)) }
        put("respiratory_rate", HealthOverview.aggregateMedian(rrPoints, dayList, zone))

        // 累计型：按日求和
        val stepPoints = readRecords(client, StepsRecord::class, filter, errors)
            .map { HealthOverview.SamplePoint(it.startTime.toEpochMilli(), it.count.toDouble(), origin(it)) }
        put("steps", HealthOverview.aggregateSum(stepPoints, dayList, zone))

        val exercisePoints = readRecords(client, ExerciseSessionRecord::class, filter, errors)
            .map { record ->
                HealthOverview.SamplePoint(
                    record.startTime.toEpochMilli(),
                    Duration.between(record.startTime, record.endTime).toMinutes().coerceAtLeast(0).toDouble(),
                    origin(record),
                )
            }
        put("exercise_minutes", HealthOverview.aggregateSum(exercisePoints, dayList, zone))

        val distancePoints = readRecords(client, DistanceRecord::class, filter, errors)
            .map { HealthOverview.SamplePoint(it.startTime.toEpochMilli(), it.distance.inKilometers, origin(it)) }
        put("distance_km", HealthOverview.aggregateSum(distancePoints, dayList, zone))

        val activeEnergyPoints = readRecords(client, ActiveCaloriesBurnedRecord::class, filter, errors)
            .map { HealthOverview.SamplePoint(it.startTime.toEpochMilli(), it.energy.inKilocalories, origin(it)) }
        put("active_energy", HealthOverview.aggregateSum(activeEnergyPoints, dayList, zone))

        // 点值型：按日中位数
        val vo2Points = readRecords(client, Vo2MaxRecord::class, filter, errors)
            .map { HealthOverview.SamplePoint(it.time.toEpochMilli(), it.vo2MillilitersPerMinuteKilogram, origin(it)) }
        put("vo2_max", HealthOverview.aggregateMedian(vo2Points, dayList, zone))

        val bpRecords = readRecords(client, BloodPressureRecord::class, filter, errors)
        val systolicPoints = bpRecords.map {
            HealthOverview.SamplePoint(it.time.toEpochMilli(), it.systolic.inMillimetersOfMercury, origin(it))
        }
        val diastolicPoints = bpRecords.map {
            HealthOverview.SamplePoint(it.time.toEpochMilli(), it.diastolic.inMillimetersOfMercury, origin(it))
        }
        put("blood_pressure_systolic", HealthOverview.aggregateMedian(systolicPoints, dayList, zone))
        put("blood_pressure_diastolic", HealthOverview.aggregateMedian(diastolicPoints, dayList, zone))

        val bmrPoints = readRecords(client, BasalMetabolicRateRecord::class, filter, errors)
            .map { HealthOverview.SamplePoint(it.time.toEpochMilli(), it.basalMetabolicRate.inKilocaloriesPerDay, origin(it)) }
        put("basal_energy", HealthOverview.aggregateMedian(bmrPoints, dayList, zone))

        val heightPoints = readRecords(client, HeightRecord::class, filter, errors)
            .map { HealthOverview.SamplePoint(it.time.toEpochMilli(), it.height.inMeters * 100.0, origin(it)) }
        put("height_cm", HealthOverview.aggregateMedian(heightPoints, dayList, zone))

        val bodyFatPoints = readRecords(client, BodyFatRecord::class, filter, errors)
            .map { HealthOverview.SamplePoint(it.time.toEpochMilli(), it.percentage.value, origin(it)) }
        put("body_fat", HealthOverview.aggregateMedian(bodyFatPoints, dayList, zone))

        val weightDays = HealthOverview.aggregateMedian(
            readRecords(client, WeightRecord::class, filter, errors)
                .map { HealthOverview.SamplePoint(it.time.toEpochMilli(), it.weight.inKilograms, origin(it)) },
            dayList,
            zone,
        )
        put("weight_kg", weightDays)

        // BMI：体重按日配对最近一次已知身高
        val heightByDay = HealthOverview.aggregateMedian(heightPoints, dayList, zone)
            .associate { it.date to it.value }
        var lastHeight: Double? = null
        val bmiDays = weightDays.mapNotNull { weightDay ->
            heightByDay[weightDay.date]?.let { lastHeight = it }
            val height = lastHeight
            if (height == null || height <= 0.0) {
                null
            } else {
                val bmi = weightDay.value / ((height / 100.0) * (height / 100.0))
                weightDay.copy(value = (bmi * 10).roundToInt() / 10.0)
            }
        }
        put("bmi", bmiDays)

        val errorText = errors.takeIf { it.isNotEmpty() }?.joinToString(separator = "；")
        return HealthSnapshot(
            readAt = now,
            series = series,
            sleepDays = sleepDays.ifEmpty { null },
            error = errorText,
            stepsTimeZone = HealthOverview.DAY_ZONE_ID,
            stepsReadAt = now,
            sleepReadAt = now,
        )
    }

    /** 单类型读取，失败记录错误并返回空列表。 */
    private suspend fun <T : Record> readRecords(
        client: HealthConnectClient,
        recordType: KClass<T>,
        filter: TimeRangeFilter,
        errors: MutableList<String>,
    ): List<T> = try {
        client.readRecords(
            ReadRecordsRequest(
                recordType = recordType,
                timeRangeFilter = filter,
            ),
        ).records
    } catch (e: Exception) {
        errors.add("${recordType.simpleName}: ${e.message}")
        emptyList()
    }

    private fun origin(record: Record): String =
        record.metadata.dataOrigin.packageName.ifEmpty { "unknown" }
}
