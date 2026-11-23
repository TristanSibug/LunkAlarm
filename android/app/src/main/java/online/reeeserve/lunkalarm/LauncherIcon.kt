package online.reeeserve.lunkalarm

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.DrawableRes

enum class LauncherIcon(@get:DrawableRes val artwork: Int) {
    LIGHT(R.drawable.app_icon_light),
    EGGSHELL_WHITE(R.drawable.app_icon_eggshell_white),
    LINEN(R.drawable.app_icon_linen),
    SEA_GLASS(R.drawable.app_icon_sea_glass),
    HERITAGE(R.drawable.app_icon_heritage),
    OLED(R.drawable.app_icon_oled),
    DARK(R.drawable.app_icon_dark),
    SUNRISE(R.drawable.app_icon_sunrise),
    EMBER(R.drawable.app_icon_ember),
    MIDNIGHT_CHERRY(R.drawable.app_icon_midnight_cherry),
    FOREST(R.drawable.app_icon_forest),
    NORD(R.drawable.app_icon_nord),
    DEEP_OCEAN(R.drawable.app_icon_deep_ocean),
    COBALT_CORAL(R.drawable.app_icon_cobalt_coral),
    SIGNAL_BLUE(R.drawable.app_icon_signal_blue),
    TOKYO_NIGHT(R.drawable.app_icon_tokyo_night),
    AMETHYST(R.drawable.app_icon_amethyst),
    DRACULA(R.drawable.app_icon_dracula);

    val id: String get() = name.lowercase().replace('_', '-')
    val title: String get() = Themes.find(id).name

    private fun component(context: Context) =
        ComponentName(context.packageName, "${context.packageName}.launcher.${name.lowercase()}")

    private fun isEnabled(context: Context): Boolean =
        when (context.packageManager.getComponentEnabledSetting(component(context))) {
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> this == SUNRISE
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            else -> false
        }

    fun select(context: Context) {
        val manager = context.packageManager
        val enabled = entries.filter { it.isEnabled(context) }
        if (enabled == listOf(this)) return

        val disable = enabled.filter { it != this }
        // Keep the actual MainActivity available to alarm intents and shortcuts.
        // Android 13+ switches both launcher components in one operation.
        if (Build.VERSION.SDK_INT >= 33) {
            val updates = buildList {
                if (this@LauncherIcon !in enabled) add(PackageManager.ComponentEnabledSetting(
                    component(context), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP
                ))
                disable.forEach { icon ->
                    add(PackageManager.ComponentEnabledSetting(
                        icon.component(context), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP
                    ))
                }
            }
            manager.setComponentEnabledSettings(updates)
        } else {
            // Enable the replacement before disabling the previous icon so the
            // app always has a working launcher entry.
            manager.setComponentEnabledSetting(component(context),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
            disable.forEach { icon ->
                manager.setComponentEnabledSetting(icon.component(context),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
            }
        }
    }

    companion object {
        fun selected(context: Context): LauncherIcon = entries.firstOrNull { it.isEnabled(context) } ?: SUNRISE
    }
}
