package online.reeeserve.lunkalarm.core

import kotlin.random.Random

/** Unit-grid outlines, clockwise, with shared seams generated from one seed. */
data class PuzzlePoint(val x: Int, val y: Int)
data class PuzzleEdge(val from: PuzzlePoint, val to: PuzzlePoint, val tab: Float, val center: Float)
data class PuzzlePiece(val id: Int, val edges: List<PuzzleEdge>) {
    val x get() = edges.minOf { minOf(it.from.x, it.to.x) }
    val y get() = edges.minOf { minOf(it.from.y, it.to.y) }
}
data class Jigsaw(val columns: Int, val pieces: List<PuzzlePiece>, val order: List<Int>) {
    companion object {
        fun create(count: Int, seed: Long): Jigsaw {
            require(count in 6..10)
            val columns = (count + 1) / 2
            val cells = List(2) { y -> List(columns) { x ->
                if (count % 2 == 1 && x == columns - 1) count - 1 else y * (if (count % 2 == 1) columns - 1 else columns) + x
            } }
            fun owner(x: Int, y: Int) = cells.getOrNull(y)?.getOrNull(x)
            val random = Random(seed)
            val seams = mutableMapOf<Pair<PuzzlePoint, PuzzlePoint>, Pair<Float, Float>>()
            val outlines = (0 until count).map { id ->
                val edges = mutableListOf<PuzzleEdge>()
                for (y in 0..1) for (x in 0 until columns) if (owner(x, y) == id) {
                    val corners = listOf(PuzzlePoint(x, y), PuzzlePoint(x + 1, y), PuzzlePoint(x + 1, y + 1), PuzzlePoint(x, y + 1))
                    val neighbors = listOf(owner(x, y - 1), owner(x + 1, y), owner(x, y + 1), owner(x - 1, y))
                    corners.indices.forEach { side ->
                        if (neighbors[side] != id) {
                            val a = corners[side]; val b = corners[(side + 1) % 4]
                            val forward = a.x < b.x || a.y < b.y
                            val key = if (forward) a to b else b to a
                            val seam = if (neighbors[side] == null) 0f to .5f else seams.getOrPut(key) {
                                (if (random.nextBoolean()) 1 else -1) * random.nextDouble(.16, .23).toFloat() to random.nextDouble(.43, .57).toFloat()
                            }
                            edges += PuzzleEdge(a, b, if (forward) seam.first else -seam.first, if (forward) seam.second else 1 - seam.second)
                        }
                    }
                }
                val ordered = mutableListOf(edges.removeAt(0))
                while (edges.isNotEmpty()) ordered += edges.removeAt(edges.indexOfFirst { it.from == ordered.last().to })
                PuzzlePiece(id, ordered)
            }
            return Jigsaw(columns, outlines, (0 until count).shuffled(random))
        }
    }
}
