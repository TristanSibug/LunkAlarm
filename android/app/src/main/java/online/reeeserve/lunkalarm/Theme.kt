package online.reeeserve.lunkalarm

import android.graphics.Typeface
import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import android.widget.EditText
import android.widget.NumberPicker
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView

@Immutable data class LunkTheme(val id: String, val name: String, val background: Color, val card: Color, val text: Color,
    val muted: Color, val accent: Color, val accent2: Color, val light: Boolean = false, val glow: Boolean = false) {
    val field get() = if (light) Color.Black.copy(alpha = .045f) else Color.Black.copy(alpha = .25f)
    val border get() = text.copy(alpha = .1f)
    val onAccent get() = if (light) Color.White else Color(0xff160f12)
    val gradient get() = Brush.horizontalGradient(listOf(accent, accent2))
}
private fun palette(id: String, name: String, bg: Long, card: Long, text: Long, muted: Long, accent: Long, accent2: Long, light: Boolean = false, glow: Boolean = false) =
    LunkTheme(id, name, Color(bg or 0xff000000), Color(card or 0xff000000), Color(text or 0xff000000), Color(muted or 0xff000000), Color(accent or 0xff000000), Color(accent2 or 0xff000000), light, glow)
object Themes {
    val all = listOf(
        palette("light", "Light", 0xf3f2fa, 0xffffff, 0x1c1b2e, 0x5b5c76, 0xc4520a, 0xd6336c, true, true),
        palette("linen", "Linen", 0xf5efe5, 0xfffcf6, 0x302921, 0x766858, 0x986020, 0xb34938, true),
        palette("sea-glass", "Sea Glass", 0xeaf3ef, 0xf9fffc, 0x173c37, 0x526d67, 0x237268, 0x346d8e, true),
        palette("oled", "OLED Black", 0x000000, 0x0c0c0e, 0xf2f2f5, 0x9a9aa3, 0xffa94d, 0xff6b7a),
        palette("dark", "Dark", 0x17181c, 0x212329, 0xececf1, 0x9a9ba6, 0xffa94d, 0xff6b7a),
        palette("sunrise", "Sunrise", 0x0a0c16, 0x171923, 0xf4f2ff, 0x9a9bb8, 0xffa94d, 0xff6b7a, glow = true),
        palette("ember", "Ember", 0x1b1110, 0x2b1d1a, 0xffeee3, 0xc3a49a, 0xffbb74, 0xef876d),
        palette("forest", "Forest", 0x0b1714, 0x142720, 0xe4f2e9, 0x9bb5a4, 0x9dcc88, 0x59c7a5),
        palette("nord", "Nord", 0x2e3440, 0x3b4252, 0xeceff4, 0xa4b1c4, 0x88c0d0, 0x81a1c1),
        palette("deep-ocean", "Deep Ocean", 0x081a24, 0x102b38, 0xe1f5fb, 0x99b9c6, 0x79d2de, 0x82b0f7),
        palette("vscode-blue", "VS Code Blue", 0x002451, 0x082e59, 0xe8f0ff, 0xa2bcdb, 0x5db0ff, 0x3a86ff),
        palette("tokyo-night", "Tokyo Night", 0x1a1b26, 0x24283b, 0xc0caf5, 0x8c93bf, 0x7aa2f7, 0xbb9af7),
        palette("amethyst", "Amethyst", 0x171123, 0x251d36, 0xf1eaff, 0xb3a3cb, 0xc5a2ff, 0xf0a4ce),
        palette("dracula", "Dracula", 0x282a36, 0x303241, 0xf8f8f2, 0xa7a5bd, 0xbd93f9, 0xff79c6))
    fun find(id: String) = all.firstOrNull { it.id == id } ?: all.first { it.id == "sunrise" }
}
@Composable fun LunkStyle(theme: LunkTheme, content: @Composable () -> Unit) {
    val colors = if (theme.light) lightColorScheme() else darkColorScheme()
    MaterialTheme(colorScheme = colors.copy(primary = theme.accent, onPrimary = theme.onAccent, secondary = theme.accent2,
        background = theme.background, surface = theme.card, onBackground = theme.text, onSurface = theme.text,
        onSurfaceVariant = theme.muted, outline = theme.border, surfaceVariant = theme.field), content = content)
}
fun haptic(view: View, strong: Boolean = false) {
    view.performHapticFeedback(if (strong) HapticFeedbackConstants.LONG_PRESS else HapticFeedbackConstants.KEYBOARD_TAP)
}
@Composable fun AccentButton(text: String, theme: LunkTheme, modifier: Modifier = Modifier, enabled: Boolean = true, click: () -> Unit) {
    Box(modifier.fillMaxWidth().heightIn(min = 52.dp).alpha(if (enabled) 1f else .45f)
        .clip(RoundedCornerShape(16.dp)).background(theme.gradient).clickable(enabled = enabled, role = androidx.compose.ui.semantics.Role.Button, onClick = click)
        .padding(horizontal = 12.dp, vertical = 15.dp), contentAlignment = androidx.compose.ui.Alignment.Center) {
        Text(text, color = theme.onAccent, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
    }
}
@Composable fun Chip(text: String, theme: LunkTheme, modifier: Modifier = Modifier, click: () -> Unit) {
    TextButton(onClick = click, modifier = modifier.border(1.dp, theme.border, RoundedCornerShape(50)).background(theme.text.copy(alpha = .055f), RoundedCornerShape(50)),
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp)) { Text(text, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = theme.text) }
}
@Composable fun SectionLabel(text: String, theme: LunkTheme) { Text(text.uppercase(), color = theme.muted, fontSize = 11.sp, letterSpacing = .7.sp) }
@Composable fun Wheel(value: Int, range: IntRange, theme: LunkTheme, tag: String, modifier: Modifier = Modifier,
    labels: List<String>? = null, change: (Int) -> Unit) {
    val latest by rememberUpdatedState(change)
    AndroidView(modifier = modifier.height(116.dp).clip(RoundedCornerShape(12.dp)).testTag(tag), factory = { context ->
        NumberPicker(context).apply {
            minValue = range.first; maxValue = range.last; wrapSelectorWheel = true
            descendantFocusability = NumberPicker.FOCUS_BLOCK_DESCENDANTS
            setOnValueChangedListener { _, _, selected -> latest(selected) }
        }
    }, update = { picker ->
        picker.setOnValueChangedListener(null)
        picker.displayedValues = null; picker.minValue = range.first; picker.maxValue = range.last
        picker.displayedValues = labels?.toTypedArray(); picker.wrapSelectorWheel = range.count() > 2
        picker.value = value.coerceIn(range)
        if (Build.VERSION.SDK_INT >= 29) { picker.textColor = theme.text.toArgb(); picker.textSize = 28f * picker.resources.displayMetrics.scaledDensity; picker.selectionDividerHeight = 0 }
        for (index in 0 until picker.childCount) (picker.getChildAt(index) as? EditText)?.apply {
            setTextColor(theme.text.toArgb()); textSize = 28f; typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
            isCursorVisible = false; isFocusable = false; isLongClickable = false; setBackgroundColor(android.graphics.Color.TRANSPARENT)
        }
        picker.contentDescription = "$tag: ${labels?.getOrNull(value - range.first) ?: value}"
        picker.setOnValueChangedListener { _, _, selected -> latest(selected) }
    })
}
