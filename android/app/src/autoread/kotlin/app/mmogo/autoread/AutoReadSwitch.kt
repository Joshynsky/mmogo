package app.mmogo.autoread

import android.content.Context

/** The auto-read switch: reader (K3) and writer (K4a). Default off. */
object AutoReadSwitch {
    private const val PREFS = "mmogo_autoread"
    private const val KEY_ENABLED = "enabled"

    fun isOn(context: Context): Boolean =
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, false)
        } catch (_: Throwable) {
            false
        }

    /** Writes the switch with commit(); true when the write succeeded. */
    fun setEnabled(context: Context, enabled: Boolean): Boolean =
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ENABLED, enabled).commit()
        } catch (_: Throwable) {
            false
        }
}
