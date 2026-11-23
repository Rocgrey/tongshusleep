package com.rocgrey.sleeptongshu.core.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

/**
 * 白噪音播放器（对应 iOS WhiteNoisePlayer）：
 * - 程序生成 6 秒白噪 wav（22050Hz，LCG 伪随机），缓存复用
 * - MediaPlayer 循环播放 + 音频焦点（保持播放）
 * - 定时停止（5/15/30/45/60/90 分钟），最后 10 秒线性渐弱
 */
object WhiteNoisePlayer {

    private const val SAMPLE_RATE = 22050
    private const val WAVE_SECONDS = 6
    private const val TICK_MS = 200L
    private const val FADE_SECONDS = 10.0

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying

    /** 剩余秒数；null 表示不限时（持续播放）。 */
    private val _remainingSeconds = MutableStateFlow<Int?>(null)
    val remainingSeconds: StateFlow<Int?> = _remainingSeconds

    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var focusRequest: AudioFocusRequest? = null
    private var audioManager: AudioManager? = null
    private var totalSeconds: Int? = null
    private var elapsedMs: Double = 0.0
    private var fading = false

    private val tick = object : Runnable {
        override fun run() {
            val total = totalSeconds
            if (player == null) return
            elapsedMs += TICK_MS
            val remaining = total?.let { it - (elapsedMs / 1000.0) }
            _remainingSeconds.value = remaining?.let { it.coerceAtLeast(0.0).toInt() }
            if (remaining != null && remaining <= FADE_SECONDS) {
                fading = true
                val fraction = (remaining / FADE_SECONDS).coerceIn(0.0, 1.0)
                player?.setVolume(fraction.toFloat(), fraction.toFloat())
            }
            if (remaining != null && remaining <= 0.0) {
                stop()
                return
            }
            handler.postDelayed(this, TICK_MS)
        }
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        // 保持播放策略：短暂打断不停止
        if (change == AudioManager.AUDIOFOCUS_LOSS) {
            stop()
        }
    }

    /** 开始播放；minutes 为 null 表示不限时持续播放。 */
    fun start(context: Context, minutes: Int?) {
        if (player != null) {
            // 已在播放：仅更新定时
            restartTimer(context, minutes)
            return
        }
        val appContext = context.applicationContext
        totalSeconds = minutes
        elapsedMs = 0.0
        fading = false
        _remainingSeconds.value = minutes
        _isPlaying.value = false
        scope.launch {
            try {
                val manager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioManager = manager
                if (android.os.Build.VERSION.SDK_INT >= 26) {
                    val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                        .setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_MEDIA)
                                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                .build(),
                        )
                        .setOnAudioFocusChangeListener(focusListener)
                        .build()
                    focusRequest = request
                    manager.requestAudioFocus(request)
                } else {
                    @Suppress("DEPRECATION")
                    manager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
                }
                val mp = MediaPlayer()
                player = mp
                mp.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                mp.setDataSource(waveFile(appContext).absolutePath)
                mp.isLooping = true
                mp.prepare()
                mp.setOnCompletionListener { stop() }
                mp.start()
                _isPlaying.value = true
                elapsedMs = 0.0
                totalSeconds = minutes
                handler.removeCallbacks(tick)
                handler.post(tick)
            } catch (_: Exception) {
                releasePlayer()
            }
        }
    }

    private fun restartTimer(context: Context, minutes: Int?) {
        totalSeconds = minutes
        elapsedMs = 0.0
        fading = false
        _remainingSeconds.value = minutes
        player?.setVolume(1f, 1f)
        handler.removeCallbacks(tick)
        handler.post(tick)
    }

    fun stop() {
        releasePlayer()
    }

    private fun releasePlayer() {
        handler.removeCallbacks(tick)
        try {
            player?.stop()
        } catch (_: Exception) {
        }
        player?.release()
        player = null
        val manager = audioManager
        if (android.os.Build.VERSION.SDK_INT >= 26) {
            focusRequest?.let { manager?.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            manager?.abandonAudioFocus(focusListener)
        }
        focusRequest = null
        audioManager = null
        totalSeconds = null
        elapsedMs = 0.0
        fading = false
        _isPlaying.value = false
        _remainingSeconds.value = null
    }

    /** 生成（或复用）6 秒白噪 wav 文件。 */
    private fun waveFile(context: Context): File {
        val file = File(context.cacheDir, "tongshu-white-noise.wav")
        if (file.exists() && file.length() > SAMPLE_RATE * WAVE_SECONDS) return file
        writeWave(file)
        return file
    }

    private fun writeWave(file: File) {
        val samples = SAMPLE_RATE * WAVE_SECONDS
        val dataSize = samples * 2 // 16-bit mono
        DataOutputStream(FileOutputStream(file)).use { out ->
            // RIFF header
            out.writeBytes("RIFF")
            out.writeIntLe(36 + dataSize)
            out.writeBytes("WAVE")
            out.writeBytes("fmt ")
            out.writeIntLe(16)
            out.writeShortLe(1) // PCM
            out.writeShortLe(1) // mono
            out.writeIntLe(SAMPLE_RATE)
            out.writeIntLe(SAMPLE_RATE * 2) // byte rate
            out.writeShortLe(2) // block align
            out.writeShortLe(16) // bits per sample
            out.writeBytes("data")
            out.writeIntLe(dataSize)
            var seed = 0x2A5F1E3D
            repeat(samples) {
                seed = seed * 1103515245 + 12345
                val value = (seed shr 16).toShort()
                out.writeShortLe(value.toInt() and 0xFFFF)
            }
        }
    }

    private fun DataOutputStream.writeIntLe(value: Int) {
        write(value and 0xFF)
        write((value shr 8) and 0xFF)
        write((value shr 16) and 0xFF)
        write((value shr 24) and 0xFF)
    }

    private fun DataOutputStream.writeShortLe(value: Int) {
        write(value and 0xFF)
        write((value shr 8) and 0xFF)
    }

    fun formatRemaining(seconds: Int): String {
        val m = seconds / 60
        val s = seconds % 60
        return String.format(Locale.US, "%02d:%02d", m, s)
    }
}
