package app.mmogo.autoread

import org.json.JSONArray
import org.json.JSONObject

/**
 * §AUTOREAD.HARD_RULE_LOGIC - 0.2.2 item 2 (B2b): the Auto-record decision, Kotlin side. Pure (no Android
 * class), like [AskFirstLogic], so the plain-JVM self-check runs it against the SAME case table the Dart test
 * runs against `decideHardRule` (test/autoread/hard_rule_parity_cases.json).
 *
 * Mirror of lib/autoread/rules/hard_rule_decision.dart: same order, same "any doubt = Ask first". Reads the
 * app's stored values RAW (the headless Dart engine can read stale preferences, so Kotlin decides again from
 * what is stored at the moment of the alert):
 *  - the rule (`lv`, `cat`, `ceil`, `ap`, `t`, `k`), parsed exactly like Dart's decodeRule (corrupt = no rule);
 *  - the pause key: absent = not paused, a Boolean = itself, any other type or an unreadable file = paused;
 *  - "Record receiver details": absent = ON, a Boolean = itself, anything else = OFF;
 *  - the amount and the kind from the stored waiting item (the fee is never an input).
 *
 * [AUTO_RECORD_LIVE] is the dormancy guard (Dart mirror `autoRecordLive`, a Dart test pins both). While it is
 * false nothing in Kotlin acts on a decision. Nothing here sees message text.
 */
internal object HardRuleLogic {
    /** Dart mirror: autoRecordLive (hard_rule_decision.dart). Flipped only by the PM-approved step G2. */
    const val AUTO_RECORD_LIVE = true

    /** Dart mirror: kHardPausedPrefsKey (prefs_hard_rule_pause.dart) with the plugin's "flutter." prefix. */
    const val PAUSED_KEY = "flutter.autoread_hard_paused"

    /** Dart mirror: kCeilingMaxCents (rule_model.dart): Ksh 1,000,000. */
    const val CEILING_MAX_CENTS = 100000000L

    /**
     * An automatic mark is the queued-Yes key ([AskStore.YES_PREFIX] + id) holding this tag and the time as a
     * STRING ("auto:<ms>"); a Yes mark holds a number. Old Yes marks stay valid; an app that does not know the
     * tag ignores it (never records). Dart mirror: kAutoMarkTag (queued_yes.dart).
     */
    const val AUTO_MARK_TAG = "auto:"

    enum class Decision(val code: String) { RECORD("record"), ASK_FIRST("askFirst"), NOT_APPLICABLE("notApplicable") }

    /** The parts of a stored rule the decision needs. */
    data class Rule(val type: String, val key: String, val level: Int, val categoryId: Long?, val ceilingCents: Long?, val autoPending: Boolean)

    private val TYPES = setOf("SM", "PB", "BG", "PO")

    /** Same as Dart canHoldAutoRecord: Send Money, Till and Pochi; never Paybill. */
    fun canHold(kind: String): Boolean = kind == "SM" || kind == "BG" || kind == "PO"

    /** Dart mirror: ruleKindOfSource (the waiting item's `type` is SmsSourceType.name). Pochi, withdrawal, airtime: null. */
    fun kindOfSource(source: String?): String? = when (source) {
        "sendMoney" -> "SM"
        "payBill" -> "PB"
        "buyGoods" -> "BG"
        else -> null
    }

    /** Dart mirror: hardPausedFromRaw. [unreadable] = the file could not be read: paused. */
    fun pausedFrom(raw: Any?, unreadable: Boolean = false): Boolean =
        if (unreadable) true else when (raw) {
            null, JSONObject.NULL -> false
            is Boolean -> raw
            else -> true
        }

    /** Dart mirror: hardDetailsOnFromRaw. [unreadable] = OFF. */
    fun detailsOnFrom(raw: Any?, unreadable: Boolean = false): Boolean =
        if (unreadable) false else when (raw) {
            null, JSONObject.NULL -> true
            is Boolean -> raw
            else -> false
        }

    /** Dart mirror: decideHardRule. */
    fun decide(rule: Rule?, kind: String?, amountCents: Long, paused: Boolean, detailsOn: Boolean): Decision {
        if (rule == null || kind == null || kind !in TYPES) return Decision.NOT_APPLICABLE
        if (rule.level == 0) return Decision.NOT_APPLICABLE
        if (rule.level == 1) return Decision.ASK_FIRST
        // Level 2 (Auto-record) from here: every doubt is Ask first.
        if (!detailsOn || paused) return Decision.ASK_FIRST
        if (!canHold(kind) || rule.type != kind) return Decision.ASK_FIRST
        if (rule.autoPending || rule.categoryId == null) return Decision.ASK_FIRST
        if (amountCents <= 0L) return Decision.ASK_FIRST
        val ceiling = rule.ceilingCents
        if (ceiling != null) {
            if (ceiling < 1L || ceiling > CEILING_MAX_CENTS) return Decision.ASK_FIRST
            if (amountCents > ceiling) return Decision.ASK_FIRST
        }
        return Decision.RECORD
    }

    /** A JSON whole number (Dart `is int`); a decimal or anything else is null. */
    private fun whole(v: Any?): Long? = when (v) {
        is Int -> v.toLong()
        is Long -> v
        else -> null
    }

    /** Dart `x == n` for a JSON number (1.0 == 1 in Dart). */
    private fun numEquals(v: Any?, n: Int): Boolean = v is Number && v.toDouble() == n.toDouble()

    private fun JSONObject.raw(name: String): Any? = if (has(name)) get(name).let { if (it == JSONObject.NULL) null else it } else null

    /** Mirror of Dart decodeRule: null for anything that is not a well-formed version 1 rule. */
    fun parseRule(raw: String?): Rule? {
        if (raw.isNullOrEmpty()) return null
        return try {
            val m = JSONObject(raw)
            if (!numEquals(m.raw("v"), 1)) return null
            val t = m.raw("t") as? String
            if (t == null || t !in TYPES) return null
            val lvRaw = m.raw("lv")
            val level = (0..2).firstOrNull { numEquals(lvRaw, it) } ?: return null
            val k = m.raw("k") as? String ?: return null
            if (k.isEmpty() || k.length > 200) return null
            if (m.raw("name") !is String) return null
            val run = whole(m.raw("run")) ?: return null
            if (run < 0L) return null
            if (whole(m.raw("created")) == null || whole(m.raw("changed")) == null) return null
            val cat = m.raw("cat")
            val runCat = m.raw("runCat")
            val last = m.raw("lastRecorded")
            if ((cat != null && whole(cat) == null) || (runCat != null && whole(runCat) == null) || (last != null && whole(last) == null)) return null
            val ceil = m.raw("ceil")
            val ap = m.raw("ap")
            val ceilV = if (ceil == null) null else (whole(ceil) ?: return null)
            if (ceilV != null && (ceilV < 1L || ceilV > CEILING_MAX_CENTS)) return null
            if (ap != null && ap !is Boolean) return null
            Rule(t, k, level, if (cat == null) null else whole(cat), ceilV, ap == true)
        } catch (_: Throwable) {
            null
        }
    }

    /** Dart mirror: ruleStorageKey with the plugin prefix: prefix + type code + '.' + base64url(UTF-8 key), no padding. */
    fun ruleKey(typeCode: String, key: String): String = ArrivalParse.RULE_KEY_PREFIX + typeCode + "." + base64UrlNoPad(key.toByteArray(Charsets.UTF_8))

    private const val B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

    /** Plain base64url without padding (no android.util / java.util.Base64, so any API level and the JVM check agree). */
    fun base64UrlNoPad(b: ByteArray): String {
        val sb = StringBuilder()
        var i = 0
        while (i < b.size) {
            val n = minOf(3, b.size - i)
            val x = ((b[i].toInt() and 0xff) shl 16) or
                ((if (n > 1) b[i + 1].toInt() and 0xff else 0) shl 8) or
                (if (n > 2) b[i + 2].toInt() and 0xff else 0)
            sb.append(B64[(x shr 18) and 63]).append(B64[(x shr 12) and 63])
            if (n > 1) sb.append(B64[(x shr 6) and 63])
            if (n > 2) sb.append(B64[x and 63])
            i += 3
        }
        return sb.toString()
    }

    /**
     * May this stored waiting item ([itemJson], as Dart's encodePendingItem writes it) be recorded with no tap?
     * True only when ALL hold: the item's hint is `auto` with a category, its kind (from `type`) equals the hint's
     * `rc`, the stored rule ([read] of its key) parses, belongs to the same person, decides RECORD with the
     * current pause and details values, and still has the hint's category. Anything else: false (today's alert).
     * [read] answers a plugin key ("flutter." prefix) with the raw stored value. Dart mirror: arrivalMayRecord.
     */
    fun mayRecord(itemJson: String?, read: (String) -> Any?): Boolean {
        if (itemJson.isNullOrEmpty()) return false
        return try {
            val m = JSONObject(itemJson)
            if (m.raw("rl") != "auto") return false
            val rc = m.raw("rc") as? String ?: return false
            val rk = m.raw("rk") as? String ?: return false
            if (rk.isEmpty() || rk.length > 200 || rc !in TYPES) return false
            val kind = kindOfSource(m.raw("type") as? String) ?: return false
            if (kind != rc) return false
            val cat = firstWhole(m.raw("sg")) ?: return false
            val amount = whole(m.raw("amountCents")) ?: return false
            val rule = parseRule(read(ruleKey(rc, rk)) as? String) ?: return false
            if (rule.key != rk) return false
            val d = decide(rule, kind, amount, pausedFrom(read(PAUSED_KEY)), detailsOnFrom(read(AskStore.DETAILS_KEY)))
            d == Decision.RECORD && rule.categoryId == cat
        } catch (_: Throwable) {
            false
        }
    }

    /** The first whole number of a JSON array (Dart keeps only `int` entries of `sg`), or null. */
    private fun firstWhole(v: Any?): Long? {
        val a = v as? JSONArray ?: return null
        for (i in 0 until a.length()) {
            val x = whole(a.opt(i))
            if (x != null) return x
        }
        return null
    }

    /** The category an `auto` item offers when Kotlin does NOT record it (today's "Record as X?" alert), or null. */
    fun autoHintCategory(itemJson: String?): Long? =
        try {
            if (itemJson.isNullOrEmpty()) null
            else {
                val m = JSONObject(itemJson)
                if (m.raw("rl") != "auto") null else firstWhole(m.raw("sg"))?.takeIf { it > 0L }
            }
        } catch (_: Throwable) {
            null
        }

    /** The value of an automatic mark written at [nowMs]. */
    fun autoMarkValue(nowMs: Long): String = AUTO_MARK_TAG + nowMs

    /** True when a stored mark value is an automatic one (a Yes mark is a number). */
    fun isAutoMark(raw: Any?): Boolean = raw is String && raw.startsWith(AUTO_MARK_TAG)
}
