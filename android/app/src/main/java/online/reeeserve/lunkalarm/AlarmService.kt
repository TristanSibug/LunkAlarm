package online.reeeserve.lunkalarm

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.*
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import online.reeeserve.lunkalarm.core.*

class AlarmService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val handler = Handler(Looper.getMainLooper())
    private val repo get() = graph.repository
    private val controller get() = graph.controller
    private lateinit var audio: AlarmAudio
    private var audioOwner: String? = null
    private var shownOwner: String? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var renewAt = 0L
    private val tick = object : Runnable {
        override fun run() {
            if (repo.state.value.session == null) return
            controller.tick(); audio.tick()
            if (SystemClock.elapsedRealtime() >= renewAt) acquireWakeLock()
            handler.postDelayed(this, 250)
        }
    }
    override fun onCreate() {
        super.onCreate(); audio = AlarmAudio(this, repo); current = this
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "Ringing alarms", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Active LunkAlarm alarms and wake-up tests"
                setSound(null, null); enableVibration(false); lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            })
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val session = repo.state.value.session
        if (session == null) { stopSelf(); return START_NOT_STICKY }
        foreground(notification(session, true))
        if (intent?.action == STOP) controller.finish()
        if (wakeLock == null) acquireWakeLock()
        if (shownOwner == null) {
            scope.launch { repo.state.collect { state ->
                val current = state.session
                if (current == null) { audio.stop(); stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); return@collect }
                val alarm = state.alarms.firstOrNull { it.id == current.owner } ?: return@collect
                if (alarm.hasTests && current.opened && current.challenge.complete) { controller.finish(); return@collect }
                val fresh = shownOwner != current.owner
                shownOwner = current.owner
                foreground(notification(current, fresh))
                val key = if (current.sound) "${current.owner}:${alarm.draft.tone}:${alarm.draft.volume}:${alarm.draft.gradual}" else null
                if (key != audioOwner) {
                    audio.stop(); audioOwner = key
                    if (key != null) try { audio.play(alarm.draft.tone, alarm.draft.volume, alarm.draft.gradual, fallback = true) }
                    catch (failure: Exception) { repo.report("Alarm audio could not play. Check your device alarm volume. ${failure.localizedMessage}") }
                }
            } }
            handler.removeCallbacks(tick); handler.post(tick)
        }
        return START_STICKY
    }
    private fun foreground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        else startForeground(NOTIFICATION, notification)
    }
    private fun notification(session: AlarmSession, fullScreen: Boolean): Notification {
        val alarm = repo.state.value.alarms.first { it.id == session.owner }
        val open = PendingIntent.getActivity(this, 0, RingingActivity.intent(this), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL).setSmallIcon(R.drawable.ic_alarm)
            .setContentTitle(alarm.label).setContentText(if (alarm.hasTests) "Open LunkAlarm to finish wake-up tests" else "Your alarm is ringing")
            .setCategory(NotificationCompat.CATEGORY_ALARM).setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC).setOngoing(true).setAutoCancel(false).setOnlyAlertOnce(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE).setContentIntent(open)
            .apply {
                if (fullScreen && controller.scheduler.fullScreenAllowed) setFullScreenIntent(open, true)
                if (!alarm.hasTests) addAction(0, "Stop", PendingIntent.getService(this@AlarmService, 1,
                    Intent(this@AlarmService, AlarmService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            }.build()
    }
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "LunkAlarm:ActiveAlarm").apply { acquire(10 * 60 * 1000L) }
        renewAt = SystemClock.elapsedRealtime() + 5 * 60 * 1000L
    }
    override fun onDestroy() {
        handler.removeCallbacks(tick); scope.cancel(); audio.stop()
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null; current = null; super.onDestroy()
    }
    override fun onBind(intent: Intent?) = null
    companion object {
        @Volatile private var current: AlarmService? = null
        internal val isPlaying: Boolean get() = current?.audio?.isPlaying == true
        const val CHANNEL = "lunkalarm-ringing"
        private const val NOTIFICATION = 41
        private const val STOP = "online.reeeserve.lunkalarm.STOP"
        fun start(context: Context) { ContextCompat.startForegroundService(context, Intent(context, AlarmService::class.java)) }
    }
}
