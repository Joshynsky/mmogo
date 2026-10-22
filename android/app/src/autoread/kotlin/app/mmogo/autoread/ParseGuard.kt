package app.mmogo.autoread

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/**
 * Kotlin's own check before the Parse button is shown and again before the engine starts: the Read
 * switch, the CURRENT consent and the SMS permission ([CaptureGuard]) AND the "Parse from the
 * notification" switch. Whatever Dart last said, a missing one means no button and no engine.
 */
object ParseGuard {
    fun mayParse(context: Context): Boolean =
        ParsePolicy.mayParse(CaptureGuard.mayCapture(context), AutoReadSwitch.parseOn(context))
}

/**
 * The Parse receiver is declared disabled in the manifest. It is enabled while the Parse switch is on
 * (the switch write and every notification that shows the button make sure of it) and disabled when the
 * switch goes off. A disabled receiver cannot be started by anything.
 */
object ParseComponent {
    private fun name(context: Context) = ComponentName(context, ParseActionReceiver::class.java)

    fun ensureEnabled(context: Context) {
        try {
            val pm = context.packageManager
            if (pm.getComponentEnabledSetting(name(context)) != PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                pm.setComponentEnabledSetting(name(context), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
            }
        } catch (_: Throwable) {
        }
    }

    fun setEnabled(context: Context, enabled: Boolean) {
        try {
            val state = if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            context.packageManager.setComponentEnabledSetting(name(context), state, PackageManager.DONT_KILL_APP)
        } catch (_: Throwable) {
        }
    }
}
