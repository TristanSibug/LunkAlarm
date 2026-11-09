package online.reeeserve.lunkalarm

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import org.junit.*
import org.junit.Assert.*

class PermissionGateTest {
    @get:Rule val rule = createAndroidComposeRule<MainActivity>()
    @Test fun missingExactAlarmAccessDoesNotCreateAnUnscheduledAlarm() {
        rule.runOnIdle { rule.activity.graph.repository.resetForTests(rule.activity) }
        assertFalse(rule.activity.graph.controller.scheduler.exactAllowed)
        rule.onNodeWithTag("view-alarms").performClick()
        rule.onNodeWithTag("new-alarm").performClick()
        rule.onNodeWithTag("save-alarm").performClick()
        rule.onNodeWithText("Allow alarms & reminders").assertExists()
        assertTrue(rule.activity.graph.repository.state.value.alarms.isEmpty())
    }
}
