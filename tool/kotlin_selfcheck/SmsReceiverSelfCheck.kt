package app.mmogo.autoread

/** Plain-JVM check of SmsReceiverLogic, run by tool/kotlin_selfcheck/run.ps1. Not part of the app. */
internal object SmsReceiverSelfCheck {
    /** The failed checks; empty means every check passed. */
    fun runAll(): List<String> {
        val fails = ArrayList<String>()
        fun check(name: String, ok: Boolean) {
            if (!ok) fails.add(name)
        }

        check("MPESA allowed", SmsReceiverLogic.senderAllowed("MPESA"))
        check("padded lowercase allowed", SmsReceiverLogic.senderAllowed(" mpesa "))
        check("MPesa allowed", SmsReceiverLogic.senderAllowed("MPesa"))
        check("trailing newline trimmed, allowed", SmsReceiverLogic.senderAllowed("MPESA\n"))
        check("MPESA1 rejected", !SmsReceiverLogic.senderAllowed("MPESA1"))
        check("XMPESA rejected", !SmsReceiverLogic.senderAllowed("XMPESA"))
        check("M-PESA rejected", !SmsReceiverLogic.senderAllowed("M-PESA"))
        check("MPE SA rejected", !SmsReceiverLogic.senderAllowed("MPE SA"))
        check("empty rejected", !SmsReceiverLogic.senderAllowed(""))
        check("null rejected", !SmsReceiverLogic.senderAllowed(null))
        check("Safaricom rejected", !SmsReceiverLogic.senderAllowed("Safaricom"))

        check("null body rejected", !SmsReceiverLogic.bodyAcceptable(null))
        check("empty body rejected", !SmsReceiverLogic.bodyAcceptable(""))
        check("2001 chars rejected", !SmsReceiverLogic.bodyAcceptable("a".repeat(2001)))
        check("1 char accepted", SmsReceiverLogic.bodyAcceptable("a"))
        check("2000 chars accepted", SmsReceiverLogic.bodyAcceptable("a".repeat(2000)))

        return fails
    }
}
