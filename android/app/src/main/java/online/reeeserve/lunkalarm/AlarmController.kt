package online.reeeserve.lunkalarm

import android.content.Context
import android.content.Intent
import android.os.SystemClock
import online.reeeserve.lunkalarm.core.*

class AlarmController(private val context: Context, val repository: AlarmRepository) {
    val scheduler = AlarmScheduler(context)
    private fun withError(action: () -> Unit): Boolean = try { action(); true } catch (failure: Exception) {
        repository.report(failure.localizedMessage ?: "Could not change the alarm."); false
    }
    fun save(draft: AlarmDraft, editingId: String? = null, rememberDraft: Boolean = true): Boolean = withError {
        check(scheduler.exactAllowed) { "Allow Alarms & reminders before saving an alarm." }
        check(scheduler.notificationsAllowed) { "Allow notifications so Android can display your alarm when the phone is locked." }
        val original = editingId?.let { id -> repository.state.value.alarms.firstOrNull { it.id == id } }
        check(editingId == null || original != null) { "This alarm was deleted." }
        check(original?.active != true) { "Finish the wake-up tests before editing this alarm." }
        val created = AlarmRecord.create(draft.copy(name = draft.name.trim()), System.currentTimeMillis(), SystemClock.elapsedRealtime(), scheduler.boot)
        val record = created.copy(id = original?.id ?: created.id, enabled = original?.enabled ?: true)
        install(record, original, if (rememberDraft) draft else null)
    }
    private fun install(record: AlarmRecord, original: AlarmRecord?, newDraft: AlarmDraft? = null) {
        val before = repository.state.value
        repository.update { it.copy(alarms = it.alarms.filterNot { a -> a.id == record.id } + record, draft = newDraft ?: it.draft) }
        try {
            scheduler.cancel(record.id); scheduler.schedule(record)
        } catch (failure: Exception) {
            runCatching { scheduler.cancel(record.id) }
            repository.update { it.copy(alarms = before.alarms, draft = before.draft) }
            if (original != null) runCatching { scheduler.schedule(original) }
            throw failure
        }
    }
    fun remove(record: AlarmRecord): Boolean = withError {
        check(!record.active) { "Complete the wake-up tests before deleting an active alarm." }
        scheduler.cancel(record.id)
        try { repository.update { it.copy(alarms = it.alarms.filterNot { a -> a.id == record.id }) } }
        catch (failure: Exception) { runCatching { scheduler.schedule(record) }; throw failure }
    }
    fun duplicate(record: AlarmRecord): Boolean = withError {
        install(record.duplicate(System.currentTimeMillis(), SystemClock.elapsedRealtime(), scheduler.boot), null)
    }
    fun enable(record: AlarmRecord, enabled: Boolean): Boolean = withError {
        check(!record.active)
        val copy = if (enabled) record.duplicate(System.currentTimeMillis(), SystemClock.elapsedRealtime(), scheduler.boot).copy(id = record.id, enabled = true)
            else record.copy(enabled = false, error = null)
        install(copy, record)
    }
    fun trigger(id: String) {
        val alarm = repository.state.value.alarms.firstOrNull { it.id == id && it.enabled } ?: return
        if (!alarm.active) repository.update { state ->
            val alarms = state.alarms.map { if (it.id == id) it.copy(active = true, error = null) else it }
            state.copy(alarms = alarms, session = state.session ?: AlarmSession(id, WakeChallenge.create(alarm.draft), boot = scheduler.boot))
        }
    }
    fun opened() = withError {
        val session = repository.state.value.session ?: return@withError
        val record = repository.state.value.alarms.firstOrNull { it.id == session.owner } ?: return@withError
        if (!session.opened || (record.hasTests && session.sound))
            repository.update { it.copy(session = session.copy(opened = true, sound = !record.hasTests, challenge = session.challenge.start(SystemClock.elapsedRealtime()))) }
    }
    fun sound(enabled: Boolean) = withError {
        repository.update { it.copy(session = it.session?.copy(sound = enabled)) }
    }
    fun submit(text: String, typing: Boolean): AnswerResult {
        val session = repository.state.value.session ?: return AnswerResult.INCOMPLETE
        if (!session.opened) return AnswerResult.INCOMPLETE
        val result = if (typing) session.challenge.submitCode(text, SystemClock.elapsedRealtime()) else session.challenge.submitDigits(text, SystemClock.elapsedRealtime())
        if (!withError { repository.update { it.copy(session = session.copy(challenge = result.challenge,
                sound = session.sound || result.result == AnswerResult.TIMED_OUT)) } }) return AnswerResult.INCOMPLETE
        return result.result
    }
    fun placePiece(piece: Int): AnswerResult {
        val session = repository.state.value.session ?: return AnswerResult.INCOMPLETE
        if (!session.opened) return AnswerResult.INCOMPLETE
        val result = session.challenge.placePiece(piece, SystemClock.elapsedRealtime())
        if (!withError { repository.update { it.copy(session = session.copy(challenge = result.challenge,
                sound = session.sound || result.result == AnswerResult.TIMED_OUT)) } }) return AnswerResult.INCOMPLETE
        return result.result
    }
    fun mineAction(cell: Int, flag: Boolean) = gameAction { it.mineAction(cell, flag, SystemClock.elapsedRealtime()) }
    fun sudokuAction(cell: Int, digit: Int) = gameAction { it.sudokuAction(cell, digit, SystemClock.elapsedRealtime()) }
    private fun gameAction(action: (WakeChallenge) -> Submission): AnswerResult {
        val session = repository.state.value.session ?: return AnswerResult.INCOMPLETE
        if (!session.opened) return AnswerResult.INCOMPLETE
        val result = action(session.challenge)
        if (!withError { repository.update { it.copy(session = session.copy(challenge = result.challenge,
            sound = session.sound || result.challenge.resets != session.challenge.resets)) } }) return AnswerResult.INCOMPLETE
        return result.result
    }
    fun tick() {
        val session = repository.state.value.session ?: return
        val expired = session.challenge.expire(SystemClock.elapsedRealtime())
        if (expired != session.challenge) withError { repository.update { it.copy(session = session.copy(challenge = expired, sound = true)) } }
    }
    fun finish(): Boolean = withError {
        val state = repository.state.value
        val session = state.session ?: return@withError
        val record = state.alarms.firstOrNull { it.id == session.owner } ?: return@withError
        check(!record.hasTests || (session.opened && session.challenge.complete)) { "Finish the wake-up tests to stop the alarm." }
        scheduler.cancel(record.id)
        val replacement = if (record.draft.timer) null else record.copy(active = false, enabled = record.draft.days.isNotEmpty(),
            target = AlarmTime.next(record.draft.hour, record.draft.minute, record.draft.days, System.currentTimeMillis()), error = null)
        val remaining = state.alarms.filterNot { it.id == record.id } + listOfNotNull(replacement)
        val next = remaining.filter { it.active }.minByOrNull { it.target }
        repository.update { it.copy(alarms = remaining, session = next?.let { a -> AlarmSession(a.id, WakeChallenge.create(a.draft), boot = scheduler.boot) }) }
        if (replacement?.enabled == true) try { scheduler.schedule(replacement) } catch (failure: Exception) {
            repository.update { it.copy(alarms = it.alarms.map { a -> if (a.id == replacement.id) a.copy(error = "Not scheduled. Edit and save to retry.") else a }) }
            throw failure
        }
    }
    fun reschedule(action: String?) = withError {
        if (repository.readOnly) return@withError
        val now = System.currentTimeMillis(); val elapsed = SystemClock.elapsedRealtime()
        val records = repository.state.value.alarms.map { alarm ->
            if (!alarm.enabled || alarm.active) alarm
            else if (alarm.draft.timer) {
                val remaining = alarm.remaining(now, elapsed, scheduler.boot).coerceAtLeast(1000)
                alarm.copy(target = now + remaining, elapsedTarget = elapsed + remaining, boot = scheduler.boot)
            } else if (action == Intent.ACTION_TIME_CHANGED || action == Intent.ACTION_TIMEZONE_CHANGED) {
                alarm.copy(target = AlarmTime.next(alarm.draft.hour, alarm.draft.minute, alarm.draft.days, now))
            } else alarm
        }
        repository.update { state ->
            val session = state.session
            val owner = records.firstOrNull { it.id == session?.owner }
            val restored = if (session != null && owner != null && session.boot != scheduler.boot)
                AlarmSession(owner.id, WakeChallenge.create(owner.draft), boot = scheduler.boot) else session
            state.copy(alarms = records, session = restored)
        }
        for (alarm in records.filter { it.enabled }) try { scheduler.schedule(alarm) } catch (failure: Exception) {
            repository.update { it.copy(alarms = it.alarms.map { a -> if (a.id == alarm.id) a.copy(error = "Not scheduled. Edit and save to retry.") else a }) }
            repository.report(failure.localizedMessage)
        }
    }
}
