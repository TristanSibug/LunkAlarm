package online.reeeserve.lunkalarm.core

import online.reeeserve.lunkalarm.AlarmJson
import org.junit.Assert.*
import org.junit.Test
import java.time.*

class AlarmCoreTest {
    private val utc = ZoneId.of("UTC")
    private fun millis(text: String) = Instant.parse(text).toEpochMilli()
    @Test fun onceSelectsNextDayWhenTimeAlreadyPassed() {
        val now = millis("2026-11-09T08:00:00Z")
        assertEquals(millis("2026-11-10T07:00:00Z"), AlarmTime.next(7, 0, emptySet(), now, utc))
    }
    @Test fun weekdaysAndDailyUseLocalWallClock() {
        val friday = millis("2026-11-06T08:00:00Z")
        assertEquals(millis("2026-11-09T07:00:00Z"), AlarmTime.next(7, 0, setOf(2,3,4,5,6), friday, utc))
        assertEquals(millis("2026-11-07T07:00:00Z"), AlarmTime.next(7, 0, (1..7).toSet(), friday, utc))
    }
    @Test fun springDSTGapAndAutumnOverlapDoNotDoubleSchedule() {
        val ny = ZoneId.of("America/New_York")
        val spring = AlarmTime.next(2, 30, emptySet(), millis("2026-03-08T06:00:00Z"), ny)
        assertEquals(3, Instant.ofEpochMilli(spring).atZone(ny).hour)
        val autumn = AlarmTime.next(1, 30, emptySet(), millis("2026-11-01T06:00:00Z"), ny)
        assertEquals(2, Instant.ofEpochMilli(autumn).atZone(ny).dayOfMonth)
    }
    @Test fun timerUsesElapsedTimeEvenIfUserChangesClock() {
        val alarm = AlarmRecord.create(AlarmDraft(timer = true, seconds = 30), 100000, 50000, 3)
        assertEquals(20000L, alarm.remaining(100000 + 3600000, 60000, 3))
        assertEquals(20000L, alarm.remaining(110000, 100, 4)) // New boot: fall back to persisted wall deadline.
    }
    @Test fun countdownBoundsAreValidated() {
        for (seconds in listOf(0, -1, MAX_DURATION_SECONDS + 1)) assertThrows(IllegalArgumentException::class.java) { AlarmDraft(timer = true, seconds = seconds).validate() }
        AlarmDraft(timer = true, seconds = MAX_DURATION_SECONDS).validate()
    }
    @Test fun exactDuplicatesHaveIndependentIdentityAndFreshTimerDeadlines() {
        val draft = AlarmDraft(timer = true, name = "", seconds = 1800, tone = "siren", volume = .6f, gradual = true, typing = true, mathCount = 7)
        val record = AlarmRecord.create(draft, 100000, 50000, 2).copy(enabled = false, active = true)
        val copy = record.duplicate(200000, 150000, 2)
        assertNotEquals(record.id, copy.id); assertEquals(record.draft, copy.draft)
        assertFalse(copy.enabled); assertFalse(copy.active); assertNull(copy.error)
        assertEquals(200000L + 1800000, copy.target)
    }
    @Test fun missionTimerWaitsUntilTestsAreOpened() {
        val c = WakeChallenge.create(AlarmDraft(typing = true, mathCount = 3))
        assertEquals(0L, c.deadline); assertEquals(c, c.expire(Long.MAX_VALUE))
        assertEquals(31000L, c.start(1000).deadline)
    }
    @Test fun incorrectMathClearsAtExpectedDigitsWithoutExtendingDeadline() {
        val c = WakeChallenge.create(AlarmDraft(mathCount = 3)).copy(left = 4, right = 7).start(1000)
        assertEquals(AnswerResult.INCOMPLETE, c.submitDigits("1", 2000).result)
        val wrong = c.submitDigits("99", 2000)
        assertEquals(AnswerResult.INCORRECT, wrong.result); assertEquals(c.deadline, wrong.challenge.deadline)
        val right = c.submitDigits("11", 3000)
        assertEquals(AnswerResult.CORRECT, right.result); assertEquals(2, right.challenge.remaining)
        assertEquals(13000L, right.challenge.deadline)
    }
    @Test fun typingIsCaseSensitiveAndCannotSkipToMath() {
        val c = WakeChallenge.create(AlarmDraft(typing = true, mathCount = 2)).copy(code = "AbCd2345").start(1000)
        assertEquals(AnswerResult.INCORRECT, c.submitCode("abcd2345", 2000).result)
        assertEquals(AnswerResult.INCOMPLETE, c.submitDigits((c.left + c.right).toString(), 2000).result)
        val next = c.submitCode("AbCd2345", 3000).challenge
        assertFalse(next.typingPending); assertEquals(13000L, next.deadline)
    }
    @Test fun timeoutResetsTypingAndAllMathProgress() {
        var c = WakeChallenge.create(AlarmDraft(typing = true, mathCount = 3, typingSeconds = 15, mathSeconds = 5)).start(1000)
        c = c.submitCode(c.code, 2000).challenge
        c = c.submitDigits((c.left + c.right).toString(), 3000).challenge
        assertEquals(1, c.answered)
        val expired = c.expire(8000)
        assertTrue(expired.typingPending); assertEquals(0, expired.answered); assertEquals(1, expired.resets)
        assertEquals(23000L, expired.deadline)
    }
    @Test fun lateCorrectAnswerCannotBeatDeadline() {
        val c = WakeChallenge.create(AlarmDraft(mathCount = 1, mathSeconds = 5)).start(1000)
        assertEquals(AnswerResult.TIMED_OUT, c.submitDigits((c.left + c.right).toString(), 6000).result)
    }
    @Test fun completionDoesNotExpireAndNoTestsStillNeedUserStop() {
        val empty = WakeChallenge.create(AlarmDraft())
        assertTrue(empty.complete); assertEquals(0L, empty.start(1000).deadline)
        val c = WakeChallenge.create(AlarmDraft(mathCount = 1)).start(1000)
        val complete = c.submitDigits((c.left + c.right).toString(), 2000).challenge
        assertTrue(complete.complete); assertEquals(0L, complete.deadline); assertEquals(complete, complete.expire(Long.MAX_VALUE))
    }
    @Test fun fadeStartsSilentAndHoldsChosenLevelAfterTenSeconds() {
        assertEquals(0f, AlarmTime.gain(.6f, 0, true), .001f)
        assertEquals(.3f, AlarmTime.gain(.6f, 5000, true), .001f)
        assertEquals(.6f, AlarmTime.gain(.6f, 60000, true), .001f)
    }
    @Test fun pendingChallengeAndAudioSettingsRoundTripAcrossProcessDeath() {
        val alarm = AlarmRecord.create(AlarmDraft(timer = true, typing = true, codeLength = 10, mathCount = 8, gradual = true, volume = .4f), 100000, 50000, 1).copy(active = true)
        val session = AlarmSession(alarm.id, WakeChallenge.create(alarm.draft).start(100000), sound = false, opened = true)
        val state = AppState(alarms = listOf(alarm), session = session)
        assertEquals(state, AlarmJson.decode(AlarmJson.encode(state)))
    }
    @Test fun corruptedOrUnsafeSavedDataIsRejected() {
        assertThrows(Exception::class.java) { AlarmJson.decode("broken") }
        assertThrows(Exception::class.java) { AlarmJson.decode(AlarmJson.encode(AppState()).replace("\"version\":1", "\"version\":2")) }
        val unsafe = AppState(sounds = listOf(ImportedSound("x", "bad", "../alarms.json")))
        assertThrows(Exception::class.java) { AlarmJson.decode(AlarmJson.encode(unsafe)) }
    }

    @Test fun puzzleCountsAreExactAndEveryInteriorSeamHasAComplement() {
        for (count in 6..10) for (seed in 0L..100L) {
            val p = Jigsaw.create(count, seed)
            assertEquals(count, p.pieces.size)
            assertEquals((0 until count).toSet(), p.order.toSet())
            val edges = p.pieces.flatMap { it.edges }
            p.pieces.forEach { piece ->
                assertEquals(piece.edges.first().from, piece.edges.last().to)
                piece.edges.zipWithNext().forEach { (a, b) -> assertEquals(a.to, b.from) }
            }
            edges.filter { it.tab != 0f }.forEach { edge ->
                val opposite = edges.single { it.from == edge.to && it.to == edge.from }
                assertEquals(-edge.tab, opposite.tab, .00001f)
                assertEquals(1f - edge.center, opposite.center, .00001f)
            }
            assertEquals(p, Jigsaw.create(count, seed))
            assertNotEquals(p, Jigsaw.create(count, seed + 1))
        }
    }
    @Test fun puzzleFollowsTypingAndMathAndKeepsOneDeadline() {
        var c = WakeChallenge.create(AlarmDraft(typing = true, mathCount = 1, puzzle = true, puzzlePieces = 7, puzzleSeconds = 20)).start(1000)
        assertEquals(AnswerResult.INCOMPLETE, c.placePiece(0, 1500).result)
        c = c.submitCode(c.code, 2000).challenge
        assertEquals(AnswerResult.INCOMPLETE, c.placePiece(0, 2500).result)
        c = c.submitDigits((c.left + c.right).toString(), 3000).challenge
        assertEquals(23000L, c.deadline)
        for (id in 0..5) {
            c = c.placePiece(id, 4000L + id).challenge
            assertEquals(23000L, c.deadline); assertFalse(c.complete)
        }
        assertEquals(AnswerResult.INCOMPLETE, c.placePiece(0, 5000).result)
        assertEquals(AnswerResult.INCOMPLETE, c.placePiece(8, 5000).result)
        c = c.placePiece(6, 6000).challenge
        assertTrue(c.complete); assertEquals(0L, c.deadline)
    }
    @Test fun puzzleTimeoutResetsWholeSequenceAndGeneratesNewShapes() {
        var c = WakeChallenge.create(AlarmDraft(typing = true, mathCount = 1, puzzle = true, puzzleSeconds = 15)).start(1000)
        c = c.submitCode(c.code, 2000).challenge
        c = c.submitDigits((c.left + c.right).toString(), 3000).challenge
        c = c.placePiece(0, 4000).challenge
        val expired = c.placePiece(1, 18000)
        assertEquals(AnswerResult.TIMED_OUT, expired.result)
        assertTrue(expired.challenge.typingPending)
        assertEquals(1, expired.challenge.remaining)
        assertTrue(expired.challenge.placedPieces.isEmpty())
        assertNotEquals(c.puzzleSeed, expired.challenge.puzzleSeed)
    }
    @Test fun puzzleAndKeyboardPersistWithProgressAndOldSavesGetDefaults() {
        val draft = AlarmDraft(puzzle = true, puzzlePieces = 10, puzzleSeconds = 40, nativeMathKeyboard = true)
        val record = AlarmRecord.create(draft, 100000, 50000, 1).copy(active = true)
        val c = WakeChallenge.create(draft).start(1000).placePiece(3, 2000).challenge
        val state = AppState(draft = draft, alarms = listOf(record), session = AlarmSession(record.id, c, opened = true))
        assertEquals(state, AlarmJson.decode(AlarmJson.encode(state)))
        val old = org.json.JSONObject(AlarmJson.encode(AppState()))
        old.getJSONObject("draft").apply { listOf("puzzle", "puzzlePieces", "puzzleSeconds", "nativeMathKeyboard").forEach { remove(it) } }
        assertEquals(AlarmDraft(), AlarmJson.decode(old.toString()).draft)
        assertThrows(IllegalArgumentException::class.java) { AlarmDraft(puzzlePieces = 5).validate() }
        assertThrows(IllegalArgumentException::class.java) { AlarmDraft(puzzleSeconds = 41).validate() }
    }

    @Test fun legacyTimersMoveToFiveSecondStepsWithoutLosingSavedAlarms() {
        val json = org.json.JSONObject(AlarmJson.encode(AppState()))
        json.getJSONObject("draft").put("mathSeconds", 12).put("typingSeconds", 23).put("puzzleSeconds", 37)
        val d = AlarmJson.decode(json.toString()).draft
        assertEquals(10, d.mathSeconds); assertEquals(25, d.typingSeconds); assertEquals(35, d.puzzleSeconds)
        for (seconds in WakeTimers.math) AlarmDraft(mathSeconds = seconds).validate()
        for (seconds in WakeTimers.typing) AlarmDraft(typingSeconds = seconds).validate()
        for (seconds in WakeTimers.puzzle) AlarmDraft(puzzleSeconds = seconds).validate()
        assertThrows(IllegalArgumentException::class.java) { AlarmDraft(mathSeconds = 12).validate() }
    }
}
