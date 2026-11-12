package online.reeeserve.lunkalarm.core

import kotlin.random.Random

/** Small, deduction-solvable boards. The opening is already safe; flags are reversible. */
data class MineBoard(val size: Int, val mines: Set<Int>, val revealed: Set<Int>, val flags: Set<Int> = emptySet()) {
    val cells get() = 0 until size * size
    val complete get() = revealed.size == size * size - mines.size && flags == mines
    fun neighbors(cell: Int): List<Int> = cells.filter { it != cell && kotlin.math.abs(it / size - cell / size) <= 1 && kotlin.math.abs(it % size - cell % size) <= 1 }
    fun number(cell: Int) = neighbors(cell).count { it in mines }
    fun reveal(cell: Int): MineBoard {
        if (cell !in cells || cell in flags || cell in mines) return this
        val seen = revealed.toMutableSet(); val pending = ArrayDeque<Int>(); pending.add(cell)
        while (pending.isNotEmpty()) {
            val next = pending.removeFirst()
            if (next in flags || next in mines || !seen.add(next)) continue
            if (number(next) == 0) pending.addAll(neighbors(next).filterNot { it in seen })
        }
        return copy(revealed = seen)
    }
    fun flag(cell: Int) = if (cell !in cells || cell in revealed) this else copy(flags = if (cell in flags) flags - cell else flags + cell)
    /** Only visible clues and the known mine count are used, never hidden answers. */
    fun deductions(): Pair<Set<Int>, Set<Int>> {
        val safe = mutableSetOf<Int>(); val marked = mutableSetOf<Int>()
        val hidden = cells.filterNot { it in revealed || it in flags }.toSet()
        val left = mines.size - flags.size
        if (left == 0) safe += hidden
        if (left == hidden.size) marked += hidden
        for (cell in revealed) {
            val near = neighbors(cell); val unknown = near.filter { it in hidden }
            val remaining = number(cell) - near.count { it in flags }
            if (remaining == 0) safe += unknown
            if (remaining == unknown.size) marked += unknown
        }
        return safe to marked
    }
    fun solvableWithoutGuessing(): Boolean {
        var board = copy(flags = emptySet())
        repeat(size * size) {
            if (board.complete) return true
            val (safe, marked) = board.deductions()
            val next = safe.fold(board.copy(flags = board.flags + marked)) { b, c -> b.reveal(c) }
            if (next == board) return false
            board = next
        }
        return board.complete
    }
    fun validate() {
        require(size in listOf(3, 4, 5, 7, 9) && mines.size == mapOf(3 to 1, 4 to 2, 5 to 4, 7 to 8, 9 to 14)[size])
        require((mines + revealed + flags).all { it in cells } && revealed.intersect(mines + flags).isEmpty())
    }
    companion object {
        fun create(difficulty: Int, seed: Long): MineBoard {
            require(difficulty in 0..2)
            val size = listOf(5, 7, 9)[difficulty]; val count = listOf(4, 8, 14)[difficulty]; val random = Random(seed)
            repeat(300) {
                val board = MineBoard(size, (0 until size * size).shuffled(random).take(count).toSet(), emptySet())
                val start = board.cells.filter { it !in board.mines && board.number(it) == 0 }.randomOrNull(random) ?: return@repeat
                val opened = board.reveal(start)
                if (opened.solvableWithoutGuessing()) return opened
            }
            // A corner cluster always has a safe flood opening and deducible remaining mines.
            return MineBoard(size, (0 until count).toSet(), emptySet()).reveal(size * size - 1).also { check(it.solvableWithoutGuessing()) }
        }
    }
}

/** Every generated 4x4 / 6x6 puzzle has exactly one solution. */
data class SudokuBoard(val size: Int, val givens: List<Int>, val solution: List<Int>, val values: List<Int>) {
    val boxRows get() = 2
    val boxColumns get() = size / 2
    val complete get() = values == solution
    val blanks get() = givens.count { it == 0 }
    val filled get() = values.indices.count { givens[it] == 0 && values[it] != 0 }
    fun enter(cell: Int, digit: Int): SudokuBoard = if (cell !in values.indices || givens[cell] != 0 || digit !in 0..size) this
        else copy(values = values.toMutableList().apply { this[cell] = digit })
    fun conflict(cell: Int): Boolean {
        val v = values[cell]
        return v != 0 && peers(size, cell).any { values[it] == v }
    }
    fun validate() {
        require(size in listOf(4, 6) && listOf(givens, solution, values).all { it.size == size * size })
        require(givens.all { it in 0..size } && solution.all { it in 1..size } && values.all { it in 0..size })
        require(values.indices.all { (givens[it] == 0 || (givens[it] == solution[it] && values[it] == givens[it])) && peers(size, it).none { p -> solution[p] == solution[it] } })
    }
    companion object {
        fun peers(size: Int, cell: Int): List<Int> = (0 until size * size).filter { p -> p != cell &&
            (p / size == cell / size || p % size == cell % size || (p / size / 2 == cell / size / 2 && p % size / (size / 2) == cell % size / (size / 2))) }
        fun solutionCount(size: Int, input: List<Int>, limit: Int = 2): Int {
            val grid = input.toMutableList(); var found = 0
            fun solve() {
                if (found >= limit) return
                val empty = grid.indices.filter { grid[it] == 0 }
                if (empty.isEmpty()) { found++; return }
                val choices = empty.map { c -> c to (1..size).filter { n -> peers(size, c).none { grid[it] == n } } }
                val (cell, digits) = choices.minBy { it.second.size }
                for (digit in digits) { grid[cell] = digit; solve(); if (found >= limit) break }
                grid[cell] = 0
            }
            if (input.indices.any { input[it] != 0 && peers(size, it).any { p -> input[p] == input[it] } }) return 0
            solve(); return found
        }
        fun create(difficulty: Int, seed: Long): SudokuBoard {
            require(difficulty in 0..3)
            val size = if (difficulty < 2) 4 else 6; val random = Random(seed)
            val rows = (0 until size / 2).shuffled(random).flatMap { band -> (0..1).shuffled(random).map { band * 2 + it } }
            val columns = (0..1).shuffled(random).flatMap { stack -> (0 until size / 2).shuffled(random).map { stack * (size / 2) + it } }
            val digits = (1..size).shuffled(random)
            val solution = rows.flatMap { r -> columns.map { c -> digits[(r * (size / 2) + r / 2 + c) % size] } }
            val clues = solution.toMutableList(); val target = listOf(6, 10, 14, 22)[difficulty]; var removed = 0
            for (cell in clues.indices.shuffled(random)) {
                val old = clues[cell]; clues[cell] = 0
                if (solutionCount(size, clues) != 1) clues[cell] = old else removed++
                if (removed == target) break
            }
            return SudokuBoard(size, clues.toList(), solution, clues.toList()).also { it.validate() }
        }
    }
}
