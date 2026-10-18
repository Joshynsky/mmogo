package app.mmogo.autoread

/**
 * Pure helpers for Notifier (no Android classes), so they can be checked on a plain JVM.
 * Notifier calls these; nothing else does. The JVM check for them is tool/kotlin_selfcheck/NotifierSelfCheck.kt.
 */
internal object NotifierPure {
    /** Tiny view of an intent: the only thing heldIdFrom needs is the string extra. */
    interface ExtraSource {
        fun heldIdExtra(): String?
    }

    /** Stable positive notification id: first 8 hex characters of a valid held id. */
    fun notificationId(heldId: String): Int =
        (heldId.substring(0, 8).toLong(16).toInt()) and 0x7fffffff

    /** The extra only when it is a valid held id, else null. */
    fun validated(source: ExtraSource?): String? {
        val id = source?.heldIdExtra()
        return if (HeldId.isValid(id)) id else null
    }
}
