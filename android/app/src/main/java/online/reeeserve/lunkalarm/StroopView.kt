package online.reeeserve.lunkalarm

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.*
import online.reeeserve.lunkalarm.core.*
import kotlin.math.min

@Composable fun StroopView(challenge: WakeChallenge, theme: LunkTheme, submit: (StroopColor) -> Unit) {
    val round = challenge.stroopRound ?: return
    val view = LocalView.current
    val fontScale = LocalDensity.current.fontScale
    Column(Modifier.widthIn(max = 480.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text("${challenge.stroopAnswered} / ${challenge.stroopRounds} rounds", color = theme.text, fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold, modifier = Modifier.testTag("stroop-progress"))
        Text("Choose the word’s ink color. Ignore the word and button colors.", color = theme.muted, fontSize = 14.sp, textAlign = TextAlign.Center)
        BoxWithConstraints(Modifier.fillMaxWidth().heightIn(min = 140.dp).clip(RoundedCornerShape(16.dp)).background(Color(0xff10131b))
            .border(1.dp, Color.White.copy(alpha = .14f), RoundedCornerShape(16.dp)).padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
            Text(round.word.label.uppercase(), color = round.ink.inkColor, fontSize = min(56f, maxWidth.value / (4.5f * fontScale)).sp,
                fontWeight = FontWeight.Bold, letterSpacing = 2.sp, maxLines = 1, softWrap = false,
                modifier = Modifier.semantics { contentDescription = "${round.word.label}, written in ${round.ink.label.lowercase()} ink" }.testTag("stroop-word"))
        }
        round.choiceOrder.chunked(2).forEachIndexed { rowIndex, row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                row.forEachIndexed { column, color ->
                    val paint = round.buttonColors[rowIndex * 2 + column]
                    Box(Modifier.weight(1f).heightIn(min = 60.dp).clip(RoundedCornerShape(14.dp)).background(paint.buttonFill)
                        .border(1.dp, Color.White.copy(alpha = .18f), RoundedCornerShape(14.dp))
                        .clickable(role = Role.Button) { haptic(view); submit(color) }
                        .semantics { contentDescription = color.label; stateDescription = "${paint.label} background" }
                        .testTag("stroop-choice-${color.name.lowercase()}").padding(12.dp), contentAlignment = Alignment.Center) {
                        Text(color.label, color = if (paint == StroopColor.YELLOW) Color(0xff17130a) else Color.White, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}

private val StroopColor.inkColor: Color get() = when (this) {
    StroopColor.RED -> Color(0xffff6778); StroopColor.BLUE -> Color(0xff6daaff)
    StroopColor.GREEN -> Color(0xff55dba9); StroopColor.YELLOW -> Color(0xffffda6b)
}
private val StroopColor.buttonFill: Color get() = when (this) {
    StroopColor.RED -> Color(0xff9c2138); StroopColor.BLUE -> Color(0xff2154a0)
    StroopColor.GREEN -> Color(0xff11734e); StroopColor.YELLOW -> Color(0xfff1c84f)
}
