package online.reeeserve.lunkalarm.core

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import online.reeeserve.lunkalarm.Themes
import org.junit.Assert.*
import org.junit.Test

class ThemeContrastTest {
    private fun contrast(a: Color, b: Color): Float {
        val x = a.luminance(); val y = b.luminance()
        return (maxOf(x, y) + .05f) / (minOf(x, y) + .05f)
    }
    @Test fun allEighteenPalettesHaveReadablePrimaryAndSecondaryText() {
        assertEquals(18, Themes.all.size)
        Themes.all.forEach { theme ->
            for (surface in listOf(theme.background)) {
                assertTrue("${theme.name} text contrast", contrast(theme.text, surface) >= 4.5f)
                assertTrue("${theme.name} secondary contrast", contrast(theme.muted, surface) >= 4.5f)
            }
            val card = theme.cardPalette
            assertTrue("${theme.name} card text", contrast(card.text, card.card) >= 4.5f)
            assertTrue("${theme.name} card detail", contrast(card.muted, card.card) >= 4.5f)
        }
    }
}
