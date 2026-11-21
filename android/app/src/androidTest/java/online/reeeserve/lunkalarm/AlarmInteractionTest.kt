package online.reeeserve.lunkalarm

import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.KeyEvent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.*
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
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
            finishRingingActivities()
            repo.state.value.alarms.forEach { controller.scheduler.cancel(it.id) }
            context.stopService(Intent(context, AlarmService::class.java)); repo.resetForTests(context)
        }
    }
    @After fun cleanup() {
        device.executeShellCommand("locksettings clear --old 1234")
        device.executeShellCommand("dumpsys deviceidle unforce"); device.executeShellCommand("dumpsys battery reset")
        device.wakeUp(); device.executeShellCommand("wm dismiss-keyguard")
        rule.runOnUiThread {
            finishRingingActivities()
            repo.state.value.alarms.forEach { controller.scheduler.cancel(it.id) }
            context.stopService(Intent(context, AlarmService::class.java)); repo.resetForTests(context)
        }
    }
    // Clearing a session also finishes its UI asynchronously. Finish it explicitly before
    // the next test creates a different owner, especially after failed secure unlock.
    private fun finishRingingActivities() {
        val monitor = ActivityLifecycleMonitorRegistry.getInstance()
        listOf(Stage.CREATED, Stage.STARTED, Stage.RESUMED, Stage.PAUSED, Stage.STOPPED)
            .flatMap { monitor.getActivitiesInStage(it) }.filterIsInstance<RingingActivity>().distinct().forEach { it.finish() }
    }
    private fun capture(name: String) {
        rule.waitForIdle()
        SystemClock.sleep(250) // Let the rendered surface catch up with sheet/state transitions.
        rule.waitForIdle()
        val folder = File(context.getExternalFilesDir(null), "previews").apply { mkdirs() }
        device.takeScreenshot(File(folder, "$name.png"))
    }
    private fun openEditor(timer: Boolean = false) {
        rule.onNodeWithTag("view-alarms").performClick(); rule.onNodeWithTag("new-alarm").performClick()
        rule.onNodeWithTag(if (timer) "add-menu-timer" else "add-menu-alarm").performClick()
        rule.onNodeWithTag("alarm-editor").assertExists()
    }
    private fun mission(draft: AlarmDraft) {
        device.wakeUp(); device.executeShellCommand("wm dismiss-keyguard")
        rule.waitUntil(10000) { !context.getSystemService(KeyguardManager::class.java).isKeyguardLocked }
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
    @Test fun b_firstEditorUpdatesSevenAmInPlaceAndPreservesOtherAlarms() {
        rule.runOnIdle {
            assertTrue(controller.save(AlarmDraft(name = "Morning", hour = 7, minute = 0)))
            assertTrue(controller.save(AlarmDraft(name = "Evening", hour = 19, minute = 0)))
        }
        val before = repo.state.value.alarms
        val original = before.single { it.draft.name == "Morning" }
        val other = before.single { it.draft.name == "Evening" }
        rule.onNodeWithTag("view-alarms").performClick()
        rule.onNodeWithTag("alarm-${original.id}").performClick()
        rule.onNodeWithText("Edit alarm").assertExists()
        rule.onNodeWithTag("editor-form").performScrollToNode(hasTestTag("time-minute"))
        val field = device.findObject(androidx.test.uiautomator.By.clazz("android.widget.EditText").text("00"))
        assertNotNull(field)
        field.click(); field.text = "30"; device.pressEnter()
        rule.onNodeWithTag("save-alarm").performClick()
        rule.waitUntil(5000) { repo.state.value.alarms.any { it.id == original.id && it.draft.minute == 30 } }
        val after = repo.state.value.alarms
        assertEquals(2, after.size)
        assertEquals(before.map { it.id }.toSet(), after.map { it.id }.toSet())
        assertEquals(other, after.single { it.id == other.id })
        val updated = after.single { it.id == original.id }
        assertEquals(7, updated.draft.hour); assertEquals(30, updated.draft.minute)
        assertEquals(original.draft.copy(minute = 30), updated.draft)
        capture("android-edit-seven-to-seven-thirty")
    }

    @Test fun b_smartDuplicateAddsThreeOffsetsWithTestsOnTheOriginalOnly() {
        rule.runOnIdle { assertTrue(controller.save(AlarmDraft(name = "Morning", hour = 7, minute = 0, typing = true, mathCount = 3))) }
        val original = repo.state.value.alarms.single()
        rule.onNodeWithTag("view-alarms").performClick()
        rule.onNodeWithTag("options-${original.id}").performClick()
        rule.onNodeWithText("Smart Duplicate").performClick()
        rule.onNodeWithText("Original only").assertIsSelected()
        rule.onNodeWithText("All alarms").assertExists()
        repeat(2) { rule.onNodeWithContentDescription("Increase Duplicates").performClick() }
        rule.onNodeWithTag("create-smart-duplicates").performClick()
        rule.waitUntil { repo.state.value.alarms.size == 4 }
        val copies = repo.state.value.alarms.filter { it.id != original.id }
        assertEquals(listOf(5, 10, 15), copies.map { it.draft.minute })
        assertTrue(copies.all { it.draft.hour == 7 && !it.hasTests })
        assertEquals(original, repo.state.value.alarms.single { it.id == original.id })
    }

    @Test fun b_aboutPageHoldsClockControlsAndReturnsToClock() {
        rule.onNodeWithTag("open-about").assertExists()
        rule.onNodeWithText("Theme").assertDoesNotExist()
        rule.onNodeWithTag("big-clock").performTouchInput { swipeDown() }
        rule.onNodeWithText("By Tristan Josh E. Sibug").assertIsDisplayed()
        rule.onNodeWithText("Theme").assertIsDisplayed()
        rule.onNodeWithText("12-hour · 2:30 PM").assertIsDisplayed()
        rule.onNodeWithText("Clock format").performClick()
        rule.onNodeWithText("24-hour · 14:30").assertIsDisplayed()
        rule.onNodeWithText("Clock font").performClick()
        rule.onNodeWithText("Serif").performClick()
        assertEquals("serif", repo.state.value.clockFontId)
        rule.onNodeWithText("Serif").assertIsDisplayed()
        rule.onNodeWithText("Clock", substring = false).performClick()
        rule.onNodeWithText("Theme").assertDoesNotExist()
        rule.onNodeWithTag("view-alarms").performClick()
        rule.onNodeWithText("Clock", substring = false).performClick()
        rule.onNodeWithText("Theme").assertDoesNotExist()
        rule.onNodeWithTag("open-about").performClick()
        rule.onNodeWithTag("about-page").assertIsDisplayed()
    }

    @Test fun c_swipeNavigationCountdownEditingAndDeleteGestures() {
        rule.onNodeWithTag("big-clock").performTouchInput { swipeUp() }
        rule.onNodeWithTag("your-alarms").assertExists()
        val left = rule.onNodeWithTag("alarms-heading").fetchSemanticsNode().boundsInRoot.left
        capture("android-empty-list")
        rule.onNodeWithTag("new-alarm").performClick()
        rule.onNodeWithTag("add-menu-timer").performClick()
        rule.onNodeWithTag("duration-hours").assertExists(); rule.onNodeWithText("8 hours").assertDoesNotExist()
        rule.onNodeWithTag("save-alarm").performClick()
        val first = repo.state.value.alarms.single()
        assertTrue(first.draft.timer)
        assertEquals(left, rule.onNodeWithTag("timers-heading").fetchSemanticsNode().boundsInRoot.left, 1f)
        rule.onNodeWithTag("alarm-${first.id}").performClick()
        rule.onNodeWithText("Edit timer").assertExists(); rule.onNodeWithTag("duration-minutes").assertExists()
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
        rule.onNodeWithTag("ringtone-picker").performClick()
        rule.onNodeWithTag("ringtone-sound-checker").performClick()
        rule.onNodeWithText("Digital Watch").performScrollTo().performClick()
        rule.onNodeWithTag("ringtone-sound-checker").assertIsOn()
        capture("android-ringtone-sound-checker")
        rule.onNodeWithTag("ringtone-sound-checker").performClick()
        device.pressBack()
        rule.onNodeWithTag("editor-form").performScrollToNode(hasTestTag("alarm-volume"))
        rule.onNodeWithTag("alarm-volume").performSemanticsAction(SemanticsActions.SetProgress) { it(.4f) }
        rule.onNodeWithTag("alarm-vibrate").performClick().assertIsOn()
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
        rule.onNodeWithTag("native-math-answer").performClick()
        val input = device.findObject(androidx.test.uiautomator.By.desc("Math answer"))
        assertNotNull(input)
        val initial = repo.state.value.session!!.challenge.answer.toString().length
        repeat(initial) { device.pressKeyCode(KeyEvent.KEYCODE_9) }
        rule.waitUntil(3000) { input.text in listOf("", "Your answer") }
        repeat(2) { index ->
            val c = repo.state.value.session!!.challenge
            c.answer.toString().forEach { device.pressKeyCode(KeyEvent.KEYCODE_0 + (it - '0')) }
            if (index == 0) { rule.waitUntil(3000) { repo.state.value.session!!.challenge.answered == 1 && input.text in listOf("", "Your answer") }; assertTrue(input.isFocused) }
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
            openEditor(timer = true)
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
        rule.onNodeWithTag("test-tile-typing").assertIsSelected()
        rule.onNodeWithTag("test-tile-math").performScrollTo().performClick()
        rule.onNodeWithTag("math-count-plus").performClick()
        rule.onNodeWithTag("math-timer-15").performClick()
        rule.onNodeWithText("Use your Android number keyboard for math answers").assertDoesNotExist()
        capture("android-math-settings")
        rule.onNodeWithTag("test-settings-done").performClick()
        rule.onNodeWithTag("test-tile-typing").assertIsSelected()
        rule.onNodeWithTag("test-tile-math").assertIsSelected().performClick()
        rule.onNodeWithTag("test-settings-done").performClick()
        rule.onNodeWithTag("test-tile-math").assertIsNotSelected()
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
        val tops = listOf(60, 120, 180, 240).map { rule.onNodeWithTag("sudoku-timer-$it").fetchSemanticsNode().boundsInRoot.top }
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
            if (test == WakeTest.TYPING) {
                rule.onNodeWithTag("wake-code").performScrollTo().performClick()
                device.pressKeyCode(KeyEvent.KEYCODE_A)
                rule.onNodeWithTag("practice-test").assertExists()
                device.pressBack()
            }
            capture("android-practice-$tag")
            if (test == WakeTest.SUDOKU) device.pressBack() else rule.onNodeWithTag("exit-practice").performClick()
            rule.onNodeWithTag("test-settings-$tag").assertExists()
            rule.onNodeWithTag("test-settings-done").performClick()
        }
        rule.onNodeWithTag("save-alarm").performClick()
        rule.waitUntil { repo.state.value.alarms.size == 1 }
        assertTrue(repo.state.value.alarms.single().draft.let { it.typing && it.mathCount > 0 && it.puzzle && it.mines && it.sudoku && it.stroop })
        assertNull(repo.state.value.session)
    }
    @Test fun q_minesweeperAndSudokuShareTheRealAlarmCompletionPath() {
        mission(AlarmDraft(mines = true, mineSeconds = 40, sudoku = true, sudokuSeconds = 120, volume = .2f))
        rule.onNodeWithTag("mine-board").assertExists()
        val mine = repo.state.value.session!!.challenge.mineBoard!!
        rule.onNodeWithTag("mine-mode").performClick()
        mine.mines.forEach { rule.onNodeWithTag("mine-cell-$it").performScrollTo().performClick() }
        rule.onNodeWithTag("mine-done").performScrollTo().assertIsEnabled().performClick()
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

    @Test fun s_explicitSetAndOperationsKeepTheirStateWhenSheetCloses() {
        openEditor()
        rule.onNodeWithTag("editor-form").performScrollToNode(hasTestTag("wake-tests"))
        rule.onNodeWithTag("test-tile-math").performScrollTo().performClick()
        for (op in listOf("subtraction", "multiplication", "division")) rule.onNodeWithTag("math-operation-$op").performScrollTo().performClick()
        rule.onNodeWithTag("close-test-settings").performClick()
        rule.onNodeWithTag("test-tile-math").assertIsNotSelected().performClick()
        MathOperation.entries.forEach { rule.onNodeWithTag("math-operation-${it.name.lowercase()}").assertIsSelected() }
        rule.onNodeWithTag("test-settings-done").performScrollTo().performClick()
        rule.onNodeWithTag("test-tile-math").assertIsSelected().performClick()
        capture("android-math-four-operations")
        rule.onNodeWithTag("close-test-settings").performClick()
        rule.onNodeWithTag("save-alarm").performClick()
        assertEquals(MathOperation.entries.toSet(), repo.state.value.alarms.single().draft.mathOperations)
    }
    @Test fun t_alarmAndTimerHaveSeparateEditorsAndOrderedSections() {
        openEditor(timer = true)
        rule.onNodeWithText("New timer").assertExists()
        rule.onNodeWithTag("alarm-name").performTextInput("Tea")
        rule.onNodeWithTag("mode-timer").assertDoesNotExist()
        rule.onNodeWithTag("save-alarm").performClick()
        rule.onNodeWithTag("timers-heading").assertExists()
        rule.onNodeWithTag("alarms-heading").assertDoesNotExist()
        rule.onNodeWithTag("new-alarm").performClick(); rule.onNodeWithTag("add-menu-alarm").performClick()
        rule.onNodeWithTag("alarm-name").performTextInput("Morning")
        rule.onNodeWithTag("save-alarm").performClick()
        rule.onNodeWithTag("your-alarms").performTouchInput { swipeUp() }
        rule.onNodeWithTag("alarms-heading").assertExists()
        capture("android-alarms-and-timers")
        assertEquals("Tea", repo.state.value.alarms.first { it.draft.timer }.draft.name)
    }

    private fun stroopInk(): StroopColor {
        val description = rule.onNodeWithTag("stroop-word").fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].first()
        return StroopColor.valueOf(description.substringAfter("written in ").substringBefore(" ink").uppercase())
    }
    @Test fun u_stroopPracticeHasFiniteSettingsColoredChoicesAndIndependentActivation() {
        openEditor()
        rule.onNodeWithTag("editor-form").performScrollToNode(hasTestTag("wake-tests"))
        rule.onNodeWithTag("test-tile-typing").performScrollTo().performClick()
        rule.onNodeWithTag("test-settings-done").performClick()
        rule.onNodeWithTag("test-tile-stroop").performScrollTo().performClick()
        rule.onNodeWithTag("stroop-rounds-value").assertTextEquals("5")
        repeat(2) { rule.onNodeWithTag("stroop-rounds-minus").performClick() }
        rule.onNodeWithTag("stroop-rounds-value").assertTextEquals("3")
        rule.onNodeWithTag("stroop-rounds-minus").assertIsNotEnabled()
        repeat(5) { rule.onNodeWithTag("stroop-rounds-plus").performClick() }
        rule.onNodeWithTag("stroop-rounds-value").assertTextEquals("8")
        rule.onNodeWithTag("stroop-rounds-plus").assertIsNotEnabled()
        for (seconds in 3..6) rule.onNodeWithTag("stroop-timer-$seconds").performClick().assertIsSelected()
        capture("android-stroop-settings")
        rule.onNodeWithTag("try-stroop").performClick()
        rule.onNodeWithTag("stroop-progress").assertTextEquals("0 / 8 rounds")
        rule.onNodeWithTag("challenge-code").assertDoesNotExist()
        assertTrue(repo.state.value.alarms.isEmpty()); assertNull(repo.state.value.session); assertFalse(AlarmService.isPlaying)
        var frames = StroopColor.entries.map { rule.onNodeWithTag("stroop-choice-${it.name.lowercase()}").fetchSemanticsNode().boundsInRoot }
        for (color in StroopColor.entries) {
            val node = rule.onNodeWithTag("stroop-choice-${color.name.lowercase()}").assertIsDisplayed().fetchSemanticsNode()
            assertNotEquals(color.label + " background", node.config[androidx.compose.ui.semantics.SemanticsProperties.StateDescription])
        }
        val word = rule.onNodeWithTag("stroop-word").fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.Text].first().text.lowercase()
        rule.onNodeWithTag("stroop-choice-$word").performClick()
        rule.onNodeWithTag("stroop-progress").assertTextEquals("0 / 8 rounds")
        capture("android-stroop-practice")
        repeat(8) { i ->
            val ink = stroopInk()
            rule.onNodeWithTag("stroop-choice-${ink.name.lowercase()}").performClick()
            if (i < 7) {
                rule.onNodeWithTag("stroop-progress").assertTextEquals("${i + 1} / 8 rounds")
                assertNotEquals(ink, stroopInk())
                val after = StroopColor.entries.map { rule.onNodeWithTag("stroop-choice-${it.name.lowercase()}").fetchSemanticsNode().boundsInRoot }
                frames.zip(after).forEach { (old, new) -> assertTrue(kotlin.math.abs(old.left - new.left) > 1f || kotlin.math.abs(old.top - new.top) > 1f) }
                val oldAnswer = frames[ink.ordinal]; val newAnswer = after[stroopInk().ordinal]
                assertTrue(kotlin.math.abs(oldAnswer.left - newAnswer.left) > 1f || kotlin.math.abs(oldAnswer.top - newAnswer.top) > 1f)
                frames = after
            }
        }
        rule.onNodeWithTag("retry-practice").performClick()
        rule.onNodeWithTag("stroop-progress").assertTextEquals("0 / 8 rounds")
        rule.onNodeWithTag("exit-practice").performClick()
        rule.onNodeWithTag("test-settings-done").assertTextEquals("Set").performClick()
        rule.onNodeWithTag("test-tile-stroop").assertIsSelected()
        rule.onNodeWithTag("test-tile-typing").assertIsSelected()
        capture("android-six-test-tiles")
        rule.onNodeWithTag("test-tile-stroop").performClick()
        rule.onNodeWithTag("test-settings-done").assertTextEquals("Unset")
        rule.onNodeWithTag("close-test-settings").performClick()
        rule.onNodeWithTag("save-alarm").performClick()
        val saved = repo.state.value.alarms.single().draft
        assertTrue(saved.stroop && saved.typing); assertEquals(8, saved.stroopRounds); assertEquals(6, saved.stroopSeconds)
    }
    @Test fun v_stroopTimeoutRestartsTheRealAlarmAndSoundThenAllowsCompletion() {
        mission(AlarmDraft(stroop = true, stroopRounds = 3, stroopSeconds = 6, volume = .2f))
        rule.onNodeWithTag("stroop-progress").assertTextEquals("0 / 3 rounds")
        rule.onNodeWithTag("stroop-choice-${stroopInk().name.lowercase()}").performScrollTo().performClick()
        rule.waitUntil(5000) { repo.state.value.session?.challenge?.stroopAnswered == 1 }
        val session = repo.state.value.session!!
        assertFalse(session.sound)
        assertEquals(repo.state.value, AlarmJson.decode(AlarmJson.encode(repo.state.value)))
        rule.onNodeWithTag("stroop-choice-${session.challenge.stroopRound!!.word.name.lowercase()}").performScrollTo().performClick()
        assertEquals(session.challenge.deadline, repo.state.value.session!!.challenge.deadline)
        assertEquals(1, repo.state.value.session!!.challenge.stroopAnswered)
        rule.waitUntil(10000) { repo.state.value.session?.challenge?.resets == 1 && AlarmService.isPlaying }
        assertTrue(repo.state.value.session!!.sound)
        rule.onNodeWithTag("stroop-progress").assertTextEquals("0 / 3 rounds")
        capture("android-stroop-alarm-timeout")
        repeat(3) { rule.onNodeWithTag("stroop-choice-${stroopInk().name.lowercase()}").performScrollTo().performClick() }
        rule.waitUntil(10000) { repo.state.value.session == null && !AlarmService.isPlaying }
        assertTrue(repo.state.value.alarms.isEmpty())
    }

}
