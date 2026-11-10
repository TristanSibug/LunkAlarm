package online.reeeserve.lunkalarm.core

import kotlin.math.ceil
import kotlin.random.Random

enum class AnswerResult { INCOMPLETE, INCORRECT, CORRECT, TIMED_OUT }
data class Submission(val challenge: WakeChallenge, val result: AnswerResult)
data class WakeChallenge(
    val typing: Boolean, val total: Int, val codeLength: Int, val typingSeconds: Int, val mathSeconds: Int,
    val code: String, val typingPending: Boolean, val remaining: Int,
    val left: Int, val right: Int, val deadline: Long = 0, val resets: Int = 0,
    val puzzle: Boolean = false, val puzzlePieces: Int = 8, val puzzleSeconds: Int = 30,
    val puzzleSeed: Long = 0, val placedPieces: Set<Int> = emptySet(),
    val mines: Boolean = false, val mineDifficulty: Int = 0, val mineSeconds: Int = 30, val mineBoard: MineBoard? = null,
    val sudoku: Boolean = false, val sudokuDifficulty: Int = 0, val sudokuSeconds: Int = 60, val sudokuBoard: SudokuBoard? = null
) {
    val puzzlePending get() = puzzle && placedPieces.size < puzzlePieces
    val minesPending get() = mines && mineBoard?.complete != true
    val sudokuPending get() = sudoku && sudokuBoard?.complete != true
    val complete get() = !typingPending && remaining == 0 && !puzzlePending && !minesPending && !sudokuPending
    val answered get() = total - remaining
    fun secondsLeft(now: Long): Int = if (deadline == 0L) 0 else ceil((deadline - now).coerceAtLeast(0) / 1000.0).toInt()
    fun start(now: Long): WakeChallenge = if (deadline == 0L && !complete) renew(now) else this
    private fun renew(now: Long) = copy(deadline = if (complete) 0 else now + (if (typingPending) typingSeconds else if (remaining > 0) mathSeconds else if (puzzlePending) puzzleSeconds else if (minesPending) mineSeconds else sudokuSeconds) * 1000L)
    fun expire(now: Long): WakeChallenge {
        if (complete || deadline == 0L || now < deadline) return this
        return restart(now)
    }
    private fun restart(now: Long): WakeChallenge = create(AlarmDraft(typing = typing, mathCount = total, codeLength = codeLength,
            typingSeconds = typingSeconds, mathSeconds = mathSeconds, puzzle = puzzle, puzzlePieces = puzzlePieces, puzzleSeconds = puzzleSeconds,
            mines = mines, mineDifficulty = mineDifficulty, mineSeconds = mineSeconds,
            sudoku = sudoku, sudokuDifficulty = sudokuDifficulty, sudokuSeconds = sudokuSeconds)).copy(resets = resets + 1).renew(now)
    fun submitCode(text: String, now: Long): Submission {
        val current = expire(now)
        if (current.resets != resets) return Submission(current, AnswerResult.TIMED_OUT)
        if (deadline == 0L || !typingPending || text != code) return Submission(this, AnswerResult.INCORRECT)
        return Submission(copy(typingPending = false).renew(now), AnswerResult.CORRECT)
    }
    fun submitDigits(text: String, now: Long): Submission {
        val current = expire(now)
        if (current.resets != resets) return Submission(current, AnswerResult.TIMED_OUT)
        if (deadline == 0L || typingPending || remaining == 0 || text.length < (left + right).toString().length)
            return Submission(this, AnswerResult.INCOMPLETE)
        if (text != (left + right).toString()) return Submission(this, AnswerResult.INCORRECT)
        return Submission(copy(remaining = remaining - 1, left = Random.nextInt(1, 21), right = Random.nextInt(1, 21)).renew(now), AnswerResult.CORRECT)
    }
    fun placePiece(piece: Int, now: Long): Submission {
        val current = expire(now)
        if (current.resets != resets) return Submission(current, AnswerResult.TIMED_OUT)
        if (deadline == 0L || typingPending || remaining > 0 || !puzzlePending || piece !in 0 until puzzlePieces || piece in placedPieces)
            return Submission(this, AnswerResult.INCOMPLETE)
        val next = copy(placedPieces = placedPieces + piece)
        // Placing a piece never extends the puzzle's single deadline.
        return Submission(if (!next.puzzlePending) next.renew(now) else next, AnswerResult.CORRECT)
    }
    fun mineAction(cell: Int, flag: Boolean, now: Long): Submission {
        val current = expire(now)
        if (current.resets != resets) return Submission(current, AnswerResult.TIMED_OUT)
        val board = mineBoard ?: return Submission(this, AnswerResult.INCOMPLETE)
        if (deadline == 0L || typingPending || remaining > 0 || puzzlePending || !minesPending || cell !in board.cells)
            return Submission(this, AnswerResult.INCOMPLETE)
        if (!flag && cell !in board.flags && cell in board.mines) return Submission(restart(now), AnswerResult.INCORRECT)
        val updated = if (flag) board.flag(cell) else board.reveal(cell)
        val next = copy(mineBoard = updated)
        return Submission(if (updated.complete) next.renew(now) else next, AnswerResult.CORRECT)
    }
    fun sudokuAction(cell: Int, digit: Int, now: Long): Submission {
        val current = expire(now)
        if (current.resets != resets) return Submission(current, AnswerResult.TIMED_OUT)
        val board = sudokuBoard ?: return Submission(this, AnswerResult.INCOMPLETE)
        if (deadline == 0L || typingPending || remaining > 0 || puzzlePending || minesPending || !sudokuPending)
            return Submission(this, AnswerResult.INCOMPLETE)
        val updated = board.enter(cell, digit); val next = copy(sudokuBoard = updated)
        return Submission(if (updated.complete) next.renew(now) else next, AnswerResult.CORRECT)
    }
    companion object {
        fun create(draft: AlarmDraft): WakeChallenge {
            val alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789"
            return WakeChallenge(draft.typing, draft.mathCount, draft.codeLength, draft.typingSeconds, draft.mathSeconds,
                (1..draft.codeLength).map { alphabet.random() }.joinToString(""), draft.typing, draft.mathCount,
                Random.nextInt(1, 21), Random.nextInt(1, 21), puzzle = draft.puzzle, puzzlePieces = draft.puzzlePieces,
                puzzleSeconds = draft.puzzleSeconds, puzzleSeed = Random.nextLong(),
                mines = draft.mines, mineDifficulty = draft.mineDifficulty, mineSeconds = draft.mineSeconds,
                mineBoard = if (draft.mines) MineBoard.create(draft.mineDifficulty, Random.nextLong()) else null,
                sudoku = draft.sudoku, sudokuDifficulty = draft.sudokuDifficulty, sudokuSeconds = draft.sudokuSeconds,
                sudokuBoard = if (draft.sudoku) SudokuBoard.create(draft.sudokuDifficulty, Random.nextLong()) else null)
        }
    }
}
