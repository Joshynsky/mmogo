package app.mmogo.autoread

import java.security.SecureRandom

/**
 * §AUTOREAD.HELD_ID (contract, 19-10-2026). The one definition of a held-message id and of the
 * held window on the Kotlin side. Everything that touches an id (HeldStore, Notifier, the
 * bridge, SmsReceiver) uses these; nobody retypes the pattern or the hours.
 *
 * Mirrors lib/autoread/held_window.dart (kHeldWindow 24 h, kHeldClockSkew 5 min, heldExpired)
 * and isValidHeldId in lib/autoread/model/waiting_item.dart (32 lowercase hex characters).
 * If one side changes, the other changes in the same slice.
 */
object HeldId {
    private val PATTERN = Regex("^[0-9a-f]{32}$")

    /** True only for exactly 32 lowercase hex characters. Null and anything else is false. */
    fun isValid(id: String?): Boolean = id != null && PATTERN.matches(id)

    /** A fresh random 128-bit id from [random], as 32 lowercase hex characters. */
    fun random(random: SecureRandom = SecureRandom()): String {
        val bytes = ByteArray(16)
        random.nextBytes(bytes)
        val sb = StringBuilder(32)
        for (b in bytes) {
            val v = b.toInt() and 0xff
            sb.append("0123456789abcdef"[v ushr 4]).append("0123456789abcdef"[v and 0x0f])
        }
        return sb.toString()
    }
}

object HeldWindow {
    /** The held window: the ONLY place the hours are typed in Kotlin. */
    const val WINDOW_MS: Long = 24L * 60L * 60L * 1000L

    /** A stamp further in the future than this counts as expired (a clock set back must not keep an item alive). */
    const val CLOCK_SKEW_MS: Long = 5L * 60L * 1000L

    /** True when the item is gone: held the whole window or longer, or stamped in the future beyond the skew. */
    fun expired(heldAtMs: Long, nowMs: Long): Boolean {
        val age = nowMs - heldAtMs
        if (age >= WINDOW_MS) return true
        if (-age > CLOCK_SKEW_MS) return true
        return false
    }
}
