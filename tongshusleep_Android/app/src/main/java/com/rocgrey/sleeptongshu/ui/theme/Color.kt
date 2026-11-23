package com.rocgrey.sleeptongshu.ui.theme

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color

/** 与 iOS AppAppearance.swift 对齐的三套外观。 */
enum class AppAppearance(val key: String, val label: String, val accent: Color) {
    BUSINESS("business", "商务", Color(0xFF1F5C71)),
    FRESH("fresh", "清新", Color(0xFF0A756B)),
    CUTE("cute", "可爱", Color(0xFFAB3563));

    companion object {
        fun fromKey(key: String?): AppAppearance =
            entries.firstOrNull { it.key == key } ?: FRESH
    }
}

/** 与 iOS SleepPalette 对齐，按深浅模式提供两组值。 */
data class SleepPalette(
    val background: Color,
    val surface: Color,
    val ink: Color,
    val muted: Color,
    val teal: Color,
    val rose: Color,
    val mint: Color,
    val deep: Color,
    val rem: Color,
    val awake: Color,
    val line: Color,
)

fun paletteFor(appearance: AppAppearance, dark: Boolean): SleepPalette {
    // 主色按外观区分，其余色板与 iOS 端保持一致的语义分布。
    val teal = appearance.accent
    return if (!dark) SleepPalette(
        background = Color(0xFFF4F7F6),
        surface = Color.White,
        ink = Color(0xFF1C2B2A),
        muted = Color(0xFF5F6F6D),
        teal = teal,
        rose = Color(0xFFC25E79),
        mint = Color(0xFF2F9E8F),
        deep = Color(0xFF2C5E92),
        rem = Color(0xFF7B68B8),
        awake = Color(0xFFC98A3D),
        line = Color(0xFFDFE7E5),
    ) else SleepPalette(
        background = Color(0xFF101C1B),
        surface = Color(0xFF182624),
        ink = Color(0xFFE8F0EE),
        muted = Color(0xFF9AACA9),
        teal = Color(0xFF5FBFB2),
        rose = Color(0xFFE18AA2),
        mint = Color(0xFF57C2B1),
        deep = Color(0xFF6FA3DC),
        rem = Color(0xFFA48FDB),
        awake = Color(0xFFDFAE6B),
        line = Color(0xFF263835),
    )
}
