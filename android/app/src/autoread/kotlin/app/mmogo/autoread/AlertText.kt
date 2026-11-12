package app.mmogo.autoread

/**
 * §AUTOREAD.ALERTTEXT (0.2.0 S10). Pure (no Android classes): what the "a message is ready"
 * alert may say. Two modes, chosen by the "What alerts show" setting:
 *  - Generic (the DEFAULT, and the only thing the lock screen ever gets): no amount, no name.
 *  - Show details: one short line (kind, amount, and the other party's name). Never the M-Pesa
 *    code, a phone number, the balance, a fee or the rest of the body.
 * The default stays Generic until the Judge/Security note J1 is signed (DRAFT only today).
 * A body that is not recognised falls back to Generic, and so does any alert posted while the phone is
 * locked. Nothing here logs.
 */
internal object AlertText {
    /** "What alerts show": false = Generic. Do NOT change without a signed J1 (a test pins this). */
    const val DEFAULT_SHOW_DETAILS = false

    private const val MAX_NAME = 30

    /** [title] and [text] of one alert; [generic] is true when no detail was used. */
    data class Text(val title: String, val text: String, val generic: Boolean)

    // WORDING-DRAFT (details mode second line); the generic words live in strings.xml.
    const val DETAILS_LINE_PARSE = "Tap Parse to record it."
    const val DETAILS_LINE_OPEN = "Tap to open mmogo."

    private val amountRe = Regex("""Ksh\.?\s?([0-9][0-9,]*(?:\.[0-9]{1,2})?)""", RegexOption.IGNORE_CASE)
    private val sentRe = Regex("""\bsent to\s+(.+?)(?=\s+\+?[0-9]{7,}|\s+on\s+[0-9]|\.\s|\.$|$)""", RegexOption.IGNORE_CASE)
    private val paidRe = Regex("""\bpaid to\s+(.+?)(?=\.\s|\.$|\s+on\s+[0-9]|$)""", RegexOption.IGNORE_CASE)
    private val fromRe = Regex("""\breceived\s+Ksh\.?\s?[0-9][0-9,]*(?:\.[0-9]{1,2})?\s+from\s+(.+?)(?=\s+\+?[0-9]{7,}|\s+on\s+[0-9]|\.\s|\.$|$)""", RegexOption.IGNORE_CASE)
    private val airtimeRe = Regex("""\bbought\s+Ksh\.?\s?[0-9][0-9,]*(?:\.[0-9]{1,2})?\s+of\s+airtime""", RegexOption.IGNORE_CASE)

    /** The Generic alert: the words from strings.xml, passed in so this file stays Android-free. */
    fun generic(title: String, text: String) = Text(title, text, true)

    /**
     * The Show-details alert for [body], or null when the body is not a shape we can summarise
     * (the caller then uses Generic). [parseOn] picks the second line.
     */
    fun details(body: String, parseOn: Boolean): Text? {
        val amount = amountRe.find(body)?.groupValues?.get(1)?.let(::money) ?: return null
        val second = if (parseOn) DETAILS_LINE_PARSE else DETAILS_LINE_OPEN
        val title = when {
            airtimeRe.containsMatchIn(body) -> "Bought airtime $amount"
            fromRe.containsMatchIn(body) -> name(fromRe.find(body))?.let { "Received $amount from $it" }
            sentRe.containsMatchIn(body) -> name(sentRe.find(body))?.let { "Sent $amount to $it" }
            paidRe.containsMatchIn(body) -> name(paidRe.find(body))?.let { "Paid $amount to $it" }
            else -> null
        } ?: return null
        return Text(title, second, false)
    }

    /** "500.00" -> "Ksh 500"; "1,250.50" -> "Ksh 1,250.50". */
    internal fun money(raw: String): String {
        val clean = raw.replace(",", "")
        val shown = if (clean.endsWith(".00") || clean.endsWith(".0")) clean.substringBefore('.') else clean
        val dot = shown.indexOf('.')
        val whole = if (dot >= 0) shown.substring(0, dot) else shown
        val frac = if (dot >= 0) shown.substring(dot) else ""
        val grouped = whole.reversed().chunked(3).joinToString(",").reversed()
        return "Ksh $grouped$frac"
    }

    private fun name(m: MatchResult?): String? {
        val n = m?.groupValues?.get(1)?.trim()?.replace(Regex("\\s+"), " ") ?: return null
        if (n.isEmpty()) return null
        return if (n.length > MAX_NAME) n.substring(0, MAX_NAME).trimEnd() else n
    }

    /** The text an alert uses: details when asked for AND recognised, else Generic. The public (lock screen) text never calls this. */
    fun choose(
        showDetails: Boolean, body: String?, parseOn: Boolean, genericTitle: String, genericText: String,
        deviceLocked: Boolean = false,
    ): Text {
        // A locked phone always gets the generic words: the lock screen shows whatever was posted unless the
        // user has told Android to hide sensitive content, and the app cannot force that setting.
        if (showDetails && !deviceLocked && body != null) details(body, parseOn)?.let { return it }
        return generic(genericTitle, genericText)
    }
}
