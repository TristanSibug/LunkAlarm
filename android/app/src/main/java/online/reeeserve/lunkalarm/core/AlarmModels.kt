package online.reeeserve.lunkalarm.core

import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlin.math.ceil

const val MAX_DURATION_SECONDS = 99 * 3600 + 59 * 60 + 59

object WakeTimers {
    val math = listOf(5, 10, 15)
    val typing = listOf(15, 20, 25, 30)
    val puzzle = listOf(15, 20, 25, 30, 35, 40)
    val pieces = listOf(6, 8, 10)
    val mines = puzzle
    val sudoku = listOf(30, 60, 90, 120)
    fun nearest(value: Int, choices: List<Int>): Int {
        require(value in choices.first()..choices.last()) { "Invalid wake-up test timer." }
        return choices.minBy { kotlin.math.abs(it - value) }
    }
}

data class AlarmDraft(
    val timer: Boolean = false, val name: String = "", val hour: Int = 7, val minute: Int = 0,
    val seconds: Int = 1800, val days: Set<Int> = (1..7).toSet(), val tone: String = "classic-beep",
    val volume: Float = 1f, val gradual: Boolean = false, val typing: Boolean = false,
    val codeLength: Int = 8, val typingSeconds: Int = 30, val mathCount: Int = 0, val mathSeconds: Int = 10,
    val nativeMathKeyboard: Boolean = false, val puzzle: Boolean = false, val puzzlePieces: Int = 8, val puzzleSeconds: Int = 30,
    val mines: Boolean = false, val mineDifficulty: Int = 0, val mineSeconds: Int = 30,
    val sudoku: Boolean = false, val sudokuDifficulty: Int = 0, val sudokuSeconds: Int = 60
) {
    fun validate() {
        require(hour in 0..23 && minute in 0..59) { "Choose a valid time." }
        require(!timer || seconds in 1..MAX_DURATION_SECONDS) { "Choose a duration from 1 second to 99 hours, 59 minutes, 59 seconds." }
        require(days.all { it in 1..7 } && volume in .1f..1f && mathCount in 0..8)
        require(puzzlePieces in WakeTimers.pieces && puzzleSeconds in WakeTimers.puzzle)
        require(mineDifficulty in 0..2 && mineSeconds in WakeTimers.mines && sudokuDifficulty in 0..3 && sudokuSeconds in WakeTimers.sudoku)
        require(codeLength in 4..10 && typingSeconds in WakeTimers.typing && mathSeconds in WakeTimers.math)
    }
}

data class AlarmRecord(
    val id: String = UUID.randomUUID().toString(), val draft: AlarmDraft,
    val target: Long, val elapsedTarget: Long = 0, val boot: Int = -1,
    val enabled: Boolean = true, val active: Boolean = false, val error: String? = null
) {
    val hasTests get() = draft.typing || draft.mathCount > 0 || draft.puzzle || draft.mines || draft.sudoku
    val label get() = draft.name.ifBlank { if (draft.timer) "Timer" else "Alarm" }
    fun remaining(now: Long, elapsed: Long, bootCount: Int): Long =
        ((if (boot == bootCount && elapsedTarget > 0) elapsedTarget - elapsed else target - now)).coerceAtLeast(0)
    fun duplicate(now: Long, elapsed: Long, bootCount: Int, zone: ZoneId = ZoneId.systemDefault()): AlarmRecord =
        create(draft, now, elapsed, bootCount, zone).copy(enabled = enabled)
    companion object {
        fun create(draft: AlarmDraft, now: Long, elapsed: Long, boot: Int, zone: ZoneId = ZoneId.systemDefault()): AlarmRecord {
            draft.validate()
            return AlarmRecord(draft = draft, target = if (draft.timer) now + draft.seconds * 1000L
                else AlarmTime.next(draft.hour, draft.minute, draft.days, now, zone),
                elapsedTarget = if (draft.timer) elapsed + draft.seconds * 1000L else 0, boot = boot)
        }
    }
}

object AlarmTime {
    fun next(hour: Int, minute: Int, days: Set<Int>, now: Long, zone: ZoneId = ZoneId.systemDefault()): Long {
        require(hour in 0..23 && minute in 0..59 && days.all { it in 1..7 })
        val date = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        return (0L..7L).map { date.plusDays(it) }.filter { days.isEmpty() || (it.dayOfWeek.value % 7 + 1) in days }
            .map { it.atTime(hour, minute).atZone(zone).toInstant().toEpochMilli() }.first { it > now }
    }
    fun daysLabel(days: Set<Int>): String = when (days) {
        (1..7).toSet() -> "Daily"
        emptySet<Int>() -> "Once"
        setOf(2, 3, 4, 5, 6) -> "Weekdays"
        setOf(1, 7) -> "Weekends"
        else -> days.sorted().joinToString(" · ") { listOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")[it - 1] }
    }
    fun duration(ms: Long): String {
        val seconds = ceil(ms.coerceAtLeast(0) / 1000.0).toLong()
        return if (seconds >= 3600) "%d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60)
        else "%d:%02d".format(seconds / 60, seconds % 60)
    }
    fun gain(level: Float, elapsed: Long, gradual: Boolean): Float = level.coerceIn(0f, 1f) *
        (if (gradual) (elapsed / 10000f).coerceIn(0f, 1f) else 1f)
}

data class ImportedSound(val id: String, val name: String, val filename: String)
data class AppState(
    val theme: String = "sunrise", val use24Hour: Boolean = false, val draft: AlarmDraft = AlarmDraft(),
    val alarms: List<AlarmRecord> = emptyList(), val sounds: List<ImportedSound> = emptyList(), val session: AlarmSession? = null
)
data class AlarmSession(val owner: String, val challenge: WakeChallenge, val sound: Boolean = true, val opened: Boolean = false, val boot: Int = -1)

object Tones {
    val all = listOf("classic-beep" to "Classic Beep", "digital-watch" to "Digital Watch", "soft-chime" to "Soft Chime",
        "xylophone" to "Xylophone", "sonar-ping" to "Sonar Ping", "church-bell" to "Church Bell", "rise-and-shine" to "Rise & Shine",
        "retro-arcade" to "Retro Arcade", "wind-bells" to "Wind Bells", "siren" to "Siren")
}
