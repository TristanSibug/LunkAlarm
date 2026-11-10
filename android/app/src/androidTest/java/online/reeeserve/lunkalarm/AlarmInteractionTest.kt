package online.reeeserve.lunkalarm

import android.content.Intent
import android.os.SystemClock
import android.view.KeyEvent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.*
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import online.reeeserve.lunkalarm.core.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runners.MethodSorters
import java.io.File

@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class AlarmInteractionTest {
    @get:Rule val rule = createAndroidComposeRule<MainActivity>()
    private val context get() = rule.activity
    private val repo get() = context.graph.repository
    private val controller get() = context.graph.controller
    private val device get() = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    @Before fun prepare() {
        device.executeShellCommand("dumpsys deviceidle unforce")
        device.wakeUp(); device.executeShellCommand("wm dismiss-keyguard")
        rule.runOnIdle {
            repo.state.value.alarms.forEach { controller.scheduler.cancel(it.id) }
            context.stopService(Intent(context, AlarmService::class.java)); repo.resetForTests(context)
        }
    }
    @After fun cleanup() {
        device.executeShellCommand("locksettings clear --old 1234")
        device.executeShellCommand("dumpsys deviceidle unforce"); device.executeShellCommand("dumpsys battery reset")
        device.wakeUp(); device.executeShellCommand("wm dismiss-keyguard")
        rule.runOnUiThread {
            repo.state.value.alarms.forEach { controller.scheduler.cancel(it.id) }
            context.stopService(Intent(context, AlarmService::class.java)); repo.resetForTests(context)
        }
    }
    private fun capture(name: String) {
        rule.waitForIdle()
        SystemClock.sleep(250) // Let the rendered surface catch up with sheet/state transitions.
        rule.waitForIdle()
        val folder = File(context.getExternalFilesDir(null), "previews").apply { mkdirs() }
        device.takeScreenshot(File(folder, "$name.png"))
    }
    private fun openEditor() {
        rule.onNodeWithTag("view-alarms").performClick(); rule.onNodeWithTag("new-alarm").performClick()
        rule.onNodeWithTag("alarm-editor").assertExists()
    }
    private fun mission(draft: AlarmDraft) {
        rule.runOnIdle {
            assertTrue(controller.save(draft.copy(timer = true, seconds = 120)))
            val record = repo.state.value.alarms.single()
            controller.scheduler.cancel(record.id); controller.trigger(record.id)
            AlarmService.start(context); context.startActivity(RingingActivity.intent(context))
        }
        rule.waitUntil(10000) { repo.state.value.session?.opened == true }
        rule.onNodeWithTag("ringing-screen").assertExists()
    }
    @Test fun a_realAlarmFiresInDozeAfterLeavingAppAndTimerIsRemovedAfterStop() {
        rule.runOnIdle { assertTrue(controller.save(AlarmDraft(timer = true, seconds = 5, volume = .2f))) }
        device.pressHome(); device.sleep()
        device.executeShellCommand("dumpsys battery unplug"); device.executeShellCommand("dumpsys deviceidle force-idle")
        rule.waitUntil(15000) { repo.state.value.session != null && AlarmService.isPlaying }
        device.executeShellCommand("dumpsys deviceidle unforce"); device.wakeUp(); device.executeShellCommand("wm dismiss-keyguard")
        rule.runOnUiThread { context.startActivity(RingingActivity.intent(context)) }
        rule.onNodeWithTag("stop-alarm").performScrollTo().performClick()
        rule.waitUntil(8000) { repo.state.value.session == null }
        assertTrue(repo.state.value.alarms.isEmpty())
    }
    @Test fun b_blankNameEditExactDuplicateAndFloatingSave() {
        openEditor()
        rule.onNodeWithText("Alarm name (optional)").assertExists()
        val y = rule.onNodeWithTag("save-alarm").fetchSemanticsNode().boundsInRoot.top
        rule.onNodeWithTag("editor-form").performScrollToNode(hasTestTag("wake-tests"))
        assertEquals(y, rule.onNodeWithTag("save-alarm").fetchSemanticsNode().boundsInRoot.top, 1f)
        capture("android-floating-add")
        rule.onNodeWithTag("save-alarm").performClick()
        rule.waitUntil { repo.state.value.alarms.size == 1 }
        val original = repo.state.value.alarms.single()
        assertEquals("", original.draft.name)
        val left = rule.onNodeWithTag("alarms-heading").fetchSemanticsNode().boundsInRoot.left
        rule.onNodeWithTag("alarm-${original.id}").performClick()
        rule.onNodeWithTag("alarm-name").performTextInput("Morning")
        rule.onNodeWithTag("save-alarm").performClick()
        assertEquals(original.id, repo.state.value.alarms.single().id)
        rule.onNodeWithContentDescription("Options for Morning").performClick()
        rule.onNodeWithText("Duplicate").performClick()
        rule.waitUntil { repo.state.value.alarms.size == 2 }
        assertEquals(repo.state.value.alarms[0].draft, repo.state.value.alarms[1].draft)
        assertNotEquals(repo.state.value.alarms[0].id, repo.state.value.alarms[1].id)
        assertEquals(left, rule.onNodeWithTag("alarms-heading").fetchSemanticsNode().boundsInRoot.left, 1f)
        capture("android-saved-alarms")
    }
    @Test fun c_swipeNavigationCountdownEditingAndDeleteGestures() {
        rule.onNodeWithTag("big-clock").performTouchInput { swipeUp() }
        rule.onNodeWithTag("your-alarms").assertExists()
        val left = rule.onNodeWithTag("alarms-heading").fetchSemanticsNode().boundsInRoot.left
        capture("android-empty-list")
        rule.onNodeWithTag("new-alarm").performClick()
        rule.onNodeWithTag("mode-timer").performClick()
        rule.onNodeWithTag("duration-hours").assertExists(); rule.onNodeWithText("8 hours").assertDoesNotExist()
        rule.onNodeWithTag("save-alarm").performClick()
        val first = repo.state.value.alarms.single()
        assertTrue(first.draft.timer)
        assertEquals(left, rule.onNodeWithTag("alarms-heading").fetchSemanticsNode().boundsInRoot.left, 1f)
        rule.onNodeWithTag("alarm-${first.id}").performClick()
        rule.onNodeWithText("Edit alarm").assertExists(); rule.onNodeWithTag("duration-minutes").assertExists()
        capture("android-edit-countdown")
        rule.onNodeWithTag("save-alarm").performClick()
        assertEquals(first.id, repo.state.value.alarms.single().id)
        rule.runOnIdle { assertTrue(controller.duplicate(repo.state.value.alarms.single())) }
        val second = repo.state.value.alarms.first { it.id != first.id }
        rule.onNodeWithTag("alarm-${first.id}").performTouchInput { swipe(Offset(width * .9f, height * .5f), Offset(width * .6f, height * .5f), 400) }
        rule.onNodeWithTag("alarm-editor").assertDoesNotExist()
        capture("android-swipe-delete")
        rule.onNodeWithTag("swipe-delete-${first.id}").performClick()
        // The animated delete also cancels AlarmManager ownership and writes storage asynchronously.
        rule.waitUntil(5000) { repo.state.value.alarms.none { it.id == first.id } }
        rule.onNodeWithTag("alarm-${second.id}").performTouchInput { swipeLeft(durationMillis = 400) }
        rule.waitUntil(5000) { repo.state.value.alarms.isEmpty() }
        rule.onNodeWithTag("your-alarms").performTouchInput { swipeDown() }
        rule.onNodeWithTag("big-clock").assertExists()
    }
    @Test fun d_mathAutoSubmissionAndWrongDigitsClear() {
        mission(AlarmDraft(mathCount = 2, mathSeconds = 15, volume = .2f))
        rule.onNodeWithTag("challenge-sound").assertIsOff()
        rule.onNodeWithText("OK").assertDoesNotExist()
        val expectedLength = (repo.state.value.session!!.challenge.left + repo.state.value.session!!.challenge.right).toString().length
        repeat(expectedLength) { rule.onNodeWithTag("key-0").performScrollTo().performClick() }
        rule.onNodeWithTag("math-answer").assertTextEquals("Your answer")
        repeat(2) {
            val c = repo.state.value.session!!.challenge
            (c.left + c.right).toString().forEach { digit -> rule.onNodeWithTag("key-$digit").performScrollTo().performClick() }
        }
        rule.waitUntil(8000) { repo.state.value.session == null }
        assertTrue(repo.state.value.alarms.isEmpty())
    }
    @Test fun e_mathTimeoutResetsProgressAndRestartsActualAudio() {
        mission(AlarmDraft(mathCount = 2, mathSeconds = 5, volume = .2f))
        val c = repo.state.value.session!!.challenge
        (c.left + c.right).toString().forEach { rule.onNodeWithTag("key-$it").performScrollTo().performClick() }
        assertEquals(1, repo.state.value.session!!.challenge.answered)
        rule.waitUntil(8000) { repo.state.value.session?.challenge?.resets == 1 && AlarmService.isPlaying }
        assertEquals(0, repo.state.value.session!!.challenge.answered); assertTrue(repo.state.value.session!!.sound)
        capture("android-timed-math")
    }
    @Test fun f_typingKeyboardCodeAndTimersAreRetained() {
        mission(AlarmDraft(typing = true, codeLength = 4, typingSeconds = 30, mathCount = 0, volume = .2f))
        rule.onNodeWithTag("wake-code").performScrollTo().performClick()
        device.pressKeyCode(KeyEvent.KEYCODE_A)
        device.pressKeyCode(KeyEvent.KEYCODE_DEL)
        val code = repo.state.value.session!!.challenge.code
        code.forEach { char ->
            val key = when { char.isDigit() -> KeyEvent.KEYCODE_0 + (char - '0'); else -> KeyEvent.KEYCODE_A + (char.lowercaseChar() - 'a') }
            device.pressKeyCode(key, if (char.isUpperCase()) KeyEvent.META_SHIFT_ON else 0)
        }
        device.pressBack()
        capture("android-typing-test")
        rule.onNodeWithTag("check-code").performScrollTo().performClick()
        rule.waitUntil(8000) { repo.state.value.session == null }
    }
    @Test fun g_failedUnlockAndRelockDoNotMuteAlarmOrStartQuestionTimer() {
        device.executeShellCommand("locksettings set-pin 1234")
        rule.runOnIdle { assertTrue(controller.save(AlarmDraft(timer = true, seconds = 5, mathCount = 1, volume = .2f))) }
        device.pressHome(); device.sleep()
        rule.waitUntil(15000) { repo.state.value.session != null && AlarmService.isPlaying }
        device.wakeUp()
        rule.runOnUiThread { context.startActivity(RingingActivity.intent(context)) }
        rule.onNodeWithTag("unlock-tests").performClick()
        device.pressBack(); device.sleep()
        rule.waitUntil(5000) { AlarmService.isPlaying }
        assertFalse(repo.state.value.session!!.opened)
        assertTrue(repo.state.value.session!!.sound)
        assertEquals(0L, repo.state.value.session!!.challenge.deadline)
    }
    @Test fun h_queuedAlarmStartsItsTestsWithoutReopeningActivity() {
        mission(AlarmDraft(mathCount = 1, mathSeconds = 15, volume = .2f))
        var second = ""
        rule.runOnUiThread {
            assertTrue(controller.save(AlarmDraft(timer = true, seconds = 120, mathCount = 1, mathSeconds = 15, tone = "soft-chime", volume = .2f)))
            second = repo.state.value.alarms.first { !it.active }.id
            controller.scheduler.cancel(second); controller.trigger(second)
        }
        val first = repo.state.value.session!!.challenge
        (first.left + first.right).toString().forEach { rule.onNodeWithTag("key-$it").performScrollTo().performClick() }
        rule.waitUntil(8000) { repo.state.value.session?.owner == second && repo.state.value.session?.opened == true }
        rule.onNodeWithTag("challenge-sound").assertIsOff()
        val next = repo.state.value.session!!.challenge
        (next.left + next.right).toString().forEach { rule.onNodeWithTag("key-$it").performScrollTo().performClick() }
        rule.waitUntil(8000) { repo.state.value.session == null }
        assertTrue(repo.state.value.alarms.isEmpty())
    }

    @Test fun i_adjustingPreviewVolumeDoesNotStopPreview() {
        openEditor()
        rule.onNodeWithTag("editor-form").performScrollToNode(hasTestTag("ringtone-picker"))
        rule.onNodeWithText("Preview", substring = false).performClick()
        rule.onNodeWithTag("editor-form").performScrollToNode(hasTestTag("alarm-volume"))
        rule.onNodeWithTag("alarm-volume").performSemanticsAction(SemanticsActions.SetProgress) { it(.4f) }
        rule.onNodeWithText("Stop", substring = false).assertExists().performClick()
        rule.onNodeWithText("Preview", substring = false).assertExists()
    }


    @Test fun j_timeWheelCanOpenKeyboardAndCommitTypedMinutes() {
        openEditor()
        rule.onNodeWithTag("editor-form").performScrollToNode(hasTestTag("time-minute"))
        val field = device.findObject(androidx.test.uiautomator.By.clazz("android.widget.EditText").text("00"))
        assertNotNull(field)
        field.click(); field.text = "42"
        device.pressEnter()
        rule.onNodeWithTag("save-alarm").performClick()
        rule.waitUntil(5000) { repo.state.value.alarms.isNotEmpty() }
        assertEquals(42, repo.state.value.alarms.single().draft.minute)
    }
    @Test fun k_nativeMathKeyboardUsesTheSameAutomaticAnswerRules() {
        mission(AlarmDraft(mathCount = 2, mathSeconds = 15, nativeMathKeyboard = true, volume = .2f))
        rule.onNodeWithTag("key-1").assertDoesNotExist()
        rule.onNodeWithTag("native-math-answer").performTextInput("99")
        rule.onNodeWithTag("native-math-answer").assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.EditableText, androidx.compose.ui.text.AnnotatedString("")))
        repeat(2) {
            val c = repo.state.value.session!!.challenge
            rule.onNodeWithTag("native-math-answer").performTextInput((c.left + c.right).toString())
        }
        rule.waitUntil(8000) { repo.state.value.session == null }
    }
    @Test fun l_puzzleSupportsTapPlacementAndFinishesOnlyAfterAllPieces() {
        mission(AlarmDraft(puzzle = true, puzzlePieces = 8, puzzleSeconds = 40, volume = .2f))
        rule.onNodeWithTag("challenge-sound").assertIsOff()
        rule.onNodeWithTag("puzzle-piece-0").performScrollTo().performClick()
        rule.onNodeWithTag("puzzle-slot-1").performScrollTo().performClick()
        assertTrue(repo.state.value.session!!.challenge.placedPieces.isEmpty())
        for (id in 0..7) {
            rule.onNodeWithTag("puzzle-piece-$id").performScrollTo().performClick()
            rule.onNodeWithTag("puzzle-slot-$id").performScrollTo().performClick()
        }
        rule.waitUntil(8000) { repo.state.value.session == null }
    }
    @Test fun m_allThemesKeepInheritedLabelsReadable() {
        for (theme in Themes.all) {
            rule.runOnIdle { repo.update { it.copy(theme = theme.id) } }
            openEditor()
            rule.onNodeWithTag("editor-form").performScrollToNode(hasTestTag("mode-timer"))
            rule.onNodeWithTag("mode-timer").performClick()
            rule.onNodeWithText("5 min").assertExists()
            capture("android-theme-${theme.id}")
            rule.onNodeWithTag("close-editor").performClick()
            rule.onNodeWithText("Clock", substring = false).performClick()
        }
    }

    @Test fun n_jigsawDragSnapsThePieceWithoutExtendingTime() {
        mission(AlarmDraft(puzzle = true, puzzlePieces = 8, puzzleSeconds = 40, volume = .2f))
        rule.onNodeWithTag("puzzle-piece-0").performScrollTo()
        val board = rule.onNodeWithTag("jigsaw-board").fetchSemanticsNode().boundsInRoot
        val tray = rule.onNodeWithTag("puzzle-piece-0").fetchSemanticsNode().boundsInRoot
        val w = board.width / 4; val h = board.width * .58f / 2
        val pad = with(rule.density) { androidx.compose.ui.unit.Dp(8f).toPx() }
        val start = Offset(pad + .43f * w * .74f, pad + .43f * h * .74f)
        val end = board.topLeft + Offset(w / 2, h / 2) - tray.topLeft
        val deadline = repo.state.value.session!!.challenge.deadline
        rule.onNodeWithTag("puzzle-piece-0").performTouchInput { swipe(start, end, durationMillis = 700) }
        rule.waitUntil(3000) { 0 in repo.state.value.session!!.challenge.placedPieces }
        assertEquals(deadline, repo.state.value.session!!.challenge.deadline)
        capture("android-jigsaw-puzzle")
    }
    @Test fun o_testTilesKeepOtherTestsAndSettingsUseFiniteButtons() {
        openEditor()
        rule.onNodeWithTag("editor-form").performScrollToNode(hasTestTag("wake-tests"))
        rule.onNodeWithText("Tap off", substring = true).assertDoesNotExist()
        rule.onNodeWithTag("test-tile-typing").performScrollTo().performClick()
        rule.onNodeWithTag("test-settings-typing").assertExists()
        rule.onNodeWithText("to dismiss your alarm", substring = true).assertDoesNotExist()
        repeat(2) { rule.onNodeWithTag("typing-length-plus").performClick() }
        rule.onNodeWithTag("typing-length-value").assertTextEquals("10")
        rule.onNodeWithTag("typing-length-plus").assertIsNotEnabled()
        rule.onNodeWithTag("typing-timer-25").performClick()
        capture("android-typing-settings")
        rule.onNodeWithTag("test-settings-done").performClick()
        rule.onNodeWithTag("test-tile-typing").assertIsOn()
        rule.onNodeWithTag("test-tile-math").performScrollTo().performClick()
        rule.onNodeWithTag("math-count-plus").performClick()
        rule.onNodeWithTag("math-timer-15").performClick()
        rule.onNodeWithText("Use your Android number keyboard for math answers").assertDoesNotExist()
        capture("android-math-settings")
        rule.onNodeWithTag("test-settings-done").performClick()
        rule.onNodeWithTag("test-tile-typing").assertIsOn()
        rule.onNodeWithTag("test-tile-math").assertIsOn().performClick()
        rule.onNodeWithTag("test-tile-math").assertIsOff()
        rule.onNodeWithTag("test-settings-math").assertDoesNotExist()
        rule.onNodeWithTag("test-tile-puzzle").performScrollTo().performClick()
        rule.onNodeWithTag("puzzle-pieces-7").assertDoesNotExist()
        rule.onNodeWithTag("puzzle-pieces-10").performClick()
        capture("android-puzzle-settings")
        rule.onNodeWithTag("test-settings-done").performClick()
        rule.onNodeWithTag("test-tile-mines").performScrollTo().performClick()
        rule.onNodeWithTag("mine-difficulty-2").performClick()
        rule.onNodeWithTag("mine-timer-40").performClick()
        capture("android-minesweeper-settings")
        rule.onNodeWithTag("test-settings-done").performClick()
        rule.onNodeWithTag("test-tile-sudoku").performScrollTo().performClick()
        rule.onNodeWithTag("sudoku-difficulty-3").performClick()
        rule.onNodeWithTag("sudoku-timer-120").performClick()
        val tops = listOf(30, 60, 90, 120).map { rule.onNodeWithTag("sudoku-timer-$it").fetchSemanticsNode().boundsInRoot.top }
        assertTrue(tops.all { kotlin.math.abs(it - tops.first()) < 1f })
        capture("android-sudoku-settings")
        rule.onNodeWithTag("test-settings-done").performClick()
        capture("android-wake-test-tiles")
        rule.onNodeWithTag("save-alarm").performClick()
        rule.waitUntil { repo.state.value.alarms.size == 1 }
        val saved = repo.state.value.alarms.single().draft
        assertTrue(saved.typing && saved.puzzle && saved.mines && saved.sudoku)
        assertEquals(0, saved.mathCount); assertEquals(10, saved.codeLength); assertEquals(25, saved.typingSeconds)
        assertEquals(10, saved.puzzlePieces); assertEquals(2, saved.mineDifficulty); assertEquals(3, saved.sudokuDifficulty); assertEquals(120, saved.sudokuSeconds)
    }
    @Test fun p_everyTryCanBeExitedWithoutSchedulingOrMutatingAnAlarm() {
        openEditor()
        rule.onNodeWithTag("editor-form").performScrollToNode(hasTestTag("wake-tests"))
        for (test in WakeTest.entries) {
            val tag = test.name.lowercase()
            rule.onNodeWithTag("test-tile-$tag").performScrollTo().performClick()
            rule.onNodeWithTag("try-$tag").performClick()
            rule.onNodeWithTag("practice-test").assertExists()
            assertTrue(repo.state.value.alarms.isEmpty()); assertNull(repo.state.value.session); assertFalse(AlarmService.isPlaying)
            capture("android-practice-$tag")
            if (test == WakeTest.SUDOKU) device.pressBack() else rule.onNodeWithTag("exit-practice").performClick()
            rule.onNodeWithTag("test-settings-$tag").assertExists()
            rule.onNodeWithTag("test-settings-done").performClick()
        }
        rule.onNodeWithTag("save-alarm").performClick()
        rule.waitUntil { repo.state.value.alarms.size == 1 }
        assertTrue(repo.state.value.alarms.single().draft.let { it.typing && it.mathCount > 0 && it.puzzle && it.mines && it.sudoku })
        assertNull(repo.state.value.session)
    }
    @Test fun q_minesweeperAndSudokuShareTheRealAlarmCompletionPath() {
        mission(AlarmDraft(mines = true, mineSeconds = 40, sudoku = true, sudokuSeconds = 120, volume = .2f))
        rule.onNodeWithTag("mine-board").assertExists()
        val mine = repo.state.value.session!!.challenge.mineBoard!!
        rule.onNodeWithTag("mine-mode").performClick()
        mine.mines.forEach { rule.onNodeWithTag("mine-cell-$it").performScrollTo().performClick() }
        if (repo.state.value.session!!.challenge.minesPending) {
            rule.onNodeWithTag("mine-mode").performClick()
            mine.cells.filterNot { it in mine.mines || it in mine.revealed }.forEach { rule.onNodeWithTag("mine-cell-$it").performScrollTo().performClick() }
        }
        rule.onNodeWithTag("sudoku-board").assertExists()
        val sudoku = repo.state.value.session!!.challenge.sudokuBoard!!
        val first = sudoku.givens.indexOfFirst { it == 0 }
        rule.onNodeWithTag("sudoku-cell-$first").performScrollTo().performClick()
        rule.onNodeWithTag("sudoku-digit-${sudoku.solution[first]}").performScrollTo().performClick()
        assertEquals(1, repo.state.value.session!!.challenge.sudokuBoard!!.filled)
        rule.onNodeWithTag("sudoku-erase").performScrollTo().performClick()
        assertEquals(0, repo.state.value.session!!.challenge.sudokuBoard!!.filled)
        capture("android-sudoku-game")
        for (cell in sudoku.givens.indices.filter { sudoku.givens[it] == 0 }) {
            rule.onNodeWithTag("sudoku-cell-$cell").performScrollTo().performClick()
            rule.onNodeWithTag("sudoku-digit-${sudoku.solution[cell]}").performScrollTo().performClick()
        }
        rule.waitUntil(8000) { repo.state.value.session == null }
        assertTrue(repo.state.value.alarms.isEmpty())
    }
    @Test fun r_gameTimeoutAndMineHitRestartSoundAndPersistedProgress() {
        mission(AlarmDraft(mines = true, mineSeconds = 15, sudoku = true, volume = .2f))
        val session = repo.state.value.session!!
        rule.runOnUiThread {
            repo.update { it.copy(session = session.copy(challenge = session.challenge.copy(deadline = SystemClock.elapsedRealtime() - 1))) }
            controller.tick()
        }
        rule.waitUntil(5000) { repo.state.value.session?.challenge?.resets == 1 && AlarmService.isPlaying }
        assertTrue(repo.state.value.session!!.sound)
        rule.onNodeWithTag("challenge-sound").performClick()
        val mine = repo.state.value.session!!.challenge.mineBoard!!.mines.first()
        rule.onNodeWithTag("mine-cell-$mine").performScrollTo().performClick()
        rule.waitUntil(5000) { repo.state.value.session?.challenge?.resets == 2 && AlarmService.isPlaying }
        assertTrue(repo.state.value.session!!.sound)
    }

}
