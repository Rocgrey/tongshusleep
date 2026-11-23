package com.rocgrey.sleeptongshu.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf

val LocalSleepPalette = staticCompositionLocalOf { paletteFor(AppAppearance.FRESH, false) }
val LocalAppAppearance = staticCompositionLocalOf { AppAppearance.FRESH }

private fun schemeFor(dark: Boolean, appearance: AppAppearance): ColorScheme {
    val p = paletteFor(appearance, dark)
    return if (dark) darkColorScheme(
        primary = p.teal, secondary = p.mint, tertiary = p.rem,
        background = p.background, surface = p.surface,
        onBackground = p.ink, onSurface = p.ink, outline = p.line,
    ) else lightColorScheme(
        primary = p.teal, secondary = p.mint, tertiary = p.rem,
        background = p.background, surface = p.surface,
        onBackground = p.ink, onSurface = p.ink, outline = p.line,
    )
}

@Composable
fun TongshuTheme(
    appearance: AppAppearance,
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val palette = paletteFor(appearance, darkTheme)
    CompositionLocalProvider(
        LocalSleepPalette provides palette,
        LocalAppAppearance provides appearance,
    ) {
        MaterialTheme(
            colorScheme = schemeFor(darkTheme, appearance),
            typography = TongshuTypography,
            content = content,
        )
    }
}
