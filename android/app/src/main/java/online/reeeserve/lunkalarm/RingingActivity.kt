package online.reeeserve.lunkalarm

import android.app.KeyguardManager
import android.content.*
import android.os.Bundle
import android.os.Build
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.*
import androidx.core.content.ContextCompat

class RingingActivity : ComponentActivity() {
    var locked by mutableStateOf(true); private set
    private val present = object : BroadcastReceiver() { override fun onReceive(context: Context, intent: Intent) { refreshLock() } }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState); enableEdgeToEdge()
        if (Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(true); setTurnScreenOn(true) }
        else { @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        locked = getSystemService(KeyguardManager::class.java).isKeyguardLocked
        setContent { RingingScreen(this) }
    }
    override fun onStart() { super.onStart(); ContextCompat.registerReceiver(this, present, IntentFilter(Intent.ACTION_USER_PRESENT), ContextCompat.RECEIVER_NOT_EXPORTED) }
    override fun onStop() { unregisterReceiver(present); super.onStop() }
    override fun onResume() {
        super.onResume()
        if (graph.repository.state.value.session == null) { finish(); return }
        AlarmService.start(this); refreshLock()
    }
    private fun refreshLock() {
        locked = getSystemService(KeyguardManager::class.java).isKeyguardLocked
        if (!locked) graph.controller.opened()
    }
    fun unlock() {
        getSystemService(KeyguardManager::class.java).requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
            override fun onDismissSucceeded() { refreshLock() }
            override fun onDismissCancelled() { refreshLock() }
            override fun onDismissError() { refreshLock() }
        })
    }
    companion object {
        fun intent(context: Context) = Intent(context, RingingActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    }
}
