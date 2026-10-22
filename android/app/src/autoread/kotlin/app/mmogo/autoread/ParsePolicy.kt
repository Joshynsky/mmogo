package app.mmogo.autoread

/**
 * Stage 2 (Wave C, "Parse from the notification"): the decisions that need no Android class, so a
 * plain JVM check can run them (tool/kotlin_selfcheck/ParseSelfCheck.kt). ParseActionReceiver,
 * ParseRunner and ParseNotifier call these; nothing else decides.
 *
 * The Judge's NARROW conditions (18-10-2026, spike note 21-10-2026): one engine at a time, a watchdog
 * that tears the engine down and leaves the message held, a rate limit, a generation check and a claim
 * so a second tap or an expired item cannot double-parse, and an ack only after the Dart side has
 * read its own write back.
 */
internal object ParsePolicy {
    /** The headless channel. Dart mirror: kBackgroundChannel in lib/autoread/background/parse_entry.dart (a test pins them). */
    const val BG_CHANNEL = "app.mmogo/autoread_bg"

    /**
     * The Dart entry point run by the headless engine: a function in the program's main library (lib/main.dart)
     * that calls the auto-read code only when the build has the auto-read flag. Dart mirror: parseFromNotificationEntry.
     */
    const val ENTRY_LIBRARY = "package:mmogo/main.dart"
    const val ENTRY_FUNCTION = "parseFromNotificationEntry"

    /**
     * The Dart generation counter as shared_preferences stores it (the plugin prefixes "flutter.").
     * Dart mirror: kPendingGenerationKey in lib/autoread/data/pending_items_store.dart (a test pins them).
     */
    const val GENERATION_KEY = "flutter.autoread_generation_v1"

    /** The engine is torn down after this long and the message stays held (the broadcast limit is 10 s). */
    const val WATCHDOG_MS = 8000L

    /** The "Parsed" notification removes itself after this long. */
    const val SELF_DISMISS_MS = 6000L

    /** At most this many taps wait behind the running one; more are left held. */
    const val MAX_WAIT = 5

    /** Minimum gap between two engine starts. */
    const val MIN_START_INTERVAL_MS = 250L

    /** At most this many accepted taps in [RATE_WINDOW_MS]; more are left held. */
    const val MAX_STARTS = 10
    const val RATE_WINDOW_MS = 60_000L

    /** Parse needs the Read switch, the CURRENT consent, the SMS permission (all in [captureOk]) AND the Parse switch. */
    fun mayParse(captureOk: Boolean, parseOn: Boolean): Boolean = captureOk && parseOn

    /**
     * An ack (the held copy is deleted) is allowed only when the generation Dart wrote under is still
     * the current one and Parse is still allowed. Anything unknown (null) is not allowed.
     */
    fun ackAllowed(dartGeneration: Long?, currentGeneration: Long?, mayAct: Boolean): Boolean =
        mayAct && dartGeneration != null && currentGeneration != null && dartGeneration == currentGeneration

    /** The `generation` argument of ackHeld, or null when missing or not a number. */
    fun generationArg(args: Any?): Long? {
        if (args !is Map<*, *>) return null
        val g = args["generation"]
        return if (g is Number) g.toLong() else null
    }

    /** The `outcome` argument of done, or null. */
    fun outcomeArg(args: Any?): String? {
        if (args !is Map<*, *>) return null
        val o = args["outcome"]
        return if (o is String) o else null
    }

    /** The `waiting` count of done: 0 to 9999, 0 when missing or odd. A number only, never content. */
    fun waitingArg(args: Any?): Int {
        if (args !is Map<*, *>) return 0
        val w = args["waiting"]
        if (w !is Number) return 0
        val n = w.toLong()
        return if (n < 0L) 0 else if (n > 9999L) 9999 else n.toInt()
    }

    /** What the Dart side reports at the end. Dart mirror: kBackgroundOutcomeCodes (a test pins the codes). */
    enum class Outcome(val code: String) {
        PARSED("parsed"),
        DUPLICATE("duplicate"),
        UNREADABLE("unreadable"),
        GONE("gone"),
        NOT_SAVED("not_saved"),
        FULL("full"),
        STALE("stale"),
        ERROR("error"),
        WATCHDOG("watchdog"),
    }

    /** The outcome for a code from Dart; anything unknown is [Outcome.ERROR]. */
    fun outcomeOf(code: String?): Outcome = Outcome.values().firstOrNull { it.code == code } ?: Outcome.ERROR

    /** What the notification does for each outcome. */
    enum class Effect { SHOW_PARSED, SHOW_COULD_NOT_READ, CANCEL, LEAVE }

    fun effectOf(o: Outcome): Effect = when (o) {
        Outcome.PARSED, Outcome.DUPLICATE -> Effect.SHOW_PARSED
        Outcome.UNREADABLE -> Effect.SHOW_COULD_NOT_READ
        Outcome.GONE, Outcome.STALE -> Effect.CANCEL
        // not saved, queue full, error, watchdog: the notification stays as it was and the message stays held.
        Outcome.NOT_SAVED, Outcome.FULL, Outcome.ERROR, Outcome.WATCHDOG -> Effect.LEAVE
    }
}

/**
 * One engine at a time. Pure bookkeeping (ids and times in milliseconds); the runner owns the engines.
 * [submit] says what to do with a tap; [finish] ends the running one and names the next.
 */
internal class ParseScheduler(
    private val maxWait: Int = ParsePolicy.MAX_WAIT,
    private val minIntervalMs: Long = ParsePolicy.MIN_START_INTERVAL_MS,
    private val maxStarts: Int = ParsePolicy.MAX_STARTS,
    private val windowMs: Long = ParsePolicy.RATE_WINDOW_MS,
) {
    enum class Admit { START, QUEUED, DUPLICATE, WAIT_FULL, RATE_LIMITED }

    private var running: String? = null
    private val waiting = ArrayDeque<String>()
    private val accepted = ArrayDeque<Long>()
    private var lastStartMs: Long = Long.MIN_VALUE / 4

    val runningId: String? get() = running
    val waitingCount: Int get() = waiting.size

    fun submit(id: String, nowMs: Long): Admit {
        if (id == running || waiting.contains(id)) return Admit.DUPLICATE
        while (accepted.isNotEmpty() && nowMs - accepted.first() >= windowMs) accepted.removeFirst()
        if (accepted.size >= maxStarts) return Admit.RATE_LIMITED
        if (running != null) {
            if (waiting.size >= maxWait) return Admit.WAIT_FULL
            accepted.addLast(nowMs)
            waiting.addLast(id)
            return Admit.QUEUED
        }
        accepted.addLast(nowMs)
        running = id
        return Admit.START
    }

    /** Milliseconds to wait before the running job's engine may start (the minimum gap between starts). */
    fun startDelayMs(nowMs: Long): Long {
        val wait = lastStartMs + minIntervalMs - nowMs
        return if (wait < 0L) 0L else wait
    }

    fun markStarted(nowMs: Long) {
        lastStartMs = nowMs
    }

    /** Ends the running job [id] (a second call, or another id, does nothing) and returns the next id, now running, or null. */
    fun finish(id: String): String? {
        if (id != running) return null
        running = waiting.removeFirstOrNull()
        return running
    }
}
