package app.mmogo.autoread

import android.content.Context

/** The auto-read switch: reader (K3) and writer (K4a). Default off. */
object AutoReadSwitch {
    private const val PREFS = "mmogo_autoread"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_CONSENT = "consent_version"
    private const val KEY_PARSE = "parse_from_notification"

    /** The consent version the user agreed to (0 when none). Kept in this file, on this side. */
    fun consentVersion(context: Context): Int =
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getInt(KEY_CONSENT, 0)
        } catch (_: Throwable) {
            0
        }

    /** Stores [version] only when it is the current consent version; true when the current one is held now. */
    fun setConsentVersion(context: Context, version: Int): Boolean =
        try {
            if (ConsentGate.isCurrent(version)) {
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putInt(KEY_CONSENT, version).commit()
            }
            ConsentGate.isCurrent(consentVersion(context))
        } catch (_: Throwable) {
            false
        }

    fun hasCurrentConsent(context: Context): Boolean = ConsentGate.isCurrent(consentVersion(context))

    /** "Parse from the notification" switch; off until the user's consent screen sets it. */
    fun parseOn(context: Context): Boolean =
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_PARSE, false)
        } catch (_: Throwable) {
            false
        }

    fun setParseOn(context: Context, on: Boolean): Boolean =
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_PARSE, on).commit()
        } catch (_: Throwable) {
            false
        }

    /**
     * The Dart generation counter (Off and Delete data bump it), read from the shared_preferences file.
     * Absent counts as 0, like Dart; null when it cannot be read. Used to refuse an ack after a bump.
     */
    fun pendingGeneration(context: Context): Long? =
        try {
            val p = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            if (p.contains(ParsePolicy.GENERATION_KEY)) p.getLong(ParsePolicy.GENERATION_KEY, 0L) else 0L
        } catch (_: Throwable) {
            null
        }

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
