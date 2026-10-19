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
}
