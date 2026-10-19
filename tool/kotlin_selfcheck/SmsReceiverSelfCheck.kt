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

        fun tracked(s: String) = SmsReceiverLogic.trackedKind(s)
        check("send money recognised", tracked("POI1U2Y3T4 Confirmed. Ksh150.00 sent to JOHN KAMAU 0712345678 on 8/10/26 at 4:45 PM. New M-PESA balance is Ksh800.00."))
        check("paybill recognised", tracked("ZXC1V2B3N4 Confirmed. Ksh1,200.00 sent to SAMPLE POWER CO for account 464332 on 8/10/26 at 4:45 PM."))
        check("buy goods recognised", tracked("UHL8E3PJ8Y Confirmed. Ksh50.00 paid to JAVA HOUSE. on 31/2/26 at 10:52 AM."))
        check("airtime recognised", tracked("TEJ4VG53X1 Confirmed. You bought Ksh104.00 of airtime on 21/5/24 at 5:57 AM."))
        check("airtime no space after Confirmed", tracked("PT8N4W7Q2K confirmed.You bought Ksh200.00 of airtime on 31/10/25 at 5:57 AM."))
        check("withdrawal recognised", tracked("ABC1D2E3F4 Confirmed.on 8/10/26 at 9:15 AMWithdraw Ksh2,000.00 from 1234567 - SAMPLE AGENT New M-PESA balance is Ksh4,100.00."))
        check("money in is quiet", !tracked("QWE1R2T3Y4 Confirmed. You have received Ksh500.00 from JANE DOE 0712345678 on 8/10/26 at 9:15 AM. New M-PESA balance is Ksh900.00."))
        check("balance reply is quiet", !tracked("Your M-PESA balance was Ksh1,000.00 on 8/10/26 at 9:15 AM."))
        check("agent-side Take cash is quiet", !tracked("XYZ1A2B3C4 Confirmed. On 21/4/24 at 10:12 PM Take Ksh297.00 cash from SOME PERSON Your M-PESA float balance is Ksh10.00."))
        check("Fuliza notice is quiet", !tracked("ABC1D2E3F4 Confirmed. Fuliza M-PESA amount is Ksh 500.00. Interest charged Ksh 5.00."))
        check("promo mentioning sent to is quiet", !tracked("Dear customer, a message was sent to you. Dial *334# for M-PESA."))
        check("no code line is quiet", !tracked("Confirmed. Ksh150.00 sent to JOHN KAMAU"))
        check("empty is quiet", !tracked(""))

        return fails
    }
}
