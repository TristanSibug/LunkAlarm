package online.reeeserve.lunkalarm

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.*
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import androidx.core.content.ContextCompat
import online.reeeserve.lunkalarm.core.*

class AlarmScheduler(private val context: Context) {
    private val manager get() = context.getSystemService(AlarmManager::class.java)
    val exactAllowed get() = Build.VERSION.SDK_INT < 31 || manager.canScheduleExactAlarms()
    val notificationsAllowed get() = context.getSystemService(NotificationManager::class.java).areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
    val fullScreenAllowed get() = Build.VERSION.SDK_INT < 34 || context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
    val boot: Int get() = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
    private fun alarmIntent(id: String, flags: Int): PendingIntent? = PendingIntent.getBroadcast(context, 0,
        Intent(context, AlarmReceiver::class.java).setAction("online.reeeserve.lunkalarm.FIRE")
            .setData(Uri.parse("lunkalarm://alarms/$id")).putExtra("id", id), flags or PendingIntent.FLAG_IMMUTABLE)
    fun schedule(alarm: AlarmRecord) {
        if (!alarm.enabled) return
        check(exactAllowed) { "Allow Alarms & reminders for LunkAlarm, then save your alarm again." }
        val pending = checkNotNull(alarmIntent(alarm.id, PendingIntent.FLAG_UPDATE_CURRENT))
        if (alarm.active || alarm.draft.timer) {
            val remaining = if (alarm.active) 1500 else alarm.remaining(System.currentTimeMillis(), SystemClock.elapsedRealtime(), boot).coerceAtLeast(1000)
            manager.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, SystemClock.elapsedRealtime() + remaining, pending)
        } else {
            val show = PendingIntent.getActivity(context, 1, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            manager.setAlarmClock(AlarmManager.AlarmClockInfo(alarm.target.coerceAtLeast(System.currentTimeMillis() + 1000), show), pending)
        }
    }
    fun cancel(id: String) { alarmIntent(id, PendingIntent.FLAG_NO_CREATE)?.let { manager.cancel(it); it.cancel() } }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("id") ?: return
        try {
            context.graph.controller.trigger(id)
            if (context.graph.repository.state.value.session != null) AlarmService.start(context)
        } catch (failure: Exception) { context.graph.repository.report("Could not start alarm: ${failure.localizedMessage}") }
    }
}
class RescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { context.graph.controller.reschedule(intent.action) }
}
