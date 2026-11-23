package com.rocgrey.sleeptongshu.core.monitor

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.rocgrey.sleeptongshu.core.sleep.PhoneNight
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.sqrt
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** 手机监测结果总线：服务停止时产出 PhoneNight 供监测页展示。 */
object PhoneMonitorResultBus {
    private val _latest = MutableStateFlow<PhoneNight?>(null)
    val latest: StateFlow<PhoneNight?> = _latest.asStateFlow()

    fun publish(night: PhoneNight) {
        _latest.value = night
    }

    fun clear() {
        _latest.value = null
    }
}

/**
 * 手机睡眠监测前台服务（对应 iOS quiet-window-v1 启发式）：
 * - AudioRecord 16kHz 单声道采集 + 加速度计体动；
 * - 每分钟聚合 audioSeconds / soundDB / movement；
 * - 连续 15 个安静分钟视为入睡点，estimatedMinutes = 之后安静音频秒数；
 * - iOS SoundAnalysis 无 Android 内置等价物，snore/speech 恒 0。
 * RECORD_AUDIO 运行时权限由 UI 层申请，服务启动时再次检查。
 */
class PhoneMonitorService : Service() {

    companion object {
        const val CHANNEL_ID = "phone-monitor"
        private const val NOTIFICATION_ID = 4213

        /** 声音分类器不可用（iOS SoundAnalysis 无 Android 内置等价物）。 */
        const val CLASSIFIER_AVAILABLE = false

        private const val SAMPLE_RATE = 16000
        private const val QUIET_DB = 34.0
        private const val QUIET_MOVEMENT_PER_MINUTE = 10
        private const val QUIET_RUN_MINUTES = 15

        val running = MutableStateFlow(false)
        val minuteCount = MutableStateFlow(0)

        fun start(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, PhoneMonitorService::class.java),
            )
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, PhoneMonitorService::class.java))
        }
    }

    /** 每分钟聚合的一条数据。 */
    private data class MinuteEpoch(
        val startMs: Long,
        val dbAvg: Double,
        val movementSamples: Int,
        val quiet: Boolean,
    )

    private val workerActive = AtomicBoolean(false)
    private var audioRecord: AudioRecord? = null
    private var workerThread: Thread? = null
    private val epochs = mutableListOf<MinuteEpoch>()
    private var movementSamples = 0
    private var lastMovementAt = 0L

    private val sensorListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val magnitude = sqrt(
                event.values[0] * event.values[0] +
                    event.values[1] * event.values[1] +
                    event.values[2] * event.values[2],
            )
            val now = System.currentTimeMillis()
            if (abs(magnitude - SensorManager.GRAVITY_EARTH) > 1.0 && now - lastMovementAt > 500) {
                synchronized(this@PhoneMonitorService) {
                    movementSamples += 1
                    lastMovementAt = now
                }
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForegroundWithNotification()
        running.value = true
        registerMovementSensor()
        startAudioWorker()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY

    override fun onDestroy() {
        workerActive.set(false)
        workerThread?.interrupt()
        runCatching { audioRecord?.stop() }
        runCatching { audioRecord?.release() }
        audioRecord = null
        val sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        sensorManager.unregisterListener(sensorListener)
        val night = buildPhoneNight()
        if (night != null) PhoneMonitorResultBus.publish(night)
        running.value = false
        minuteCount.value = 0
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "手机睡眠监测",
            NotificationManager.IMPORTANCE_LOW,
        ).apply { description = "正在用手机麦克风与传感器监测睡眠环境" }
        manager.createNotificationChannel(channel)
    }

    private fun startForegroundWithNotification() {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("手机睡眠监测中")
            .setContentText("正在采集环境声音与体动，停止后生成夜间结果")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 30) {
            val type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                (if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH else 0)
            startForeground(NOTIFICATION_ID, notification, type)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun registerMovementSensor() {
        val sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        sensorManager.registerListener(
            sensorListener,
            sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER),
            SensorManager.SENSOR_DELAY_NORMAL,
        )
    }

    private fun startAudioWorker() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            stopSelf()
            return
        }
        if (!workerActive.compareAndSet(false, true)) return
        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val record = try {
            AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                maxOf(minBuffer, SAMPLE_RATE) * 2,
            )
        } catch (_: SecurityException) {
            stopSelf()
            return
        }
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            stopSelf()
            return
        }
        audioRecord = record
        val buffer = ShortArray(SAMPLE_RATE)
        workerThread = Thread {
            record.startRecording()
            var secondCount = 0
            var dbSum = 0.0
            var minuteStart = System.currentTimeMillis()
            while (workerActive.get() && !Thread.currentThread().isInterrupted) {
                val read = runCatching { record.read(buffer, 0, buffer.size) }.getOrDefault(0)
                if (read <= 0) continue
                dbSum += computeDb(buffer, read)
                secondCount += 1
                if (secondCount >= 60) {
                    val dbAvg = dbSum / secondCount
                    val now = System.currentTimeMillis()
                    val movement = synchronized(this) {
                        val current = movementSamples
                        movementSamples = 0
                        current
                    }
                    val epoch = MinuteEpoch(
                        startMs = minuteStart,
                        dbAvg = dbAvg,
                        movementSamples = movement,
                        quiet = dbAvg < QUIET_DB && movement < QUIET_MOVEMENT_PER_MINUTE,
                    )
                    synchronized(epochs) { epochs.add(epoch) }
                    minuteCount.value = synchronized(epochs) { epochs.size }
                    secondCount = 0
                    dbSum = 0.0
                    minuteStart = now
                }
            }
            runCatching { record.stop() }
            runCatching { record.release() }
        }.also { it.start() }
    }

    private fun computeDb(buffer: ShortArray, read: Int): Double {
        var sum = 0.0
        for (i in 0 until read) {
            val s = buffer[i].toDouble()
            sum += s * s
        }
        val rms = sqrt(sum / read.coerceAtLeast(1))
        if (rms <= 0.0) return 0.0
        return (20.0 * log10(rms / 32768.0) + 96.0).coerceIn(0.0, 120.0)
    }

    /** 静默窗启发式：连续 15 个安静分钟 -> 入睡点；估算时长 = 之后安静分钟秒数。 */
    private fun buildPhoneNight(): PhoneNight? {
        val snapshot = synchronized(epochs) { epochs.toList() }
        if (snapshot.isEmpty()) return null
        var onsetIndex = -1
        var run = 0
        for ((index, epoch) in snapshot.withIndex()) {
            run = if (epoch.quiet) run + 1 else 0
            if (run >= QUIET_RUN_MINUTES) {
                onsetIndex = index - QUIET_RUN_MINUTES + 1
                break
            }
        }
        val estimatedMinutes = if (onsetIndex >= 0) {
            snapshot.drop(onsetIndex).count { it.quiet } * 60
        } else {
            null
        }
        return PhoneNight(
            estimatedMinutes = estimatedMinutes,
            audioSeconds = snapshot.size * 60,
            // 无声音分类器：iOS SoundAnalysis 无等价内置实现
            snoreSeconds = 0,
            speechSeconds = 0,
            movementSamples = snapshot.sumOf { it.movementSamples },
        )
    }
}
