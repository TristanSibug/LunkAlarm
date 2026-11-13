package online.reeeserve.lunkalarm

import androidx.test.platform.app.InstrumentationRegistry
import online.reeeserve.lunkalarm.core.*
import org.junit.Test
import org.junit.Assert.*
import java.io.File

/** Two separate instrumentation runs, with adb install -r of a higher version between them. */
class UpgradePersistenceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val repo get() = context.graph.repository
    private val controller get() = context.graph.controller
    private val expected get() = File(context.createDeviceProtectedStorageContext().filesDir, "upgrade-expected.json")
    @Test fun seedBeforeUpgrade() {
        repo.resetForTests(context)
        val sound = File(repo.soundDirectory, "upgrade-test.wav")
        context.assets.open("sounds/classic-beep.wav").use { src -> sound.outputStream().use { src.copyTo(it) } }
        repo.update { it.copy(theme = "cobalt-coral", use24Hour = true,
            sounds = listOf(ImportedSound("upgrade-sound", "Upgrade sound", sound.name))) }
        val at = java.time.LocalTime.now().plusHours(12)
        assertTrue(controller.save(AlarmDraft(name = "Keep my alarm", hour = at.hour, minute = at.minute,
            days = setOf(2, 4, 6), tone = "upgrade-sound", volume = .6f, gradual = true,
            typing = true, codeLength = 6, mathCount = 3, mathOperations = MathOperation.entries.toSet(),
            mines = true, mineDifficulty = 1, sudoku = true, sudokuSeconds = 180, vibrate = true)))
        assertTrue(controller.save(AlarmDraft(timer = true, name = "Keep my timer", seconds = 7200)))
        assertEquals(2, repo.state.value.alarms.size)
        expected.writeText(AlarmJson.encode(repo.state.value))
    }
    @Test fun verifyAfterUpgrade() {
        assertTrue("Upgrade must preserve private files", expected.exists())
        val before = AlarmJson.decode(expected.readText())
        val after = repo.state.value
        assertFalse(repo.readOnly)
        assertEquals(before.copy(alarms = emptyList()), after.copy(alarms = emptyList()))
        assertEquals(before.alarms.map { it.id }, after.alarms.map { it.id })
        for (old in before.alarms) {
            val updated = after.alarms.single { it.id == old.id }
            if (old.draft.timer) {
                assertEquals(old, updated.copy(target = old.target))
                assertTrue("Countdown wall time should stay within clock-sampling tolerance", kotlin.math.abs(old.target - updated.target) < 2000)
            } else assertEquals(old, updated)
        }
        val sound = File(repo.soundDirectory, "upgrade-test.wav")
        assertTrue("Imported sound must survive", sound.exists())
        assertArrayEquals(context.assets.open("sounds/classic-beep.wav").use { it.readBytes() }, sound.readBytes())
        after.alarms.forEach { assertTrue(controller.remove(it)) }
        repo.resetForTests(context)
        expected.delete(); sound.delete()
    }
}
