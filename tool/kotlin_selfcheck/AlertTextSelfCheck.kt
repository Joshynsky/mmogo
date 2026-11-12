package app.mmogo.autoread

/** Plain-JVM check of AlertText (0.2.0 S10), run by tool/kotlin_selfcheck/run.ps1. Invented messages only. */
internal object AlertTextSelfCheck {
    fun runAll(): List<String> {
        val fails = ArrayList<String>()
        fun check(name: String, ok: Boolean) {
            if (!ok) fails.add(name)
        }
        val gt = "M-Pesa message received"
        val gx = "An M-Pesa message is waiting. Tap to parse it."

        // The default is Generic (binding until the Judge note J1 is signed).
        check("default is Generic", AlertText.DEFAULT_SHOW_DETAILS == false)
        check("bridge state default is Generic", BridgeLogic.stateResult(false, false, false, 0)["alertDetails"] == false)

        // J1 B3: only a details alert times out early; a generic one keeps the held window.
        check("details timeout is 15 min", AlertText.DETAILS_TIMEOUT_MS == 900_000L)
        check("details alert gets the short timeout", AlertText.timeoutMs(false, HeldWindow.WINDOW_MS) == 900_000L)
        check("generic alert keeps the held window", AlertText.timeoutMs(true, HeldWindow.WINDOW_MS) == HeldWindow.WINDOW_MS)
        check("state absent flag defaults false and carries", BridgeLogic.stateResult(false, false, false, 0)["alertDetailsAbsent"] == false &&
            BridgeLogic.stateResult(false, false, false, 0, alertDetailsAbsent = true)["alertDetailsAbsent"] == true)

        val sent = "ZZ11AA22BB Confirmed. Ksh500.00 sent to JANE WANJIKU 0700000001 on 3/11/26 at 10:15 AM. New M-PESA balance is Ksh9,999.00. Transaction cost, Ksh7.00."
        val paid = "ZZ11AA22BC Confirmed. Ksh1,250.50 paid to KPLC PREPAID. on 3/11/26 at 11:00 AM.New M-PESA balance is Ksh8,000.00."
        val recv = "ZZ11AA22BD Confirmed.You have received Ksh2,000.00 from JOHN DOE 0700000002 on 3/11/26 at 12:00 PM  New M-PESA balance is Ksh12,000.00."
        val air = "ZZ11AA22BE confirmed. You bought Ksh50.00 of airtime on 3/11/26 at 1:00 PM.New M-PESA balance is Ksh100.00."

        // Generic mode never reads the body.
        val g = AlertText.choose(false, sent, true, gt, gx)
        check("generic mode keeps generic words", g.generic && g.title == gt && g.text == gx)

        val d1 = AlertText.choose(true, sent, true, gt, gx)
        check("sent title (got ${d1.title})", d1.title == "Sent Ksh 500 to JANE WANJIKU" && !d1.generic)
        check("sent second line, parse on", d1.text == AlertText.DETAILS_LINE_PARSE)
        check("sent second line, parse off", AlertText.choose(true, sent, false, gt, gx).text == AlertText.DETAILS_LINE_OPEN)
        val d2 = AlertText.choose(true, paid, true, gt, gx)
        check("paid title (got ${d2.title})", d2.title == "Paid Ksh 1,250.50 to KPLC PREPAID")
        val d3 = AlertText.choose(true, recv, true, gt, gx)
        check("received title (got ${d3.title})", d3.title == "Received Ksh 2,000 from JOHN DOE")
        val d4 = AlertText.choose(true, air, true, gt, gx)
        check("airtime title (got ${d4.title})", d4.title == "Bought airtime Ksh 50")

        // No code, phone number, balance or fee ever reaches the text.
        for (b in listOf(sent, paid, recv, air)) {
            val t = AlertText.choose(true, b, true, gt, gx)
            val all = t.title + " " + t.text
            check("no code in: $all", !all.contains("ZZ11AA22"))
            check("no phone in: $all", !Regex("[0-9]{7,}").containsMatchIn(all))
            check("no balance in: $all", !all.contains("balance", true) && !all.contains("9,999") && !all.contains("12,000") && !all.contains("8,000"))
        }

        // A locked phone gets Generic even with details on.
        val lk = AlertText.choose(true, sent, true, gt, gx, deviceLocked = true)
        check("locked phone is generic", lk.generic && lk.title == gt && lk.text == gx)
        check("unlocked phone still gets details", !AlertText.choose(true, sent, true, gt, gx, deviceLocked = false).generic)

        // Unrecognised, empty or missing body falls back to Generic, even with details on.
        for (b in listOf<String?>(null, "", "hello", "Fuliza M-PESA limit is Ksh 3,000", "Ksh 500 something else")) {
            val t = AlertText.choose(true, b, true, gt, gx)
            check("fallback generic for '$b'", t.generic && t.title == gt && t.text == gx)
        }
        // A very long name is cut.
        val longName = "ZZ11 Confirmed. Ksh10.00 sent to " + "A".repeat(80) + " 0700000003 on 3/11/26"
        check("long name cut", AlertText.choose(true, longName, true, gt, gx).title.length <= "Sent Ksh 10 to ".length + 30)
        check("money 5 digits", AlertText.money("12345.5") == "Ksh 12,345.5")
        // WBS row 4: the line after Parse (wording B). The count leaves queued airtime out.
        val wl = { n: Int -> "Parsed. $n waiting for a category." }
        check("parsed: ordinary item", AlertText.parsedText(2, null, true, wl) == "Parsed. 2 waiting for a category.")
        check("parsed: ordinary keeps buttons", AlertText.parsedHasButtons(1, null))
        check("queued, details, none waiting", AlertText.parsedText(0, 1000, true, wl) == "Parsed. Ksh 10 airtime is queued for recording.")
        check("queued, generic hides amount", AlertText.parsedText(0, 1000, false, wl) == "Parsed. Your airtime is queued for recording.")
        check("queued, generic, none waiting has no digit", AlertText.parsedText(0, 1000, false, wl).none { it.isDigit() })
        check("queued with count", AlertText.parsedText(2, 1000, true, wl) == "Parsed. Ksh 10 airtime is queued for recording. 2 waiting for a category.")
        check("queued with one", AlertText.parsedText(1, 1000, true, wl).endsWith(" 1 waiting for a category."))
        check("queued, one waiting generic", AlertText.parsedText(1, 550, false, wl).startsWith("Parsed. Your airtime is queued for recording."))
        check("queued amount with cents", AlertText.parsedText(0, 12550, true, wl) == "Parsed. Ksh 125.50 airtime is queued for recording.")
        check("queued, none waiting: no buttons", !AlertText.parsedHasButtons(0, 1000))
        check("queued, some waiting: buttons", AlertText.parsedHasButtons(2, 1000))
        check("queued arg", ParsePolicy.queuedCentsArg(mapOf("queuedAirtimeCents" to 1000)) == 1000L)
        check("queued arg missing", ParsePolicy.queuedCentsArg(mapOf("waiting" to 1)) == null)
        check("queued arg negative", ParsePolicy.queuedCentsArg(mapOf("queuedAirtimeCents" to -1)) == null)
        check("queued arg string", ParsePolicy.queuedCentsArg(mapOf("queuedAirtimeCents" to "10")) == null)
        return fails
    }
}
