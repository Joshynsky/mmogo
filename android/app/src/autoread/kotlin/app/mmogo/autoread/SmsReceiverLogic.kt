package app.mmogo.autoread

/** Decision logic of SmsReceiver that needs no Android class, so a plain JVM check can run it. */
internal object SmsReceiverLogic {
    /** The one place the allowed sender is typed. Exact match after trim, case-insensitive. */
    val ALLOWED_SENDERS: Set<String> = setOf("MPESA")

    fun senderAllowed(address: String?): Boolean {
        if (address == null) return false
        val a = address.trim()
        return ALLOWED_SENDERS.any { it.equals(a, ignoreCase = true) }
    }

    /**
     * How long the "message ready" heads-up waits after the SMS is stored. M-Pesa's own notification
     * lands right after the SMS and would push ours off the screen; 3 s lets it settle first. Must
     * stay well inside the receiver budget (goAsync gives roughly 10 s); the selfcheck enforces 1 to 8 s.
     */
    const val ALERT_DELAY_MS = 3000L

    /**
     * Second post of the same alert, this long after the first (about 7 s after arrival), so it pops up
     * again after the Messages app's own heads-up (seen at about 5 s on the Oppo). The whole thread
     * (ALERT_DELAY_MS + this) must stay under the receiver's ~10 s goAsync budget; the selfcheck enforces 4 to 9 s.
     */
    const val ALERT_REPEAT_AFTER_MS = 4000L

    /**
     * True when the "message ready / Tap to parse" alert goes up before anything else. False when a parse is
     * due on arrival (Ask first): the parse starts at once and its result is the first alert; the "ready" alert
     * is only the fallback if the parse cannot start or ends quietly.
     */
    fun readyAlertFirst(parseNow: Boolean): Boolean = !parseNow

    /** True for a body of 1 to HeldStore.MAX_BODY_CHARS characters. */
    fun bodyAcceptable(body: String?): Boolean =
        body != null && body.isNotEmpty() && body.length <= HeldStore.MAX_BODY_CHARS

    /**
     * Loose check for the four tracked outgoing kinds: send money / paybill ("sent to"), buy goods
     * ("paid to"), airtime ("You bought ... of airtime"), withdrawal ("Withdraw Ksh", glued to the time in real messages as "AMWithdraw", so no word
     * boundary), each after the
     * "<10-char code> Confirmed." opening. Deliberately looser than the Dart parser: it only decides
     * whether to notify, never what the message means. A false "no" is harmless (the message is still
     * held and shows under Other messages); a false "yes" is one extra notification.
     */
    private val TRACKED_KIND = Regex(
        "^\\s*[A-Z0-9]{10}\\s*confirmed\\.[\\s\\S]*?" +
            "(\\bsent to\\b|\\bpaid to\\b|\\byou bought\\b[\\s\\S]*?\\bof airtime\\b|withdraw\\s+ksh)",
        RegexOption.IGNORE_CASE,
    )

    fun trackedKind(body: String): Boolean = TRACKED_KIND.containsMatchIn(body)

    /**
     * Known NON-transaction notices that are dropped on arrival, never stored or listed (PM
     * decision 01-11-2026: a non-transaction message must not show up as "Could not read").
     * Today only the Safaricom airtime recharge notice, "Recharge of 5.00 KSH ...". Mirror of Dart
     * `isNonTransactionNotice` (lib/autoread/logic/non_transaction.dart); the two must agree.
     * A confirmation ("<code> Confirmed") or a "Failed" message is never ignored.
     */
    private val RECHARGE = Regex("^\\s*recharge\\s+of\\s+[\\d.,]+\\s*(ksh|kes)\\b", RegexOption.IGNORE_CASE)
    private val CONFIRMATION = Regex("^\\s*[A-Z0-9]{10}\\s*confirmed\\b", RegexOption.IGNORE_CASE)
    private val FAILED = Regex("\\bfailed\\b", RegexOption.IGNORE_CASE)

    fun isNonTransactionNotice(body: String): Boolean {
        if (CONFIRMATION.containsMatchIn(body)) return false
        if (FAILED.containsMatchIn(body)) return false
        return RECHARGE.containsMatchIn(body)
    }
}
