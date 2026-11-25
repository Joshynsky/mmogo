package app.mmogo.autoread

import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Plain-JVM check of HardRuleLogic (0.2.2 item 2, B2b), run by tool/kotlin_selfcheck/run.ps1. It runs the SAME
 * case table the Dart test runs (test/autoread/hard_rule_parity_cases.json, path passed as -Dmmogo.parity), so
 * Dart and Kotlin cannot drift apart. Invented values only.
 */
internal object HardRuleSelfCheck {
    var count = 0

    private fun raw(o: JSONObject, name: String): Any? = if (!o.has(name) || o.isNull(name)) null else o.get(name)

    fun runAll(path: String?): List<String> {
        val fails = ArrayList<String>()
        fun check(name: String, ok: Boolean) {
            count++
            if (!ok) fails.add(name)
        }
        if (path == null || !File(path).isFile) return listOf("case table not found: $path")
        val table = JSONObject(File(path).readText(Charsets.UTF_8))

        val decide = table.getJSONArray("decide")
        check("decide table has at least 40 cases", decide.length() >= 40)
        for (i in 0 until decide.length()) {
            val c = decide.getJSONObject(i)
            val paused = HardRuleLogic.pausedFrom(raw(c, "paused"), c.optBoolean("pausedUnreadable", false))
            val details = HardRuleLogic.detailsOnFrom(raw(c, "details"), c.optBoolean("detailsUnreadable", false))
            val d = HardRuleLogic.decide(
                HardRuleLogic.parseRule(raw(c, "rule") as? String),
                raw(c, "kind") as? String,
                (c.get("amountCents") as Number).toLong(),
                paused,
                details,
            )
            check("decide: " + c.getString("name") + " (got " + d.code + ")", d.code == c.getString("expect"))
        }

        val items = table.getJSONArray("mayRecord")
        for (i in 0 until items.length()) {
            val c = items.getJSONObject(i)
            val prefs = c.getJSONObject("prefs")
            val got = HardRuleLogic.mayRecord(c.getString("item")) { k ->
                if (!k.startsWith("flutter.")) null else raw(prefs, k.removePrefix("flutter."))
            }
            check("mayRecord: " + c.getString("name"), got == c.getBoolean("expect"))
        }

        val keys = table.getJSONArray("ruleKey")
        for (i in 0 until keys.length()) {
            val c = keys.getJSONObject(i)
            check("ruleKey " + c.getString("type"), HardRuleLogic.ruleKey(c.getString("type"), c.getString("key")) == "flutter." + c.getString("storageKey"))
        }

        val kinds: JSONArray = table.getJSONArray("kindOfSource")
        for (i in 0 until kinds.length()) {
            val c = kinds.getJSONObject(i)
            check("kindOfSource " + c.getString("source"), HardRuleLogic.kindOfSource(c.getString("source")) == raw(c, "kind"))
        }
        check("kindOfSource unknown", HardRuleLogic.kindOfSource("bogus") == null && HardRuleLogic.kindOfSource(null) == null)

        // The mark, the fallback category and the flag.
        check("dormant: AUTO_RECORD_LIVE is false", !HardRuleLogic.AUTO_RECORD_LIVE)
        check("auto mark value", HardRuleLogic.autoMarkValue(123L) == "auto:123")
        check("auto mark is a string with the tag; a Yes mark (number) is not", HardRuleLogic.isAutoMark("auto:5") && !HardRuleLogic.isAutoMark(5L) && !HardRuleLogic.isAutoMark(null) && !HardRuleLogic.isAutoMark("5"))
        check("auto hint category", HardRuleLogic.autoHintCategory("""{"rl":"auto","sg":[7,3]}""") == 7L)
        check("no fallback category for ask, none, bad", HardRuleLogic.autoHintCategory("""{"rl":"ask","sg":[7]}""") == null &&
            HardRuleLogic.autoHintCategory("""{"rl":"auto","sg":[]}""") == null && HardRuleLogic.autoHintCategory("{") == null &&
            HardRuleLogic.autoHintCategory(null) == null && HardRuleLogic.autoHintCategory("""{"rl":"auto","sg":[0]}""") == null)
        check("an auto item's Yes is valid (same question)", AskStore.itemAsksFirst("""{"rl":"auto","rc":"SM","rk":"0712","sg":[7]}"""))
        check("stored level 2 still starts the arrival Parse", ArrivalParse.isAskFirstRule("""{"v":1,"lv":2}"""))
        check("base64url, no padding", HardRuleLogic.base64UrlNoPad("a".toByteArray()) == "YQ" && HardRuleLogic.base64UrlNoPad("ab".toByteArray()) == "YWI" &&
            HardRuleLogic.base64UrlNoPad("abc".toByteArray()) == "YWJj" && HardRuleLogic.base64UrlNoPad(byteArrayOf(-5, -1)) == "-_8")
        return fails
    }
}
