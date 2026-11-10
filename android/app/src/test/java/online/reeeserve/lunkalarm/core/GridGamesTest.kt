package online.reeeserve.lunkalarm.core

import online.reeeserve.lunkalarm.AlarmJson
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class GridGamesTest {
    @Test fun mineBoardsAlwaysHaveFiniteTargetsAndCanBeSolvedFromVisibleClues() {
        for (difficulty in 0..2) for (seed in 0L..150L) {
            var b = MineBoard.create(difficulty, seed)
            assertEquals(difficulty + 3, b.size); b.validate()
            assertTrue(b.solvableWithoutGuessing()); assertFalse(b.complete)
            assertTrue(b.revealed.isNotEmpty()); assertTrue(b.revealed.intersect(b.mines).isEmpty())
            repeat(25) {
                val (safe, flags) = b.deductions()
                b = safe.fold(b.copy(flags = b.flags + flags)) { board, cell -> board.reveal(cell) }
            }
            assertTrue(b.complete)
        }
    }
    @Test fun sudokuBoardsHaveValidUniqueSolutionsAtEveryDifficulty() {
        for (difficulty in 0..3) for (seed in 0L..35L) {
            val b = SudokuBoard.create(difficulty, seed); b.validate()
            assertEquals(if (difficulty < 2) 4 else 6, b.size)
            assertEquals(1, SudokuBoard.solutionCount(b.size, b.givens))
            assertTrue(b.blanks > 0); assertFalse(b.complete)
            assertEquals(b, SudokuBoard.create(difficulty, seed))
            val cell = b.givens.indexOfFirst { it == 0 }
            val edited = b.enter(cell, b.solution[cell]); assertEquals(b.solution[cell], edited.values[cell])
            assertEquals(b, edited.enter(cell, 0))
            val given = b.givens.indexOfFirst { it != 0 }
            assertEquals(b, b.enter(given, 0))
        }
    }
    @Test fun allFiveTestsRunInOrderAndGameActionsNeverExtendTheirDeadline() {
        var c = WakeChallenge.create(AlarmDraft(typing = true, mathCount = 1, puzzle = true, mines = true, sudoku = true, mineSeconds = 40, sudokuSeconds = 120)).start(1000)
        assertEquals(AnswerResult.INCOMPLETE, c.mineAction(0, true, 1100).result)
        assertEquals(AnswerResult.INCOMPLETE, c.sudokuAction(0, 1, 1100).result)
        c = c.submitCode(c.code, 1200).challenge
        c = c.submitDigits((c.left + c.right).toString(), 1300).challenge
        repeat(8) { c = c.placePiece(it, 1400).challenge }
        assertTrue(c.minesPending); assertEquals(41400L, c.deadline)
        for (cell in c.mineBoard!!.cells) {
            val b = c.mineBoard!!
            c = c.mineAction(cell, cell in b.mines, 1500).challenge
            if (c.minesPending) assertEquals(41400L, c.deadline)
        }
        assertFalse(c.minesPending); assertTrue(c.sudokuPending); assertEquals(121500L, c.deadline)
        val b = c.sudokuBoard!!
        for (cell in b.values.indices.filter { b.givens[it] == 0 }) {
            c = c.sudokuAction(cell, b.solution[cell], 1600).challenge
            if (!c.complete) assertEquals(121500L, c.deadline)
        }
        assertTrue(c.complete); assertEquals(0L, c.deadline)
    }
    @Test fun mineMistakesAndGameTimeoutsRestartTheWholeSequence() {
        val draft = AlarmDraft(typing = true, mines = true, sudoku = true, mineSeconds = 15)
        val typing = WakeChallenge.create(draft).start(1000)
        val mine = typing.submitCode(typing.code, 2000).challenge
        val hit = mine.mineAction(mine.mineBoard!!.mines.first(), false, 2100)
        assertEquals(AnswerResult.INCORRECT, hit.result); assertTrue(hit.challenge.typingPending); assertEquals(1, hit.challenge.resets)
        assertEquals(AnswerResult.TIMED_OUT, mine.mineAction(0, true, 17000).result)
        var sudoku = WakeChallenge.create(AlarmDraft(sudoku = true, sudokuSeconds = 30)).start(1000)
        val cell = sudoku.sudokuBoard!!.givens.indexOfFirst { it == 0 }
        sudoku = sudoku.sudokuAction(cell, sudoku.sudokuBoard!!.solution[cell], 2000).challenge
        val expired = sudoku.sudokuAction(cell, 0, 31000)
        assertEquals(AnswerResult.TIMED_OUT, expired.result); assertEquals(1, expired.challenge.resets)
        assertEquals(0, expired.challenge.sudokuBoard!!.filled)
    }
    @Test fun gamesAndPartialProgressSurviveStorageAndDuplication() {
        val d = AlarmDraft(mines = true, mineDifficulty = 2, mineSeconds = 40, sudoku = true, sudokuDifficulty = 3, sudokuSeconds = 120)
        val a = AlarmRecord.create(d, 100000, 1000, 1).copy(active = true)
        var c = WakeChallenge.create(d).start(1000)
        c = c.mineAction(c.mineBoard!!.mines.first(), true, 2000).challenge
        val state = AppState(draft = d, alarms = listOf(a), session = AlarmSession(a.id, c, sound = false, opened = true))
        assertEquals(state, AlarmJson.decode(AlarmJson.encode(state)))
        val copy = a.duplicate(200000, 2000, 1)
        assertEquals(a.draft, copy.draft); assertNotEquals(a.id, copy.id)
    }
    @Test fun legacyOddPieceCountsMigrateAndNewSettingsHaveSafeDefaults() {
        val old = JSONObject(AlarmJson.encode(AppState()))
        old.getJSONObject("draft").put("puzzlePieces", 7)
        for (field in listOf("mines", "mineDifficulty", "mineSeconds", "sudoku", "sudokuDifficulty", "sudokuSeconds")) old.getJSONObject("draft").remove(field)
        val restored = AlarmJson.decode(old.toString()).draft
        assertEquals(6, restored.puzzlePieces); assertFalse(restored.mines); assertFalse(restored.sudoku)
        for (count in listOf(7, 9)) assertThrows(IllegalArgumentException::class.java) { AlarmDraft(puzzlePieces = count).validate() }
        for (timer in listOf(30, 60, 90, 120)) AlarmDraft(sudokuSeconds = timer).validate()
        assertThrows(IllegalArgumentException::class.java) { AlarmDraft(sudokuSeconds = 40).validate() }
    }
}
