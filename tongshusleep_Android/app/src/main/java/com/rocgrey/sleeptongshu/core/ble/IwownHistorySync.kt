package com.rocgrey.sleeptongshu.core.ble

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.alibaba.fastjson.JSON
import com.alibaba.fastjson.JSONObject
import com.rocgrey.sleeptongshu.core.api.ApiClient
import com.rocgrey.sleeptongshu.core.data.DeviceStepEntity
import com.rocgrey.sleeptongshu.core.data.AppDatabase
import com.rocgrey.sleeptongshu.core.data.WearableVitalEntity
import com.rocgrey.sleeptongshu.core.sleep.SleepMetadata
import com.rocgrey.sleeptongshu.core.sleep.SleepRecord
import com.rocgrey.sleeptongshu.core.sleep.SleepRecordMapper
import com.rocgrey.sleeptongshu.core.sleep.SleepSegment
import com.rocgrey.sleeptongshu.core.sleep.SleepStage
import com.rocgrey.sleeptongshu.core.sleep.SleepSource
import com.rocgrey.sleeptongshu.core.steps.StepSync
import com.rocgrey.sleeptongshu.core.sync.AutomaticSync
import com.iwown.app.nativeinvoke.NativeInvoker
import com.iwown.app.nativeinvoke.SA_SleepBufInfo
import com.zeroner.blemidautumn.bluetooth.cmdimpl.ProtoBufSendBluetoothCmdImpl
import com.zeroner.blemidautumn.bluetooth.model.ProtoBufHisHealthData
import com.zeroner.blemidautumn.bluetooth.model.ProtoBufHisIndexTable
import com.zeroner.blemidautumn.bluetooth.model.ProtoBufHisRriData
import com.zeroner.blemidautumn.bluetooth.model.ProtoBufSupportInfo
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONArray

/**
 * 0x80 历史数据同步状态机（参考 demo ProtoBufSync/ProtoBufDataParsePersenter 的简化版）：
 * - itHisData(type) → 0x80 hisDataCase==3 收索引表 → 逐段 startHisData(type,startSeq,endSeq)
 *   → hisDataCase==4 收数据 → 段完成/超时发下一段 → 全部完成 stopHisData(type)
 * - 健康数据（hisDataType=3）：步数→DeviceStepDao，体征→WearableVitalDao，
 *   睡眠 Q/T/E JSON 按天落盘 filesDir/iwown/sleep/{yyyyMMdd}.json
 * - RRI（hisDataType=7）：按天落盘 filesDir/iwown/rri/{yyyyMMdd}.json（seq→样本映射）
 * - 同步完成后触发 AI 睡眠计算（NativeInvoker.calculateSleepFileWithAF）并入库 SleepRecord。
 */
class IwownHistorySync(
    private val context: Context,
    private val onEvent: (String) -> Unit,
    private val onSyncing: (Boolean) -> Unit,
    private val deviceIdProvider: () -> String,
    private val signedIn: () -> Boolean,
    private val client: () -> ApiClient?,
    private val userScopeId: () -> String,
) {

    private data class Segment(val startSeq: Int, val endSeq: Int, val daySecond: Long)

    companion object {
        /** 请求侧历史数据类型（与 demo ProtoBufSync 一致）。 */
        const val HEALTH_DATA = 0
        const val RRI_DATA = 4

        /** 0x80 回调里的 hisDataCase。 */
        private const val CASE_INDEX_TABLE = 3
        private const val CASE_HIS_DATA = 4

        /** 0x80 数据里的 hisDataType（DataCase 编号，与 demo 一致）。 */
        private const val TYPE_HIS_HEALTH = 3
        private const val TYPE_HIS_HEALTH_ENCRYPT = 12
        private const val TYPE_HIS_RRI = 7

        private const val SEGMENT_TIMEOUT_MS = 5000L
        private const val DAY_FILE = DateTimeFormatter.ofPattern("yyyyMMdd")
        private const val DAY_LABEL = DateTimeFormatter.ofPattern("yyyy-MM-dd")

        /** sleepMode → SleepStage（3=深睡、4=浅睡、6=清醒、7=REM）。 */
        fun stageName(mode: Int): String? = when (mode) {
            3 -> SleepStage.DEEP.name
            4 -> SleepStage.LIGHT.name
            6 -> SleepStage.AWAKE.name
            7 -> SleepStage.REM.name
            else -> null
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var syncing = false
    private var pendingDays: Int? = null
    private var supportInfo: ProtoBufSupportInfo? = null

    private var types = mutableListOf<Int>()
    private var typeIndex = 0
    private var currentType = 0
    private var segments = mutableListOf<Segment>()
    private var segmentIndex = 0
    private var cutoffSecond = 0L

    private val timeoutRunnable = Runnable { onTimeout() }
    private val dayStepTotals = mutableMapOf<String, Int>()

    private val sleepDir: File get() = File(context.filesDir, "iwown/sleep")
    private val rriDir: File get() = File(context.filesDir, "iwown/rri")

    // ---------- 入口 ----------
    fun start(days: Int = 3) {
        if (syncing) {
            onEvent("历史同步进行中，请稍后再试")
            return
        }
        val info = supportInfo
        if (info == null) {
            // 能力信息还没拿到（0x09），先请求，收到后自动开始
            pendingDays = days
            IwownSdkManager.startSupportQuery()
            onEvent("正在获取设备能力信息…")
            return
        }
        beginSync(days, info)
    }

    fun cancel() {
        if (!syncing) return
        syncing = false
        mainHandler.removeCallbacks(timeoutRunnable)
        runCatching { sendStop() }
        onSyncing(false)
        onEvent("历史同步已取消")
    }

    // ---------- 0x09 能力信息 ----------
    fun onSupportInfo(data: String) {
        runCatching {
            val info = JSON.parseObject(data, ProtoBufSupportInfo::class.java)
            supportInfo = info
            val pending = pendingDays
            pendingDays = null
            if (pending != null && !syncing) {
                beginSync(pending, info)
            }
        }
    }

    // ---------- 0x80 分发 ----------
    fun on80Data(data: String) {
        if (!syncing) return
        val case = runCatching {
            JSONObject.parseObject(data).getIntValue("hisDataCase")
        }.getOrDefault(-1)
        when (case) {
            CASE_INDEX_TABLE -> scope.launch { runCatching { handleIndexTable(data) } }
            CASE_HIS_DATA -> scope.launch { runCatching { handleHisData(data) } }
        }
    }

    private fun beginSync(days: Int, info: ProtoBufSupportInfo) {
        val zone = ZoneId.systemDefault()
        cutoffSecond = LocalDate.now(zone).minusDays((days - 1).toLong())
            .atStartOfDay(zone).toInstant().epochSecond
        types = mutableListOf()
        if (info.isSupport_health()) types.add(HEALTH_DATA)
        if (info.isSupport_rri()) types.add(RRI_DATA)
        if (types.isEmpty()) {
            onEvent("设备不支持健康/RRI 历史数据同步")
            return
        }
        syncing = true
        typeIndex = 0
        segments = mutableListOf()
        segmentIndex = 0
        dayStepTotals.clear()
        onSyncing(true)
        onEvent("开始同步最近 $days 天历史数据")
        requestIndexTable()
    }

    private fun requestIndexTable() {
        if (typeIndex >= types.size) {
            finishSync()
            return
        }
        armTimeout()
        sendCmd(ProtoBufSendBluetoothCmdImpl.getInstance().itHisData(types[typeIndex]))
    }

    private suspend fun handleIndexTable(data: String) {
        val table = JSON.parseObject(data, ProtoBufHisIndexTable::class.java) ?: return
        currentType = table.getHisDataType()
        val collected = mutableListOf<Segment>()
        table.getIndexList()?.forEach { index ->
            val start = index.getStartSeq()
            val end = index.getEndSeq()
            if (start >= end) return@forEach
            val second = index.getSecond()
            // 只同步最近 N 天（index.second 是该段所属时刻的 Unix 秒）
            if (second > 0 && second < cutoffSecond) return@forEach
            collected.add(Segment(start, end, second.toLong()))
        }
        if (collected.isEmpty()) {
            // 该类型没有需要同步的数据，进入下一个类型
            mainHandler.removeCallbacks(timeoutRunnable)
            typeIndex++
            requestIndexTable()
            return
        }
        // 新的一天在前（与 demo 排序方向一致）
        collected.sortByDescending { it.daySecond }
        segments = collected
        segmentIndex = 0
        mainHandler.removeCallbacks(timeoutRunnable)
        requestSegment()
    }

    private fun requestSegment() {
        if (segmentIndex >= segments.size) {
            // 本类型全部段完成
            mainHandler.removeCallbacks(timeoutRunnable)
            sendStop()
            typeIndex++
            requestIndexTable()
            return
        }
        val segment = segments[segmentIndex]
        armTimeout()
        sendCmd(ProtoBufSendBluetoothCmdImpl.getInstance().startHisData(currentType, segment.startSeq, segment.endSeq))
        onEvent("同步第 ${segmentIndex + 1}/${segments.size} 段（seq ${segment.startSeq}-${segment.endSeq}）")
    }

    private fun sendStop() {
        val type = currentType
        runCatching {
            sendCmd(ProtoBufSendBluetoothCmdImpl.getInstance().stopHisData(type))
        }
    }

    private suspend fun handleHisData(data: String) {
        val dataType = JSONObject.parseObject(data).getIntValue("hisDataType")
        when (dataType) {
            TYPE_HIS_HEALTH, TYPE_HIS_HEALTH_ENCRYPT -> {
                val hb = JSON.parseObject(data, ProtoBufHisHealthData::class.java) ?: return
                storeHealth(hb)
                maybeSegmentDone(hb.getSeq())
            }
            TYPE_HIS_RRI -> {
                val rr = JSON.parseObject(data, ProtoBufHisRriData::class.java) ?: return
                storeRri(rr)
                maybeSegmentDone(rr.getSeq())
            }
        }
    }

    /** 收到数据后刷新 5 秒超时；seq 到达段尾则立即推进下一段。 */
    private fun maybeSegmentDone(seq: Int) {
        mainHandler.removeCallbacks(timeoutRunnable)
        val segment = segments.getOrNull(segmentIndex) ?: return
        if (seq >= segment.endSeq) {
            segmentDone()
        } else {
            armTimeout()
        }
    }

    private fun segmentDone() {
        mainHandler.removeCallbacks(timeoutRunnable)
        segmentIndex++
        requestSegment()
    }

    private fun onTimeout() {
        if (!syncing) return
        onEvent("等待数据超时，跳过当前段")
        segmentDone()
    }

    private fun armTimeout() {
        mainHandler.removeCallbacks(timeoutRunnable)
        mainHandler.postDelayed(timeoutRunnable, SEGMENT_TIMEOUT_MS)
    }

    private fun finishSync() {
        syncing = false
        mainHandler.removeCallbacks(timeoutRunnable)
        onSyncing(false)
        onEvent("历史同步完成，开始计算睡眠")
        scope.launch { runCatching { calculateSleep() } }
    }

    private fun sendCmd(bytes: ByteArray?) {
        if (bytes == null || bytes.isEmpty()) return
        try {
            com.zeroner.blemidautumn.task.BackgroundThreadManager.getInstance()
                .addWriteData(context, bytes)
        } catch (e: Exception) {
            onEvent("指令发送失败：${e.message}")
        }
    }

    // ---------- 健康数据存储 ----------
    private suspend fun storeHealth(hb: ProtoBufHisHealthData) {
        val day = String.format("%04d-%02d-%02d", hb.getYear(), hb.getMonth(), hb.getDay())
        if (hb.getYear() <= 0) return
        val deviceId = deviceIdProvider()
        val recordAt = localEpochMs(hb.getYear(), hb.getMonth(), hb.getDay(), hb.getHour(), hb.getMinute())
        val dao = AppDatabase.get(context)

        // 步数：按天累计（一条 0x80 数据代表当天的一个时段）
        val step = hb.getPedo()?.getStep() ?: 0
        if (step > 0) {
            val total = (dayStepTotals[day] ?: 0) + step
            dayStepTotals[day] = total
            dao.deviceStepDao().upsertAll(
                listOf(
                    DeviceStepEntity(
                        mergeKey = "$deviceId|$day",
                        deviceId = deviceId,
                        deviceName = "BIO-7349",
                        day = day,
                        steps = total,
                        readAt = System.currentTimeMillis(),
                        dayBasis = "device",
                    ),
                ),
            )
            if (signedIn()) {
                runCatching {
                    val api = client() ?: return@runCatching
                    StepSync(context) { api }.uploadDay(
                        date = LocalDate.parse(day),
                        steps = total,
                        source = "wearable",
                        dataTime = "$day 23:59:59",
                    )
                }
            }
        }

        // 体征：心率 / HRV / 血压 / 血氧
        val vitals = mutableListOf<WearableVitalEntity>()
        hb.getHeartRate()?.let { hr ->
            if (hr.getAvg_bpm() > 0) {
                vitals += vital(deviceId, "heart_rate", hr.getAvg_bpm().toDouble(), "次/分", recordAt)
            }
        }
        hb.getHrv()?.let { hrv ->
            if (hrv.getMEAN() > 0f) {
                vitals += vital(deviceId, "hrv_mean", hrv.getMEAN().toDouble(), "ms", recordAt)
            }
            if (hrv.getSDNN() > 0f) {
                vitals += vital(deviceId, "hrv_sdnn", hrv.getSDNN().toDouble(), "ms", recordAt)
            }
        }
        hb.getBp()?.let { bp ->
            if (bp.getSbp() > 0 && bp.getDbp() > 0) {
                vitals += vital(deviceId, "blood_pressure_systolic", bp.getSbp().toDouble(), "mmHg", recordAt)
                vitals += vital(deviceId, "blood_pressure_diastolic", bp.getDbp().toDouble(), "mmHg", recordAt)
            }
        }
        hb.getSpo2()?.let { spo2 ->
            if (spo2.getAvgSpo2() > 0) {
                vitals += vital(deviceId, "oxygen_saturation", spo2.getAvgSpo2().toDouble(), "%", recordAt)
            }
        }
        if (vitals.isNotEmpty()) dao.wearableVitalDao().insertAll(vitals)

        // 睡眠 JSON（Q/T/E，同 demo filterJson 的结构）按天累加合并
        hb.getSleep()?.getSleepFile()?.let { sf ->
            runCatching { appendSleepEntry(day, sf) }
        }
    }

    private fun vital(
        deviceId: String,
        kind: String,
        value: Double,
        unit: String,
        recordAt: Long,
    ) = WearableVitalEntity(
        id = "$deviceId|$kind|$recordAt|iwown",
        deviceId = deviceId,
        kind = kind,
        value = value,
        recordAt = recordAt,
        unit = unit,
        origin = "iwown",
    )

    /** 单条 0x80 健康数据 → 睡眠文件条目 {"Q":..,"T":[..],"E":{"a":[..],"c":..,"s":..},...}。 */
    private fun appendSleepEntry(day: String, sf: com.zeroner.blemidautumn.bluetooth.model.FileProtobufSleep) {
        val entry = org.json.JSONObject()
        entry.put("Q", sf.getQ())
        val t = sf.getT()
        if (t != null && t.isNotEmpty()) entry.put("T", JSONArray(t.toList()))
        sf.getE()?.let { e ->
            val eo = org.json.JSONObject()
            val a = e.getA()
            if (a != null && a.isNotEmpty()) eo.put("a", JSONArray(a.toList()))
            if (e.getC() != 0) eo.put("c", e.getC())
            if (e.getS() != 0) eo.put("s", e.getS())
            if (eo.length() > 0) entry.put("E", eo)
        }
        sf.getH()?.let { h ->
            if (h.getN() != 0 || h.getX() != 0 || h.getA() != 0) {
                val ho = org.json.JSONObject()
                if (h.getN() != 0) ho.put("n", h.getN())
                if (h.getX() != 0) ho.put("x", h.getX())
                if (h.getA() != 0) ho.put("a", h.getA())
                entry.put("H", ho)
            }
        }
        sf.getP()?.let { p ->
            if (p.getT() != 0 || p.getA() != 0 || p.getC() != 0f || p.getS() != 0 || p.getD() != 0) {
                val po = org.json.JSONObject()
                if (p.getT() != 0) po.put("t", p.getT())
                if (p.getA() != 0) po.put("a", p.getA())
                if (p.getC() != 0f) po.put("c", p.getC())
                if (p.getS() != 0) po.put("s", p.getS())
                if (p.getD() != 0) po.put("d", p.getD())
                entry.put("P", po)
            }
        }
        sf.getV()?.let { v ->
            if (v.getS() != 0f || v.getR() != 0f || v.getP() != 0f || v.getM() != 0f || v.getF() != 0f) {
                val vo = org.json.JSONObject()
                if (v.getS() != 0f) vo.put("s", v.getS())
                if (v.getR() != 0f) vo.put("r", v.getR())
                if (v.getP() != 0f) vo.put("p", v.getP())
                if (v.getM() != 0f) vo.put("m", v.getM())
                if (v.getF() != 0f) vo.put("f", v.getF())
                entry.put("V", vo)
            }
        }
        val file = dayFile(sleepDir, day)
        val array = if (file.exists()) {
            runCatching { JSONArray(file.readText()) }.getOrDefault(JSONArray())
        } else {
            JSONArray()
        }
        // 按 Q 去重（同一段数据重复同步不重复累加）
        val q = sf.getQ()
        var exists = false
        for (i in 0 until array.length()) {
            if (array.optJSONObject(i)?.optInt("Q", Int.MIN_VALUE) == q) {
                exists = true
                break
            }
        }
        if (!exists) {
            array.put(entry)
            file.parentFile?.mkdirs()
            file.writeText(array.toString())
        }
    }

    // ---------- RRI 存储 ----------
    private suspend fun storeRri(rr: ProtoBufHisRriData) {
        if (rr.getYear() <= 0) return
        val raw = rr.getRaw_data() ?: return
        if (raw.isEmpty()) return
        val day = String.format("%04d-%02d-%02d", rr.getYear(), rr.getMonth(), rr.getDay())
        val file = dayFile(rriDir, day)
        // 文件结构：{"{seq}":[int,...]}，按 seq 去重并保证顺序
        val obj = if (file.exists()) {
            runCatching { JSONObject.parseObject(file.readText()) }.getOrDefault(JSONObject())
        } else {
            JSONObject()
        }
        val seq = rr.getSeq().toString()
        if (!obj.containsKey(seq)) {
            // 每个 int 高 16 位 + 低 16 位各一条 RRI（拆法同 demo parse80Data）
            val samples = mutableListOf<Int>()
            raw.forEach { value ->
                val high = (value shr 16) and 0xFFFF
                val low = value and 0xFFFF
                samples.add(high.toShort().toInt())
                samples.add(low.toShort().toInt())
            }
            obj.put(seq, samples)
            file.parentFile?.mkdirs()
            file.writeText(obj.toJSONString())
        }
    }

    private fun dayFile(dir: File, day: String): File =
        File(dir, "${LocalDate.parse(day).format(DAY_FILE)}.json")

    // ---------- AI 睡眠计算 ----------
    private suspend fun calculateSleep() {
        sleepDir.mkdirs()
        rriDir.mkdirs()
        val dayFiles = sleepDir.listFiles { f -> f.name.endsWith(".json") } ?: return
        var saved = 0
        var uploaded = 0
        val zone = ZoneId.systemDefault()
        dayFiles.forEach { todayFile ->
            val dayKey = todayFile.nameWithoutExtension
            val localDate = runCatching { LocalDate.parse(dayKey, DAY_FILE) }.getOrNull() ?: return@forEach
            val yesterdayFile = File(sleepDir, "${localDate.minusDays(1).format(DAY_FILE)}.json")
            val yesRri = loadRri(localDate.minusDays(1))
            val todayRri = loadRri(localDate)
            val result = SA_SleepBufInfo()
            val status = try {
                NativeInvoker().calculateSleepFileWithAF(
                    yesterdayFile.absolutePath,
                    todayFile.absolutePath,
                    dayKey,
                    1,
                    yesRri,
                    todayRri,
                    result,
                )
            } catch (e: Throwable) {
                onEvent("AI 睡眠计算异常（$dayKey）：${e.message}")
                return@forEach
            }
            result.datastatus = status
            val sleepSegs = result.sleepdata ?: return@forEach
            if (sleepSegs.isEmpty() || (result.datastatus != 0 && result.datastatus != 1)) {
                onEvent("睡眠计算无有效结果（$dayKey，status=$status）")
                return@forEach
            }
            val startMs = timeInfoToEpoch(result.inSleepTime, zone)
            val endMs = timeInfoToEpoch(result.outSleepTime, zone)
            if (startMs == null || endMs == null || endMs <= startMs) return@forEach

            val recordSegments = sleepSegs.mapNotNull { info ->
                val s = timeInfoToEpoch(info.startTime, zone) ?: return@mapNotNull null
                val e = timeInfoToEpoch(info.stopTime, zone) ?: return@mapNotNull null
                val stage = stageName(info.sleepMode) ?: return@mapNotNull null
                SleepSegment(stage, s, e)
            }.sortedBy { it.start }
            if (recordSegments.isEmpty()) return@forEach

            val id = "band:$startMs:$endMs"
            val record = SleepRecord(
                id = id,
                start = Instant.ofEpochMilli(startMs),
                end = Instant.ofEpochMilli(endMs),
                zoneId = zone,
                source = SleepSource.BAND,
                segments = recordSegments,
                heartSamples = emptyList(),
                averageHeartRate = null,
                averageSpO2 = null,
                averageRespiratoryRate = null,
                note = "BIO-7349 设备睡眠（AI 算法）",
                metadata = SleepMetadata(externalSource = "iwown-bio", externalId = id, bioNight = true),
            )
            AppDatabase.get(context).sleepRecordDao().upsert(SleepRecordMapper.toEntity(record))
            saved++
            if (signedIn()) {
                val api = client() ?: return@forEach
                runCatching {
                    AutomaticSync(context) { api }.pushSleepRecord(
                        record = record,
                        scope = userScopeId(),
                        deviceId = deviceIdProvider(),
                        deviceName = "BIO-7349",
                    )
                }.onSuccess { uploaded++ }
                    .onFailure { onEvent("睡眠记录上传失败：${it.message}") }
            }
        }
        val suffix = if (signedIn() && uploaded > 0) {
            "，其中 $uploaded 条已上传账号云端"
        } else if (!signedIn()) {
            "（已存本地，登录后可同步）"
        } else {
            ""
        }
        onEvent("睡眠计算完成：入库 $saved 条$suffix")
    }

    /** 读取某天的 RRI（按 seq 排序拼接，过滤 -1）。 */
    private fun loadRri(date: LocalDate): DoubleArray {
        val file = File(rriDir, "${date.format(DAY_FILE)}.json")
        if (!file.exists()) return DoubleArray(0)
        val obj = runCatching { JSONObject.parseObject(file.readText()) }.getOrNull() ?: return DoubleArray(0)
        val values = mutableListOf<Double>()
        obj.keySet().asSequence()
            .mapNotNull { it.toIntOrNull() }
            .sorted()
            .forEach { seq ->
                val arr = obj.getJSONArray(seq.toString()) ?: return@forEach
                for (i in 0 until arr.size()) {
                    val v = arr.optInt(i, -1)
                    if (v != -1) values.add(v.toDouble())
                }
            }
        return values.toDoubleArray()
    }

    /** SA_TimeInfo 的 year 相对 2000 年。 */
    private fun timeInfoToEpoch(
        info: com.iwown.app.nativeinvoke.SA_TimeInfo?,
        zone: ZoneId,
    ): Long? {
        if (info == null) return null
        val year = info.year + 2000
        if (year !in 2000..2100 || info.month !in 1..12 || info.day !in 1..31) return null
        return runCatching {
            LocalDateTime.of(year, info.month, info.day, info.hour, info.minute, 0)
                .atZone(zone).toInstant().toEpochMilli()
        }.getOrNull()
    }

    private fun localEpochMs(year: Int, month: Int, day: Int, hour: Int, minute: Int): Long {
        val zone = ZoneId.systemDefault()
        return runCatching {
            LocalDateTime.of(year, month, day, hour.coerceIn(0, 23), minute.coerceIn(0, 59))
                .atZone(zone).toInstant().toEpochMilli()
        }.getOrDefault(System.currentTimeMillis())
    }
}
