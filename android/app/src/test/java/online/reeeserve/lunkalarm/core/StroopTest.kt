package online.reeeserve.lunkalarm.core

import online.reeeserve.lunkalarm.AlarmJson
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import kotlin.random.Random

class StroopTest {
    @Test fun roundsAlwaysUseConflictingWordsAndBackgroundsWithoutRepeatingTheAnswer() {
        var previous: StroopColor? = null
        repeat(500) { seed ->
            val round = StroopRound.create(previous, Random(seed))
            round.validate(); assertNotEquals(round.word, round.ink); assertNotEquals(previous, round.ink)
            assertEquals(StroopColor.entries.toSet(), round.buttonColors.toSet())
            StroopColor.entries.zip(round.buttonColors).forEach { (label, background) -> assertNotEquals(label, background) }
            previous = round.ink
        }
        assertEquals(listOf("Red", "Blue", "Green", "Yellow"), StroopColor.entries.map { it.label })
    }
    @Test fun settingsUseTheSameBoundsAsIOS() {
        assertEquals((3..8).toList(), WakeTimers.stroopRounds.toList()); assertEquals(listOf(3, 4, 5, 6), WakeTimers.stroop)
        for (rounds in 3..8) for (seconds in 3..6) AlarmDraft(stroop = true, stroopRounds = rounds, stroopSeconds = seconds).validate()
        for (rounds in listOf(2, 9)) assertThrows(IllegalArgumentException::class.java) { AlarmDraft(stroopRounds = rounds).validate() }
        for (seconds in listOf(2, 7)) assertThrows(IllegalArgumentException::class.java) { AlarmDraft(stroopSeconds = seconds).validate() }
        assertFalse(AlarmRecord.create(AlarmDraft(), 1000, 1000, 1).hasTests)
        assertTrue(AlarmRecord.create(AlarmDraft(stroop = true), 1000, 1000, 1).hasTests)
    }
    @Test fun correctAnswersRenewRoundsAndWrongAnswersLeaveTheDeadlineAndProgressIntact() {
        for (rounds in 3..8) {
            var c = WakeChallenge.create(AlarmDraft(stroop = true, stroopRounds = rounds, stroopSeconds = 6))
            assertEquals(AnswerResult.INCOMPLETE, c.submitStroop(c.stroopRound!!.ink, 1000).result)
            c = c.start(1000); assertEquals(7000L, c.deadline)
            repeat(rounds) { i ->
                val round = c.stroopRound!!; val now = 1500L + i * 500
                val wrong = c.submitStroop(round.word, now)
                assertEquals(AnswerResult.INCORRECT, wrong.result); assertEquals(c, wrong.challenge)
                val right = c.submitStroop(round.ink, now)
                assertEquals(AnswerResult.CORRECT, right.result); c = right.challenge
                assertEquals(i + 1, c.stroopAnswered)
                if (i + 1 < rounds) { assertEquals(now + 6000, c.deadline); assertNotEquals(round.ink, c.stroopRound!!.ink) }
            }
            assertTrue(c.complete); assertEquals(0L, c.deadline)
            assertEquals(AnswerResult.INCOMPLETE, c.submitStroop(StroopColor.RED, 10000).result)
        }
    }
    @Test fun lateAnswersRestartAllSelectedTestsAndResetStroopProgress() {
        var c = WakeChallenge.create(AlarmDraft(typing = true, mathCount = 1, stroop = true, stroopRounds = 3, stroopSeconds = 3)).start(1000)
        assertEquals(AnswerResult.INCOMPLETE, c.submitStroop(c.stroopRound!!.ink, 1100).result)
        c = c.submitCode(c.code, 1200).challenge
        c = c.submitDigits(c.answer.toString(), 1300).challenge
        c = c.submitStroop(c.stroopRound!!.ink, 1400).challenge
        assertEquals(1, c.stroopAnswered)
        val expired = c.submitStroop(c.stroopRound!!.ink, c.deadline)
        assertEquals(AnswerResult.TIMED_OUT, expired.result)
        assertTrue(expired.challenge.typingPending); assertEquals(0, expired.challenge.answered)
        assertEquals(0, expired.challenge.stroopAnswered); assertEquals(1, expired.challenge.resets)
        assertTrue(expired.challenge.stroopRound != null)
    }
    @Test fun allSixStagesReachStroopBeforeCompleting() {
        var c = WakeChallenge.create(AlarmDraft(typing = true, mathCount = 1, puzzle = true, mines = true, sudoku = true, stroop = true, stroopRounds = 3)).start(1000)
        c = c.submitCode(c.code, 1200).challenge
        c = c.submitDigits(c.answer.toString(), 1300).challenge
        repeat(c.puzzlePieces) { c = c.placePiece(it, 1400).challenge }
        for (mine in c.mineBoard!!.mines) c = c.mineAction(mine, true, 1500).challenge
        c = c.mineAction(-1, false, 1500).challenge
        val b = c.sudokuBoard!!
        for (cell in b.givens.indices.filter { b.givens[it] == 0 }) c = c.sudokuAction(cell, b.solution[cell], 1600).challenge
        assertTrue(c.stroopPending); assertFalse(c.complete); assertEquals(6600L, c.deadline)
        repeat(3) { c = c.submitStroop(c.stroopRound!!.ink, 1700).challenge }
        assertTrue(c.complete); assertEquals(0L, c.deadline)
    }
    @Test fun partialProgressAndConfigurationSurviveSavingAndDuplicateWithTheAlarm() {
        val d = AlarmDraft(stroop = true, stroopRounds = 8, stroopSeconds = 4)
        val a = AlarmRecord.create(d, 100000, 1000, 1).copy(active = true)
        var c = WakeChallenge.create(d).start(1000)
        c = c.submitStroop(c.stroopRound!!.ink, 2000).challenge
        val state = AppState(draft = d, alarms = listOf(a), session = AlarmSession(a.id, c, sound = false, opened = true, boot = 1))
        val restored = AlarmJson.decode(AlarmJson.encode(state))
        assertEquals(state, restored); assertEquals(1, restored.session!!.challenge.stroopAnswered)
        assertEquals(6000L, restored.session!!.challenge.deadline)
        val copy = a.duplicate(200000, 3000, 1)
        assertEquals(d, copy.draft); assertNotEquals(a.id, copy.id); assertTrue(copy.hasTests)
    }
    @Test fun oldAlarmsAndSessionsLoadWithStroopDisabled() {
        val d = AlarmDraft(puzzle = true)
        val a = AlarmRecord.create(d, 100000, 1000, 1).copy(active = true)
        val state = AppState(draft = d, alarms = listOf(a), session = AlarmSession(a.id, WakeChallenge.create(d).start(1000), opened = true))
        val j = JSONObject(AlarmJson.encode(state))
        for (draft in listOf(j.getJSONObject("draft"), j.getJSONArray("alarms").getJSONObject(0).getJSONObject("draft"))) {
            listOf("stroop", "stroopRounds", "stroopSeconds").forEach { draft.remove(it) }
        }
        val challenge = j.getJSONObject("session").getJSONObject("challenge")
        listOf("stroop", "stroopRounds", "stroopSeconds", "stroopAnswered", "stroopRound").forEach { challenge.remove(it) }
        val restored = AlarmJson.decode(j.toString())
        assertFalse(restored.draft.stroop); assertFalse(restored.alarms.single().draft.stroop)
        assertFalse(restored.session!!.challenge.stroopPending); assertTrue(restored.session!!.challenge.puzzlePending)
        assertEquals(5, restored.draft.stroopRounds); assertEquals(5, restored.draft.stroopSeconds)
    }
    @Test fun corruptRoundsAndProgressAreRejected() {
        val d = AlarmDraft(stroop = true)
        val a = AlarmRecord.create(d, 100000, 1000, 1).copy(active = true)
        val j = JSONObject(AlarmJson.encode(AppState(alarms = listOf(a), session = AlarmSession(a.id, WakeChallenge.create(d).start(1000)))))
        val c = j.getJSONObject("session").getJSONObject("challenge")
        c.put("stroopAnswered", 9)
        assertThrows(IllegalArgumentException::class.java) { AlarmJson.decode(j.toString()) }
        c.put("stroopAnswered", 0)
        val round = c.getJSONObject("stroopRound"); round.put("word", round.getString("ink"))
        assertThrows(IllegalArgumentException::class.java) { AlarmJson.decode(j.toString()) }
    }
}
