package online.reeeserve.lunkalarm

import android.Manifest
import android.app.KeyguardManager
import android.content.*
import android.net.Uri
import android.os.*
import android.provider.Settings
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.core.view.WindowInsetsControllerCompat

class MainActivity : ComponentActivity() {
    var permissionRevision by mutableIntStateOf(0); private set
    private val notifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) { permissionRevision++ }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState); enableEdgeToEdge()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        graph.controller.reschedule(null)
        setContent { MainScreen(this) }
    }
    override fun onResume() {
        super.onResume(); permissionRevision++
        if (graph.repository.state.value.session != null) { AlarmService.start(this); startActivity(RingingActivity.intent(this)) }
    }
    fun requestNotifications() {
        if (Build.VERSION.SDK_INT >= 33) notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        else startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
    }
    fun alarmPermission() {
        if (Build.VERSION.SDK_INT >= 31) startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")))
    }
    fun fullScreenPermission() {
        if (Build.VERSION.SDK_INT >= 34) startActivity(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:$packageName")))
    }
}
fun ComponentActivity.applyBars(theme: LunkTheme) {
    WindowInsetsControllerCompat(window, window.decorView).apply {
        isAppearanceLightStatusBars = theme.light; isAppearanceLightNavigationBars = theme.light
    }
}
