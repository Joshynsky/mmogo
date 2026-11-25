package app.mmogo.autoread

import org.json.JSONObject

/**
 * 0.2.1 Ask first, Kotlin side. Pure (no Android class), so a plain JVM check can run it
 * (tool/kotlin_selfcheck/AskFirstSelfCheck.kt) and a Dart test can pin its constants.
 *
 * Three small pieces, each one job:
 *  - [ArrivalParse]: should the background Parse start by itself when a message arrives?
 *  - [AskAlert]: the words, buttons and timeout of the "Record as <Category>?" alert.
 *  - [AskStore]: the preference keys and the small reads of the app's own stored values.
 *
 * Nothing here sees message text: only rule levels, a category id and a category name.
 */
internal object ArrivalParse {
    /** One rule per person; Dart mirror: kRuleKeyPrefix (lib/autoread/rules/rule_codec.dart), plus the plugin's "flutter." prefix. */
    const val RULE_KEY_PREFIX = "flutter.autoread_rule_v1."

    private val VERSION = Regex("\"v\"\\s*:\\s*1\\b")
    private val LEVEL = Regex("\"lv\"\\s*:\\s*(\\d+)")

    /**
     * True for a stored rule of level Ask first (1). Auto-record (2) counts too: 0.2.1 treats a stored
     * Auto-record level as Ask first, so a tap always decides. Suggested (0), a corrupt value and null are false.
     */
    fun isAskFirstRule(json: String?): Boolean {
        if (json == null || !VERSION.containsMatchIn(json)) return false
        val level = LEVEL.find(json)?.groupValues?.get(1)?.toIntOrNull() ?: return false
        return level == 1 || level == 2
    }

    /** True when any stored rule value is Ask first (a cheap presence check; the person is only known after parsing). */
    fun anyAskFirst(values: Iterable<String?>): Boolean = values.any { isAskFirstRule(it) }

    /**
     * The Parse starts on arrival only when ALL hold: the message looks like a transaction ([tracked]), the
     * existing Parse guard allows it (Read switch, current consent, SMS permission, Parse switch), "Record
     * receiver details" is ON (OFF keeps no rule, so nothing could apply) and some rule is Ask first.
     * Anything else keeps today's behaviour: the "message ready" alert with its Parse button.
     */
    fun shouldParse(tracked: Boolean, mayParse: Boolean, receiverDetailsOn: Boolean, anyAskFirst: Boolean): Boolean =
        tracked && mayParse && receiverDetailsOn && anyAskFirst
}

internal object AskAlert {
    /** Receiver action of the Yes button (our own non-exported receiver). Dart does not read it. */
    const val ACTION_YES = "app.mmogo.autoread.ASK_YES"

    /** App-launch action of the Change category button; the launch bridge turns it into [LAUNCH_CATEGORIZE]. */
    const val ACTION_CHANGE = "app.mmogo.autoread.ASK_CHANGE"

    /** What `takeLaunchAction` answers (Dart mirror: kLaunchCategorize). */
    const val LAUNCH_CATEGORIZE = "categorize"

    // WORDING-DRAFT (PM signs later): the three buttons and the two lines.
    const val LABEL_YES = "Yes"
    const val LABEL_CHANGE = "Change category"
    const val LABEL_NOT_NOW = "Not now"
    const val TEXT_GENERIC = "Record with your usual category?"
    const val TEXT_QUEUED = "Queued. It will be added when mmogo opens."

    private const val MAX_NAME = 30

    /** [text] of the alert; [detailed] is true when the category name is in it (so the "Hide details after" setting applies). */
    data class Shown(val text: String, val detailed: Boolean)

    /**
     * "Record as <Category>?" only when a [categoryName] is known (the caller passes one only when the
     * details setting is on and the phone is unlocked); otherwise the generic line. The name is clipped.
     */
    fun text(categoryName: String?): Shown {
        val n = categoryName?.trim()?.replace(Regex("\\s+"), " ")
        if (n.isNullOrEmpty()) return Shown(TEXT_GENERIC, false)
        val clipped = if (n.length > MAX_NAME) n.substring(0, MAX_NAME).trimEnd() else n
        return Shown("Record as $clipped?", true)
    }

    /**
     * DECISION (19-11-2026): this alert follows the SAME rule as the "message ready" alert, not the 6 s
     * self-dismiss of the plain "Parsed" line (ParsePolicy.SELF_DISMISS_MS), because it asks a question and a
     * question that vanishes in 6 s is useless. With details in it: the "Hide details after" minutes
     * (0 = Never = no timeout). Generic: the held window. Only the alert goes; the waiting item stays.
     */
    fun timeoutMs(detailed: Boolean, heldWindowMs: Long, detailsMinutes: Int): Long =
        AlertText.timeoutMs(!detailed, heldWindowMs, detailsMinutes)
}

internal object AskStore {
    /** The plugin's own file and key prefix (the same file ParsePolicy.GENERATION_KEY is read from). */
    const val FLUTTER_PREFS = "FlutterSharedPreferences"

    /** Dart mirror: kPendingItemPrefix (lib/autoread/data/pending_items_store.dart) with "flutter." in front. */
    const val PENDING_PREFIX = "flutter.autoread_pending_v1."

    /** A Yes tapped on an alert: one key per waiting item, value = tap time (ms). Dart mirror: kYesMarkPrefix (queued_yes.dart). */
    const val YES_PREFIX = "flutter.autoread_yes_v1."

    /** Category names for the alert: JSON {"<id>":"<name>"}. Dart mirror: kCategoryNamesKey (queued_yes.dart). */
    const val NAMES_KEY = "flutter.autoread_cat_names_v1"

    /** The existing "Record receiver details" switch (Dart: AppPrefs.keyCaptureIdentityPreference); absent = ON. */
    const val DETAILS_KEY = "flutter.capture_identity_preference"

    // 0.2.2: an `auto` hint that Kotlin did not record shows the same question, so its Yes is valid too.
    private val ASK = Regex("\"rl\"\\s*:\\s*\"(ask|auto)\"")
    private val FIRST_CATEGORY = Regex("\"sg\"\\s*:\\s*\\[\\s*(\\d+)")

    fun yesKey(heldId: String): String = YES_PREFIX + heldId

    /** True when a stored waiting item (its JSON) carries an Ask first hint with a category to offer. */
    fun itemAsksFirst(json: String?): Boolean = json != null && ASK.containsMatchIn(json) && FIRST_CATEGORY.containsMatchIn(json)

    /** The name stored for category [id], or null (absent, corrupt, blank). */
    fun categoryName(namesJson: String?, id: Long): String? =
        try {
            if (namesJson == null) null else JSONObject(namesJson).optString(id.toString(), "").ifBlank { null }
        } catch (_: Throwable) {
            null
        }
}
