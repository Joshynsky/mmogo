package app.mmogo.autoread

/** Plain-JVM check of AskFirstLogic (0.2.1 Ask first), run by tool/kotlin_selfcheck/run.ps1. Invented values only. */
internal object AskFirstSelfCheck {
    fun runAll(): List<String> {
        val fails = ArrayList<String>()
        fun check(name: String, ok: Boolean) {
            if (!ok) fails.add(name)
        }
        fun rule(lv: Int, v: Int = 1) = """{"v":$v,"t":"SM","k":"0712345678","name":"Jane","lv":$lv,"cat":7,"run":0}"""

        // Which stored rules count: Ask first (1) and a stored Auto-record (2, shown as Ask first in 0.2.1); not Suggested, corrupt, or another version.
        check("suggested rule is not ask first", !ArrivalParse.isAskFirstRule(rule(0)))
        check("ask first rule counts", ArrivalParse.isAskFirstRule(rule(1)))
        check("stored auto-record counts as ask first", ArrivalParse.isAskFirstRule(rule(2)))
        check("unknown level does not count", !ArrivalParse.isAskFirstRule(rule(3)))
        check("version 2 does not count", !ArrivalParse.isAskFirstRule(rule(1, v = 2)))
        check("corrupt value does not count", !ArrivalParse.isAskFirstRule("not json") && !ArrivalParse.isAskFirstRule(null) && !ArrivalParse.isAskFirstRule(""))
        check("any: none", !ArrivalParse.anyAskFirst(listOf(rule(0), null, "x")))
        check("any: one is enough", ArrivalParse.anyAskFirst(listOf(rule(0), rule(1))))
        check("key prefix", ArrivalParse.RULE_KEY_PREFIX == "flutter.autoread_rule_v1.")

        // Every guard is needed, each alone stops it.
        check("all guards on starts the parse", ArrivalParse.shouldParse(true, true, true, true))
        check("not a transaction: no parse", !ArrivalParse.shouldParse(false, true, true, true))
        check("parse guard off: no parse", !ArrivalParse.shouldParse(true, false, true, true))
        check("receiver details off: no parse", !ArrivalParse.shouldParse(true, true, false, true))
        check("no ask first rule: today's behaviour", !ArrivalParse.shouldParse(true, true, true, false))

        // The alert words and the decided timeout.
        check("generic text without a name", AskAlert.text(null) == AskAlert.Shown(AskAlert.TEXT_GENERIC, false) && !AskAlert.text("  ").detailed)
        check("named text", AskAlert.text("Transport") == AskAlert.Shown("Record as Transport?", true))
        check("long name clipped", AskAlert.text("A".repeat(50)).text == "Record as ${"A".repeat(30)}?")
        check("details alert follows the minutes", AskAlert.timeoutMs(true, HeldWindow.WINDOW_MS, 30) == 30L * 60_000L)
        check("never = no timeout", AskAlert.timeoutMs(true, HeldWindow.WINDOW_MS, 0) == 0L)
        check("generic alert keeps the held window", AskAlert.timeoutMs(false, HeldWindow.WINDOW_MS, 5) == HeldWindow.WINDOW_MS)
        check("not the 6 s self dismiss", AskAlert.timeoutMs(true, HeldWindow.WINDOW_MS, 5) != ParsePolicy.SELF_DISMISS_MS)

        // The stored item and names.
        val ask = """{"id":"x","rl":"ask","rc":"SM","rk":"0712","sg":[7,3]}"""
        check("item asks first", AskStore.itemAsksFirst(ask))
        check("suggested item does not", !AskStore.itemAsksFirst("""{"id":"x","rc":"SM","rk":"0712","sg":[7]}"""))
        check("ask without a category does not", !AskStore.itemAsksFirst("""{"id":"x","rl":"ask","sg":[]}"""))
        check("null item does not", !AskStore.itemAsksFirst(null))
        check("name found", AskStore.categoryName("""{"7":"Transport"}""", 7) == "Transport")
        check("name missing", AskStore.categoryName("""{"7":"Transport"}""", 8) == null && AskStore.categoryName(null, 7) == null && AskStore.categoryName("{", 7) == null)
        check("yes key", AskStore.yesKey("a".repeat(32)) == "flutter.autoread_yes_v1.${"a".repeat(32)}")

        // The done argument.
        check("ask category arg ok", ParsePolicy.askCategoryArg(mapOf("askCategoryId" to 12)) == 12L)
        check("ask category arg refuses 0, negative, text, none", ParsePolicy.askCategoryArg(mapOf("askCategoryId" to 0)) == null &&
            ParsePolicy.askCategoryArg(mapOf("askCategoryId" to -3)) == null && ParsePolicy.askCategoryArg(mapOf("askCategoryId" to "7")) == null &&
            ParsePolicy.askCategoryArg(mapOf<String, Any>()) == null && ParsePolicy.askCategoryArg(null) == null)
        return fails
    }
}
