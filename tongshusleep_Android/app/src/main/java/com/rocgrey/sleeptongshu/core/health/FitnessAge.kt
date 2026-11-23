package com.rocgrey.sleeptongshu.core.health

import java.time.LocalDate
import kotlin.math.roundToInt

/**
 * 身体年龄估算，复刻 iOS FitnessAge.swift：
 * - FRIEND 2015 表 3：VO2max 中位数按性别/年龄段线性插值反推身体年龄；
 * - 探索性年龄：近 7 天多指标综合打分，偏离 50 分每 10 分调整 1 岁（±3 封顶）。
 */
object FitnessAge {

    /** FRIEND 2015 表 3 中位数（knot 为年龄段中点：20-29 -> 24.5 … 70-79 -> 74.5）。 */
    private val MALE_MEDIAN_KNOTS = listOf(
        24.5 to 51.4,
        34.5 to 48.3,
        44.5 to 45.4,
        54.5 to 41.9,
        64.5 to 38.5,
        74.5 to 34.6,
    )

    private val FEMALE_MEDIAN_KNOTS = listOf(
        24.5 to 40.7,
        34.5 to 38.7,
        44.5 to 36.3,
        54.5 to 33.3,
        64.5 to 30.5,
        74.5 to 27.0,
    )

    const val BODY_AGE_NOTE = "基于心肺健康研究 FRIEND 2015 表 3 参考值估算，约 ±5 岁"
    const val EXPLORATORY_NOTE = "未经验证的实验估算，不是医学年龄"

    /**
     * 由最大摄氧量反推身体年龄（20-79，插值区间 24.5-74.5，
     * VO2max 高于首个 knot 视为 20，低于末个 knot 视为 79）。
     */
    fun bodyAgeFromVo2(vo2Max: Double, male: Boolean): Int? {
        val knots = if (male) MALE_MEDIAN_KNOTS else FEMALE_MEDIAN_KNOTS
        if (vo2Max >= knots.first().second) return 20
        if (vo2Max <= knots.last().second) return 79
        for (i in 0 until knots.size - 1) {
            val (age1, vo1) = knots[i]
            val (age2, vo2) = knots[i + 1]
            if (vo2Max <= vo1 && vo2Max >= vo2) {
                val t = (vo1 - vo2Max) / (vo1 - vo2)
                return (age1 + t * (age2 - age1)).roundToInt().coerceIn(20, 79)
            }
        }
        return null
    }

    /** 探索性年龄结果。 */
    data class ExploratoryAge(
        val age: Int?,
        val averageScore: Double?,
        val usedItems: List<String>,
        val note: String = EXPLORATORY_NOTE,
    )

    /**
     * 探索性年龄：近 7 天同日至少 2 项指标参与打分（0-100，50 为中性）：
     * - 睡眠：以 7.5 小时为中心，每偏差 1 小时 ±10 分；
     * - 步数：8000 步映射 50 分，16000 步封顶 100 分；
     * - 静息心率：50 起，每高 1 次 -1.2 分；
     * - HRV：对比前 30 天个人中位数，每偏差 1% ±1 分。
     * 平均分偏离 50 每 10 分调整 1 岁（±3），基准年龄默认 30。
     */
    fun exploratory(snapshot: HealthSnapshot?, referenceAge: Int? = null): ExploratoryAge {
        val today = LocalDate.now()
        val windowStart = today.minusDays(6)

        val sleepHoursByDay = snapshot?.sleepDays.orEmpty()
            .filter { it.day >= windowStart && it.day <= today && it.asleepMinutes > 0 }
            .associate { it.day to it.asleepMinutes / 60.0 }
        val stepsByDay = snapshot?.series?.get("steps")?.days.orEmpty()
            .filter { it.date >= windowStart && it.date <= today }
            .associate { it.date to it.value }
        val rhrByDay = snapshot?.series?.get("resting_heart_rate")?.days.orEmpty()
            .filter { it.date >= windowStart && it.date <= today }
            .associate { it.date to it.value }
        val hrvDays = snapshot?.series?.get("hrv")?.days.orEmpty()
        val hrvBaseline = HealthOverview.median(
            hrvDays.filter { it.date.isBefore(windowStart) }.map { it.value },
        )
        val hrvByDay = hrvDays
            .filter { it.date >= windowStart && it.date <= today }
            .associate { it.date to it.value }

        if (sleepHoursByDay.isEmpty() && stepsByDay.isEmpty() &&
            rhrByDay.isEmpty() && hrvByDay.isEmpty()
        ) {
            return ExploratoryAge(age = null, averageScore = null, usedItems = emptyList())
        }

        val allDates = (sleepHoursByDay.keys + stepsByDay.keys + rhrByDay.keys + hrvByDay.keys)
            .toSortedSet()
        var scoreSum = 0.0
        var countedDays = 0
        val usedItems = sortedSetOf<String>()

        for (date in allDates) {
            val scores = mutableListOf<Double>()
            sleepHoursByDay[date]?.let { hours ->
                scores += (50.0 + (hours - 7.5) * 10.0).coerceIn(0.0, 100.0)
                usedItems += "睡眠"
            }
            stepsByDay[date]?.let { steps ->
                scores += (steps / 8000.0 * 50.0).coerceIn(0.0, 100.0)
                usedItems += "步数"
            }
            rhrByDay[date]?.let { rhr ->
                scores += (50.0 - (rhr - 50.0) * 1.2).coerceIn(0.0, 100.0)
                usedItems += "静息心率"
            }
            hrvByDay[date]?.let { hrv ->
                hrvBaseline?.takeIf { it > 0.0 }?.let { base ->
                    scores += (50.0 + (hrv / base - 1.0) * 100.0).coerceIn(0.0, 100.0)
                    usedItems += "HRV"
                }
            }
            if (scores.size >= 2) {
                scoreSum += scores.average()
                countedDays += 1
            }
        }

        if (countedDays == 0) {
            return ExploratoryAge(age = null, averageScore = null, usedItems = emptyList())
        }

        val averageScore = scoreSum / countedDays
        val adjust = ((averageScore - 50.0) / 10.0).coerceIn(-3.0, 3.0)
        val baseAge = referenceAge ?: 30
        val age = (baseAge + adjust).roundToInt().coerceIn(20, 80)
        return ExploratoryAge(age = age, averageScore = averageScore, usedItems = usedItems.toList())
    }
}
