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
}
