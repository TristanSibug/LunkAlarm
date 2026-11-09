package online.reeeserve.lunkalarm

import android.content.Intent
import android.os.SystemClock
import android.view.KeyEvent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.*
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
        rule.waitUntil { repo.state.value.alarms.none { it.id == first.id } }
        rule.onNodeWithTag("alarm-${second.id}").performTouchInput { swipeLeft(durationMillis = 400) }
        rule.waitUntil { repo.state.value.alarms.isEmpty() }
        rule.onNodeWithTag("your-alarms").performTouchInput { swipeDown() }
        rule.onNodeWithTag("big-clock").assertExists()
    }
    @Test fun d_mathAutoSubmissionAndWrongDigitsClear() {
        mission(AlarmDraft(mathCount = 2, mathSeconds = 12, volume = .2f))
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
        mission(AlarmDraft(mathCount = 1, mathSeconds = 12, volume = .2f))
        var second = ""
        rule.runOnUiThread {
            assertTrue(controller.save(AlarmDraft(timer = true, seconds = 120, mathCount = 1, mathSeconds = 12, tone = "soft-chime", volume = .2f)))
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

}
