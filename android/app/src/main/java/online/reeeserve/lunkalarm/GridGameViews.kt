package online.reeeserve.lunkalarm

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import online.reeeserve.lunkalarm.core.*

@OptIn(ExperimentalFoundationApi::class)
@Composable fun MinesweeperView(board: MineBoard, theme: LunkTheme, action: (Int, Boolean) -> Unit) {
    var flagMode by rememberSaveable { mutableStateOf(false) }
    val view = LocalView.current
    Text("Minesweeper", color = theme.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
    Text("Reveal safe squares and flag all mines.\nTap to reveal · Hold to flag", color = theme.muted, fontSize = 12.sp)
    Row(Modifier.widthIn(max = 360.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text("${board.flags.size}/${board.mines.size} flags", color = theme.muted, fontSize = 13.sp, modifier = Modifier.weight(1f).testTag("mine-progress"))
        Chip(if (flagMode) "⚑ Flag" else "Reveal", theme, Modifier.testTag("mine-mode")) { flagMode = !flagMode }
    }
    Column(Modifier.widthIn(max = 360.dp).fillMaxWidth().testTag("mine-board"), verticalArrangement = Arrangement.spacedBy(7.dp)) {
        repeat(board.size) { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                repeat(board.size) { col ->
                    val cell = row * board.size + col; val revealed = cell in board.revealed; val flagged = cell in board.flags
                    Box(Modifier.weight(1f).aspectRatio(1f).clip(RoundedCornerShape(9.dp))
                        .background(if (revealed) theme.field else theme.accent2.copy(alpha = .13f))
                        .border(1.dp, if (revealed) theme.border else theme.accent2.copy(alpha = .65f), RoundedCornerShape(9.dp))
                        .combinedClickable(enabled = !revealed, role = Role.Button, onClick = { haptic(view); action(cell, flagMode) },
                            onLongClickLabel = "Toggle flag", onLongClick = { haptic(view); action(cell, true) })
                        .semantics { contentDescription = "Row ${row + 1}, column ${col + 1}, " + when {
                            flagged -> "flagged"; revealed -> "${board.number(cell)} adjacent mines"; else -> "hidden" }
                        }.testTag("mine-cell-$cell"), contentAlignment = Alignment.Center) {
                        Text(if (flagged) "⚑" else if (revealed && board.number(cell) != 0) "${board.number(cell)}" else "",
                            color = if (flagged) theme.accent2 else theme.text, fontSize = 24.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}

@Composable fun SudokuView(board: SudokuBoard, theme: LunkTheme, action: (Int, Int) -> Unit) {
    var cell by rememberSaveable(board.givens) { mutableIntStateOf(board.givens.indexOfFirst { it == 0 }) }
    val view = LocalView.current
    Text("Sudoku", color = theme.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
    Text("Use 1–${board.size} once in each row, column and box.", color = theme.muted, fontSize = 12.sp)
    Text("${board.filled}/${board.blanks} filled", color = theme.muted, fontSize = 13.sp, modifier = Modifier.testTag("sudoku-progress"))
    Column(Modifier.widthIn(max = 360.dp).fillMaxWidth().border(1.5.dp, theme.text.copy(alpha = .6f)).testTag("sudoku-board")) {
        repeat(board.size) { row ->
            Row {
                repeat(board.size) { col ->
                    val id = row * board.size + col; val given = board.givens[id] != 0; val selected = cell == id; val conflict = board.conflict(id)
                    Box(Modifier.weight(1f).aspectRatio(1f).background(when { selected -> theme.accent2.copy(alpha = .2f); given -> theme.text.copy(alpha = .05f); else -> theme.field })
                        .drawBehind {
                            val thin = .5.dp.toPx(); val strong = 1.5.dp.toPx(); val color = theme.text.copy(alpha = .45f)
                            drawLine(color, Offset.Zero, Offset(size.width, 0f), if (row % 2 == 0) strong else thin)
                            drawLine(color, Offset.Zero, Offset(0f, size.height), if (col % board.boxColumns == 0) strong else thin)
                        }.clickable(enabled = !given, role = Role.Button) { haptic(view); cell = id }
                        .semantics { this.selected = selected; contentDescription = "Row ${row + 1}, column ${col + 1}, ${if (board.values[id] == 0) "empty" else board.values[id].toString()}${if (given) ", fixed" else ""}${if (conflict) ", conflict" else ""}" }
                        .testTag("sudoku-cell-$id"), contentAlignment = Alignment.Center) {
                        Text(if (board.values[id] == 0) "" else "${board.values[id]}", color = if (conflict) androidx.compose.ui.graphics.Color(0xffff6b7a) else if (given) theme.text else theme.accent,
                            fontSize = 24.sp, fontWeight = if (given) FontWeight.SemiBold else FontWeight.Normal)
                    }
                }
            }
        }
    }
    Row(Modifier.widthIn(max = 360.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        (1..board.size).forEach { digit ->
            Box(Modifier.weight(1f).height(50.dp).clip(RoundedCornerShape(10.dp)).background(theme.card).border(1.dp, theme.border, RoundedCornerShape(10.dp))
                .clickable(role = Role.Button) { haptic(view); action(cell, digit) }.semantics { contentDescription = "Enter $digit" }.testTag("sudoku-digit-$digit"), contentAlignment = Alignment.Center) {
                Text("$digit", color = theme.text, fontSize = 23.sp)
            }
        }
    }
    Chip("Erase", theme, Modifier.testTag("sudoku-erase")) { haptic(view); action(cell, 0) }
}
