package app.mmogo.autoread

import android.content.Context

/** Read side of the auto-read switch (the writer arrives with K4). Default off. */
object AutoReadSwitch {
    private const val PREFS = "mmogo_autoread"
    private const val KEY_ENABLED = "enabled"

    fun isOn(context: Context): Boolean =
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, false)
        } catch (_: Throwable) {
            false
        }
}
