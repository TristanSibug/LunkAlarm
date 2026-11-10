package online.reeeserve.lunkalarm

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import online.reeeserve.lunkalarm.core.*
import kotlin.math.abs
import kotlin.math.min

/** All pieces have the same theme fill; only their interlocking silhouettes identify them. */
@Composable fun JigsawView(challenge: WakeChallenge, theme: LunkTheme, place: (Int) -> Unit) {
    val puzzle = remember(challenge.puzzleSeed, challenge.puzzlePieces) { Jigsaw.create(challenge.puzzlePieces, challenge.puzzleSeed) }
    var selected by remember(challenge.puzzleSeed) { mutableStateOf<Int?>(null) }
    var dragged by remember(challenge.puzzleSeed) { mutableStateOf<Int?>(null) }
    var dragPosition by remember { mutableStateOf(Offset.Zero) }
    var grab by remember { mutableStateOf(Offset.Zero) }
    var origin by remember { mutableStateOf(Offset.Zero) }
    var boardOrigin by remember { mutableStateOf(Offset.Zero) }
    var boardWidth by remember { mutableFloatStateOf(1f) }
    val latestPlace by rememberUpdatedState(place)
    val view = LocalView.current
    val cellW = boardWidth / puzzle.columns; val cellH = boardWidth * .58f / 2
    val paths = remember(puzzle, cellW, cellH) { puzzle.pieces.map { piecePath(it, cellW, cellH) } }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
        Text("Fit the pieces", fontSize = 20.sp)
        Text("${challenge.placedPieces.size} / ${challenge.puzzlePieces} placed · Drag pieces into the outline, or tap a piece then its space.", color = theme.muted, fontSize = 12.sp)
        Box(Modifier.fillMaxWidth().onGloballyPositioned { origin = it.positionInRoot() }) {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Box(Modifier.fillMaxWidth().aspectRatio(1f / .58f).background(theme.field, RoundedCornerShape(12.dp))
                    .onGloballyPositioned { boardOrigin = it.positionInRoot(); boardWidth = it.size.width.toFloat() }.testTag("jigsaw-board")) {
                    Canvas(Modifier.matchParentSize()) {
                        puzzle.pieces.forEach { piece ->
                            if (piece.id in challenge.placedPieces) drawPath(paths[piece.id], theme.accent)
                            drawPath(paths[piece.id], theme.text.copy(alpha = .55f), style = Stroke(1.5.dp.toPx()))
                        }
                    }
                    // Equivalent tap controls also support TalkBack and switch access.
                    puzzle.pieces.filter { it.id !in challenge.placedPieces }.forEach { piece ->
                        val height = piece.edges.maxOf { maxOf(it.from.y, it.to.y) } - piece.y
                        Box(Modifier.fillMaxWidth(1f / puzzle.columns).fillMaxHeight(height / 2f)
                            .offset { androidx.compose.ui.unit.IntOffset((piece.x * cellW).toInt(), (piece.y * cellH).toInt()) }
                            .testTag("puzzle-slot-${piece.id}").semantics { contentDescription = "Puzzle space ${piece.id + 1}" }
                            .clickable { if (selected == piece.id) { latestPlace(piece.id); selected = null; haptic(view) } })
                    }
                }
                Column(Modifier.fillMaxWidth().background(theme.card, RoundedCornerShape(14.dp)).padding(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    puzzle.order.chunked(5).forEach { row ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            row.forEach { id ->
                                val piece = puzzle.pieces[id]
                                var trayOrigin by remember { mutableStateOf(Offset.Zero) }
                                val scale = .43f
                                Box(Modifier.weight(1f).height(100.dp).onGloballyPositioned { trayOrigin = it.positionInRoot() }
                                    .border(if (selected == id) 2.dp else 0.dp, if (selected == id) theme.accent else androidx.compose.ui.graphics.Color.Transparent, RoundedCornerShape(8.dp))
                                    .testTag("puzzle-piece-$id").semantics { contentDescription = if (id in challenge.placedPieces) "Placed piece" else "Jigsaw piece ${id + 1}"; this.selected = selected == id }
                                    .clickable(enabled = id !in challenge.placedPieces) { selected = id; haptic(view) }
                                    .pointerInput(challenge.puzzleSeed, challenge.placedPieces, cellW, cellH) {
                                        if (id !in challenge.placedPieces) detectDragGestures(onDragStart = { point ->
                                            dragged = id; selected = id; dragPosition = trayOrigin + point
                                            grab = Offset((point.x - 8.dp.toPx()) / scale - cellW * .24f, (point.y - 8.dp.toPx()) / scale - cellH * .24f)
                                            haptic(view)
                                        }, onDrag = { event, delta -> event.consume(); dragPosition += delta }, onDragCancel = { dragged = null }, onDragEnd = {
                                            val target = boardOrigin + Offset(piece.x * cellW, piece.y * cellH)
                                            val dropped = dragPosition - grab
                                            val tolerance = min(cellW, cellH) * .4f
                                            if (abs(dropped.x - target.x) < tolerance && abs(dropped.y - target.y) < tolerance) {
                                                latestPlace(id); selected = null; haptic(view)
                                            }
                                            dragged = null
                                        })
                                    }) {
                                    if (id !in challenge.placedPieces && dragged != id) Canvas(Modifier.fillMaxSize().padding(8.dp)) {
                                        withTransformForPiece(piece, cellW, cellH, scale) {
                                            drawPath(paths[id], theme.accent)
                                            drawPath(paths[id], theme.text.copy(alpha = .8f), style = Stroke(1.5.dp.toPx() / scale))
                                        }
                                    }
                                }
                            }
                            repeat(5 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
            dragged?.let { id ->
                Canvas(Modifier.matchParentSize()) {
                    val piece = puzzle.pieces[id]
                    val at = dragPosition - grab - origin
                    translate(at.x - piece.x * cellW, at.y - piece.y * cellH) {
                        drawPath(paths[id], theme.accent)
                        drawPath(paths[id], theme.text, style = Stroke(2.dp.toPx()))
                    }
                }
            }
        }
    }
}
private inline fun androidx.compose.ui.graphics.drawscope.DrawScope.withTransformForPiece(piece: PuzzlePiece, w: Float, h: Float, scale: Float, draw: androidx.compose.ui.graphics.drawscope.DrawScope.() -> Unit) {
    withTransform({
        scale(scale, scale, Offset.Zero); translate(-piece.x * w + w * .24f, -piece.y * h + h * .24f)
    }, draw)
}
private fun piecePath(piece: PuzzlePiece, w: Float, h: Float) = Path().apply {
    moveTo(piece.edges.first().from.x * w, piece.edges.first().from.y * h)
    piece.edges.forEach { edge ->
        val a = Offset(edge.from.x * w, edge.from.y * h); val b = Offset(edge.to.x * w, edge.to.y * h)
        val v = b - a
        val normal = Offset(v.y, -v.x) / v.getDistance() * min(w, h) * edge.tab
        fun point(t: Float, bump: Float = 0f) = a + v * t + normal * bump
        fun line(t: Float) { val p = point(t); lineTo(p.x, p.y) }
        fun curve(t1: Float, n1: Float, t2: Float, n2: Float, t3: Float, n3: Float) {
            val c1 = point(t1, n1); val c2 = point(t2, n2); val end = point(t3, n3)
            cubicTo(c1.x, c1.y, c2.x, c2.y, end.x, end.y)
        }
        if (edge.tab != 0f) {
            val c = edge.center
            line(c - .12f)
            curve(c - .04f, 0f, c - .19f, 1f, c, 1f)
            curve(c + .19f, 1f, c + .04f, 0f, c + .12f, 0f)
        }
        lineTo(b.x, b.y)
    }
    close()
}
