package app.mmogo.autoread

import android.content.Context

/**
 * Android glue of [AskStore]: the few reads and the one write Ask first needs in the plugin's preference
 * file (the file Dart's shared_preferences uses, so the app sees the write after its next reload).
 * Every function fails closed (false or null) and never throws. No logging.
 */
internal object AskFirstPrefs {
    private fun flutter(ctx: Context) = ctx.getSharedPreferences(AskStore.FLUTTER_PREFS, Context.MODE_PRIVATE)

    /** True when some stored rule is Ask first. Cheap: one pass over at most about 300 small keys. */
    fun anyAskFirstRule(ctx: Context): Boolean =
        try {
            ArrivalParse.anyAskFirst(
                flutter(ctx).all.filterKeys { it.startsWith(ArrivalParse.RULE_KEY_PREFIX) }.values.map { it as? String },
            )
        } catch (_: Throwable) {
            false
        }

    /** "Record receiver details" (default ON when absent, like Dart). Unreadable counts as OFF: nothing starts. */
    fun receiverDetailsOn(ctx: Context): Boolean =
        try {
            flutter(ctx).getBoolean(AskStore.DETAILS_KEY, true)
        } catch (_: Throwable) {
            false
        }

    /** The stored name of category [id] for the alert, or null. */
    fun categoryName(ctx: Context, id: Long): String? =
        try {
            AskStore.categoryName(flutter(ctx).getString(AskStore.NAMES_KEY, null), id)
        } catch (_: Throwable) {
            null
        }

    /**
     * Records that the user tapped Yes for [heldId]: one key holding the tap time, written with commit().
     * Only when the stored waiting item still carries an Ask first hint with a category; otherwise false and
     * nothing is written. The app decides what to record (from its own copy of the hint) when it next opens.
     */
    fun writeYes(ctx: Context, heldId: String, nowMs: Long): Boolean =
        try {
            if (!HeldId.isValid(heldId)) {
                false
            } else {
                val p = flutter(ctx)
                if (!AskStore.itemAsksFirst(p.getString(AskStore.PENDING_PREFIX + heldId, null))) {
                    false
                } else {
                    p.edit().putLong(AskStore.yesKey(heldId), nowMs).commit()
                }
            }
        } catch (_: Throwable) {
            false
        }
}
