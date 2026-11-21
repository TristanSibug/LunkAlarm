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
        // The first-launch setup may already be visible on a clean install.
        val setup = rule.onAllNodesWithText("Allow alarms & reminders")
        if (setup.fetchSemanticsNodes().isNotEmpty()) rule.onNodeWithText("Close").performClick()
        rule.onNodeWithTag("view-alarms").performClick()
        rule.onNodeWithTag("new-alarm").performClick()
        rule.onNodeWithTag("add-menu-alarm").performClick()
        rule.onNodeWithTag("save-alarm").performClick()
        rule.onNodeWithText("Allow alarms & reminders").assertExists()
        assertTrue(rule.activity.graph.repository.state.value.alarms.isEmpty())
    }
}
