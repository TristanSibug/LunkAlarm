package online.reeeserve.lunkalarm

import android.os.SystemClock
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.*
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.delay
import online.reeeserve.lunkalarm.core.*

enum class WakeTest(val title: String, val short: String) {
    TYPING("Typing test", "Typing"), MATH("Math test", "Math"), PUZZLE("Puzzle test", "Puzzle"),
    MINES("Minesweeper test", "Minesweeper"), SUDOKU("Sudoku test", "Sudoku");
    fun enabled(d: AlarmDraft) = when (this) { TYPING -> d.typing; MATH -> d.mathCount > 0; PUZZLE -> d.puzzle; MINES -> d.mines; SUDOKU -> d.sudoku }
    fun only(d: AlarmDraft) = d.copy(typing = this == TYPING, mathCount = if (this == MATH) d.mathCount.coerceAtLeast(1) else 0,
        puzzle = this == PUZZLE, mines = this == MINES, sudoku = this == SUDOKU)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun WakeTestSelector(draft: AlarmDraft, theme: LunkTheme, change: (AlarmDraft) -> Unit, beforePractice: () -> Unit) {
    var settings by rememberSaveable { mutableStateOf<WakeTest?>(null) }
    var practice by rememberSaveable { mutableStateOf<WakeTest?>(null) }
    var mathCount by rememberSaveable { mutableIntStateOf(draft.mathCount.takeIf { it > 0 } ?: 3) }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        WakeTest.entries.forEach { test ->
            val enabled = test.enabled(draft)
            Box(Modifier.weight(1f).clip(RoundedCornerShape(12.dp))
                .background(if (enabled) theme.accent2.copy(alpha = .1f) else theme.field)
                .border(if (enabled) 1.5.dp else 1.dp, if (enabled) theme.accent2 else theme.border, RoundedCornerShape(12.dp))
                .toggleable(enabled, role = Role.Checkbox) { value ->
                    val next = when (test) {
                        WakeTest.TYPING -> draft.copy(typing = value)
                        WakeTest.MATH -> { if (!value) mathCount = draft.mathCount; draft.copy(mathCount = if (value) mathCount else 0) }
                        WakeTest.PUZZLE -> draft.copy(puzzle = value)
                        WakeTest.MINES -> draft.copy(mines = value)
                        WakeTest.SUDOKU -> draft.copy(sudoku = value)
                    }
                    change(next)
                    settings = if (value) test else null
                }.semantics { contentDescription = test.title }.testTag("test-tile-${test.name.lowercase()}")) {
                Column(Modifier.fillMaxWidth().padding(top = 18.dp, bottom = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(9.dp)) {
                    TestGlyph(test, if (enabled) theme.accent2 else theme.muted, Modifier.size(25.dp))
                    Text(test.short, color = theme.text, fontSize = if (test == WakeTest.MINES) 9.sp else 10.sp, maxLines = 1)
                }
                if (enabled) Icon(Icons.Default.Check, null, Modifier.align(Alignment.TopEnd).padding(3.dp).size(13.dp), tint = theme.accent2)
            }
        }
    }
    settings?.let { test ->
        ModalBottomSheet(onDismissRequest = { settings = null }, containerColor = theme.card,
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 24.dp)
                .testTag("test-settings-${test.name.lowercase()}"), verticalArrangement = Arrangement.spacedBy(22.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(test.title, color = theme.text, fontSize = 19.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f, fill = false))
                    OutlinedButton(onClick = { beforePractice(); practice = test }, contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp),
                        border = BorderStroke(1.dp, theme.accent2), modifier = Modifier.testTag("try-${test.name.lowercase()}")) {
                        Icon(Icons.Default.PlayArrow, null, Modifier.size(17.dp), tint = theme.accent2)
                        Text("Try", color = theme.text, fontSize = 12.sp)
                    }
                    }
                    IconButton(onClick = { settings = null }, modifier = Modifier.size(36.dp).testTag("close-test-settings")) { Icon(Icons.Default.Close, "Close test settings", tint = theme.muted) }
                }
                when (test) {
                    WakeTest.TYPING -> Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        SettingBox(Modifier.weight(.42f), theme) { CountSetting("Code length", draft.codeLength, 4..10, "4–10 characters", "typing-length", theme) { change(draft.copy(codeLength = it)) } }
                        SettingBox(Modifier.weight(.58f), theme) { ChoiceSetting("Time limit", draft.typingSeconds, WakeTimers.typing, "typing-timer", theme, suffix = "", footer = "seconds") { change(draft.copy(typingSeconds = it)) } }
                    }
                    WakeTest.MATH -> {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            SettingBox(Modifier.weight(.42f), theme) { CountSetting("Problems", draft.mathCount.coerceAtLeast(1), 1..8, "1–8 problems", "math-count", theme) { mathCount = it; change(draft.copy(mathCount = it)) } }
                            SettingBox(Modifier.weight(.58f), theme) { ChoiceSetting("Time per question", draft.mathSeconds, WakeTimers.math, "math-timer", theme) { change(draft.copy(mathSeconds = it)) } }
                        }
                        HorizontalDivider(color = theme.border)
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text("Use native keyboard/keypad", color = theme.text, fontSize = 13.sp, modifier = Modifier.weight(1f))
                            Switch(draft.nativeMathKeyboard, onCheckedChange = { change(draft.copy(nativeMathKeyboard = it)) }, modifier = Modifier.testTag("native-math-keyboard"))
                        }
                    }
                    WakeTest.PUZZLE -> {
                        ChoiceSetting("Pieces", draft.puzzlePieces, WakeTimers.pieces, "puzzle-pieces", theme, suffix = "") { change(draft.copy(puzzlePieces = it)) }
                        ChoiceSetting("Time limit", draft.puzzleSeconds, WakeTimers.puzzle, "puzzle-timer", theme) { change(draft.copy(puzzleSeconds = it)) }
                    }
                    WakeTest.MINES -> {
                        Text("Difficulty", color = theme.text, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            listOf("Easy", "Medium", "Hard").forEachIndexed { i, name ->
                                DifficultyCard(name, "${i + 3} × ${i + 3}", draft.mineDifficulty == i, WakeTest.MINES, theme, Modifier.weight(1f).testTag("mine-difficulty-$i")) { change(draft.copy(mineDifficulty = i)) }
                            }
                        }
                        ChoiceSetting("Time limit", draft.mineSeconds, WakeTimers.mines, "mine-timer", theme) { change(draft.copy(mineSeconds = it)) }
                    }
                    WakeTest.SUDOKU -> {
                        Text("Difficulty", color = theme.text, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            listOf(0..1, 2..3).forEach { row -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { row.forEach { i ->
                                DifficultyCard(listOf("Easy", "Medium", "Hard", "Difficult")[i], "${if (i < 2) "4 × 4" else "6 × 6"} · ${if (i % 2 == 0) "Easy" else "Hard"}",
                                    draft.sudokuDifficulty == i, WakeTest.SUDOKU, theme, Modifier.weight(1f).testTag("sudoku-difficulty-$i")) { change(draft.copy(sudokuDifficulty = i)) }
                            } } }
                        }
                        ChoiceSetting("Time limit", draft.sudokuSeconds, WakeTimers.sudoku, "sudoku-timer", theme) { change(draft.copy(sudokuSeconds = it)) }
                    }
                }
                AccentButton("Done", theme, Modifier.testTag("test-settings-done")) { settings = null }
            }
        }
    }
    practice?.let { test -> PracticeTest(test, draft, theme) { practice = null } }
}

@Composable private fun SettingBox(modifier: Modifier, theme: LunkTheme, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.clip(RoundedCornerShape(14.dp)).background(theme.field).border(1.dp, theme.border, RoundedCornerShape(14.dp)).padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
}
@Composable private fun CountSetting(title: String, value: Int, range: IntRange, footer: String, tag: String, theme: LunkTheme, change: (Int) -> Unit) {
    Text(title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = theme.text)
    Row(Modifier.fillMaxWidth().testTag(tag), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
        listOf(-1, 0, 1).forEach { delta ->
            if (delta == 0) Text("$value", color = theme.text, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.testTag("$tag-value"))
            else Box(Modifier.size(32.dp, 44.dp).clip(RoundedCornerShape(9.dp)).background(theme.text.copy(alpha = .06f))
                .border(1.dp, theme.border, RoundedCornerShape(9.dp)).clickable(enabled = value + delta in range, role = Role.Button) { change(value + delta) }
                .semantics { contentDescription = "${if (delta < 0) "Decrease" else "Increase"} $title"; if (value + delta !in range) disabled() }
                .testTag("$tag-${if (delta < 0) "minus" else "plus"}"), contentAlignment = Alignment.Center) {
                Text(if (delta < 0) "−" else "+", color = theme.text.copy(alpha = if (value + delta in range) 1f else .25f), fontSize = 23.sp)
            }
        }
    }
    Text(footer, fontSize = 11.sp, color = theme.muted)
}
@Composable private fun ChoiceSetting(title: String, value: Int, choices: List<Int>, tag: String, theme: LunkTheme, suffix: String = " s", footer: String? = null, change: (Int) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, color = theme.text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Row(Modifier.fillMaxWidth().testTag(tag), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            choices.forEach { n ->
                Box(Modifier.weight(1f).heightIn(min = 44.dp).clip(RoundedCornerShape(10.dp))
                    .background(if (n == value) theme.accent2 else theme.field).border(1.dp, if (n == value) theme.accent2 else theme.border, RoundedCornerShape(10.dp))
                    .clickable(role = Role.RadioButton) { change(n) }.semantics { selected = n == value; contentDescription = "$title: $n${if (suffix.isEmpty()) "" else " seconds"}" }
                    .testTag("$tag-$n").padding(vertical = 10.dp), contentAlignment = Alignment.Center) {
                    Text("$n$suffix", color = if (n == value) theme.onAccent else theme.text, fontSize = if (choices.size > 4) 11.sp else 12.sp, maxLines = 1)
                }
            }
        }
        if (footer != null) Text(footer, color = theme.muted, fontSize = 11.sp)
    }
}
@Composable private fun DifficultyCard(title: String, detail: String, selected: Boolean, glyph: WakeTest, theme: LunkTheme, modifier: Modifier, click: () -> Unit) {
    Column(modifier.clip(RoundedCornerShape(12.dp)).background(if (selected) theme.accent2.copy(alpha = .12f) else theme.field)
        .border(if (selected) 1.5.dp else 1.dp, if (selected) theme.accent2 else theme.border, RoundedCornerShape(12.dp))
        .clickable(role = Role.RadioButton, onClick = click).semantics { this.selected = selected; contentDescription = "$title, $detail" }
        .padding(horizontal = 8.dp, vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        TestGlyph(glyph, if (selected) theme.accent2 else theme.muted, Modifier.size(22.dp))
        Text(title, color = theme.text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Text(detail, color = theme.muted, fontSize = 11.sp)
    }
}
@Composable fun TestGlyph(test: WakeTest, color: Color, modifier: Modifier = Modifier) {
    if (test == WakeTest.TYPING || test == WakeTest.MATH) Box(modifier, contentAlignment = Alignment.Center) {
        Text(if (test == WakeTest.TYPING) "Aa" else "+=", color = color, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
    } else Canvas(modifier) {
        val w = size.width; val h = size.height; val stroke = Stroke(1.5.dp.toPx())
        when (test) {
            WakeTest.MINES -> {
                drawCircle(color, w * .27f, center, style = stroke)
                for (i in 0..7) { val angle = i * Math.PI / 4; val unit = Offset(kotlin.math.cos(angle).toFloat(), kotlin.math.sin(angle).toFloat())
                    drawLine(color, center + unit * w * .29f, center + unit * w * .46f, 1.5.dp.toPx()) }
                drawCircle(color, w * .045f, center - Offset(w * .09f, h * .09f))
            }
            WakeTest.SUDOKU -> { drawRect(color, Offset(w * .08f, h * .08f), androidx.compose.ui.geometry.Size(w * .84f, h * .84f), style = stroke)
                for (i in 1..3) { val f = .08f + i * .21f; drawLine(color, Offset(w * f, h * .08f), Offset(w * f, h * .92f), if (i == 2) 1.5.dp.toPx() else .7.dp.toPx())
                    drawLine(color, Offset(w * .08f, h * f), Offset(w * .92f, h * f), if (i == 2) 1.5.dp.toPx() else .7.dp.toPx()) } }
            WakeTest.PUZZLE -> {
                val p = Path().apply { moveTo(w * .1f, h * .18f); lineTo(w * .4f, h * .18f)
                    cubicTo(w * .25f, -h * .05f, w * .75f, -h * .05f, w * .6f, h * .18f)
                    lineTo(w * .88f, h * .18f); lineTo(w * .88f, h * .42f)
                    cubicTo(w * .62f, h * .28f, w * .62f, h * .78f, w * .88f, h * .62f)
                    lineTo(w * .88f, h * .9f); lineTo(w * .6f, h * .9f)
                    cubicTo(w * .75f, h * .65f, w * .25f, h * .65f, w * .4f, h * .9f)
                    lineTo(w * .1f, h * .9f); close() }
                drawPath(p, color, style = stroke)
            }
            else -> Unit
        }
    }
}

@Composable private fun PracticeTest(test: WakeTest, draft: AlarmDraft, theme: LunkTheme, close: () -> Unit) {
    val snapshot = remember(test) { test.only(draft) }
    var challenge by remember(test) { mutableStateOf(WakeChallenge.create(snapshot).start(SystemClock.elapsedRealtime())) }
    var now by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    LaunchedEffect(Unit) { while (true) { now = SystemClock.elapsedRealtime(); challenge = challenge.expire(now); delay(200) } }
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        BackHandler(onBack = close)
        Column(Modifier.fillMaxSize().background(theme.background).windowInsetsPadding(WindowInsets.safeDrawing).imePadding().testTag("practice-test")) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("${test.short} practice", color = theme.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                IconButton(onClick = close, modifier = Modifier.testTag("exit-practice")) { Icon(Icons.Default.Close, "Exit practice", tint = theme.text) }
            }
            Text(if (challenge.complete) "Practice complete" else "${challenge.secondsLeft(now)}s", color = theme.muted, modifier = Modifier.padding(horizontal = 24.dp).testTag("practice-countdown"))
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                if (challenge.complete) {
                    Text("Well done!", color = theme.text, fontSize = 26.sp)
                    AccentButton("Try again", theme, Modifier.testTag("retry-practice")) { challenge = WakeChallenge.create(snapshot).start(SystemClock.elapsedRealtime()) }
                    OutlinedButton(onClick = close) { Text("Back to settings", color = theme.text) }
                } else WakeChallengeContent(challenge, snapshot, theme,
                    submit = { text, typing -> (if (typing) challenge.submitCode(text, SystemClock.elapsedRealtime()) else challenge.submitDigits(text, SystemClock.elapsedRealtime())).also { challenge = it.challenge }.result },
                    place = { challenge = challenge.placePiece(it, SystemClock.elapsedRealtime()).challenge },
                    mine = { cell, flag -> challenge = challenge.mineAction(cell, flag, SystemClock.elapsedRealtime()).challenge },
                    sudoku = { cell, digit -> challenge = challenge.sudokuAction(cell, digit, SystemClock.elapsedRealtime()).challenge })
            }
        }
    }
}
