package app.mmogo.autoread

/** Plain-JVM check of ParsePolicy and ParseScheduler (stage 2), run by tool/kotlin_selfcheck/run.ps1. Not part of the app. */
internal object ParseSelfCheck {
    /** The failed checks; empty means every check passed. */
    fun runAll(): List<String> {
        val fails = ArrayList<String>()
        fun check(name: String, ok: Boolean) {
            if (!ok) fails.add(name)
        }

        // --- the gate: every one of the four conditions is needed
        for (capture in listOf(false, true)) for (parse in listOf(false, true)) {
            check("mayParse capture=$capture parse=$parse", ParsePolicy.mayParse(capture, parse) == (capture && parse))
        }
        // the capture part itself (switch, current consent, SMS permission) is ConsentGate.mayCapture
        check("gate: all three present", ConsentGate.mayCapture(true, ConsentGate.CONSENT_VERSION, true))
        check("gate: switch off", !ConsentGate.mayCapture(false, ConsentGate.CONSENT_VERSION, true))
        check("gate: no consent", !ConsentGate.mayCapture(true, 0, true))
        check("gate: old consent", !ConsentGate.mayCapture(true, ConsentGate.CONSENT_VERSION - 1, true))
        check("gate: no SMS permission", !ConsentGate.mayCapture(true, ConsentGate.CONSENT_VERSION, false))

        // --- ack: only on the same generation, only while Parse is allowed, never on unknowns
        check("ack same generation", ParsePolicy.ackAllowed(3L, 3L, true))
        check("ack refused: generation moved", !ParsePolicy.ackAllowed(3L, 4L, true))
        check("ack refused: generation went back", !ParsePolicy.ackAllowed(4L, 3L, true))
        check("ack refused: Parse no longer allowed", !ParsePolicy.ackAllowed(3L, 3L, false))
        check("ack refused: Dart generation missing", !ParsePolicy.ackAllowed(null, 3L, true))
        check("ack refused: current generation unreadable", !ParsePolicy.ackAllowed(3L, null, true))
        check("ack refused: both missing", !ParsePolicy.ackAllowed(null, null, true))
        check("generation arg Int", ParsePolicy.generationArg(mapOf("generation" to 7)) == 7L)
        check("generation arg Long", ParsePolicy.generationArg(mapOf("generation" to 7L)) == 7L)
        check("generation arg missing", ParsePolicy.generationArg(mapOf("id" to "x")) == null)
        check("generation arg string", ParsePolicy.generationArg(mapOf("generation" to "7")) == null)
        check("generation arg not a map", ParsePolicy.generationArg("7") == null)

        // --- done arguments
        check("outcome arg", ParsePolicy.outcomeArg(mapOf("outcome" to "parsed")) == "parsed")
        check("outcome arg wrong type", ParsePolicy.outcomeArg(mapOf("outcome" to 1)) == null)
        check("waiting arg", ParsePolicy.waitingArg(mapOf("waiting" to 3)) == 3)
        check("waiting arg negative", ParsePolicy.waitingArg(mapOf("waiting" to -5)) == 0)
        check("waiting arg huge", ParsePolicy.waitingArg(mapOf("waiting" to 1000000L)) == 9999)
        check("waiting arg string", ParsePolicy.waitingArg(mapOf("waiting" to "3")) == 0)
        check("waiting arg missing", ParsePolicy.waitingArg(null) == 0)

        // --- outcomes and what the notification does
        check("known code", ParsePolicy.outcomeOf("parsed") == ParsePolicy.Outcome.PARSED)
        check("unknown code is an error", ParsePolicy.outcomeOf("whatever") == ParsePolicy.Outcome.ERROR)
        check("null code is an error", ParsePolicy.outcomeOf(null) == ParsePolicy.Outcome.ERROR)
        check("codes are unique", ParsePolicy.Outcome.values().map { it.code }.toSet().size == ParsePolicy.Outcome.values().size)
        for (o in ParsePolicy.Outcome.values()) check("code round trip ${o.code}", ParsePolicy.outcomeOf(o.code) == o)
        check("parsed shows Parsed", ParsePolicy.effectOf(ParsePolicy.Outcome.PARSED) == ParsePolicy.Effect.SHOW_PARSED)
        check("duplicate shows Parsed", ParsePolicy.effectOf(ParsePolicy.Outcome.DUPLICATE) == ParsePolicy.Effect.SHOW_PARSED)
        check("unreadable shows could-not-read", ParsePolicy.effectOf(ParsePolicy.Outcome.UNREADABLE) == ParsePolicy.Effect.SHOW_COULD_NOT_READ)
        check("gone cancels", ParsePolicy.effectOf(ParsePolicy.Outcome.GONE) == ParsePolicy.Effect.CANCEL)
        check("stale cancels", ParsePolicy.effectOf(ParsePolicy.Outcome.STALE) == ParsePolicy.Effect.CANCEL)
        for (o in listOf(ParsePolicy.Outcome.NOT_SAVED, ParsePolicy.Outcome.FULL, ParsePolicy.Outcome.ERROR, ParsePolicy.Outcome.WATCHDOG)) {
            check("failure leaves the notification: ${o.code}", ParsePolicy.effectOf(o) == ParsePolicy.Effect.LEAVE)
        }

        // --- constants the conditions name
        check("watchdog under the 10 s broadcast limit", ParsePolicy.WATCHDOG_MS in 1L..9_999L)
        check("watchdog about 8 s", ParsePolicy.WATCHDOG_MS == 8000L)
        check("self-dismiss about 6 s", ParsePolicy.SELF_DISMISS_MS == 6000L)

        // --- scheduler: one engine at a time
        val a = "a".repeat(32)
        val b = "b".repeat(32)
        val c = "c".repeat(32)
        run {
            val s = ParseScheduler()
            check("first tap starts", s.submit(a, 0L) == ParseScheduler.Admit.START)
            check("running id", s.runningId == a)
            check("second tap on the same id is a duplicate (claim twin)", s.submit(a, 10L) == ParseScheduler.Admit.DUPLICATE)
            check("another id waits behind", s.submit(b, 20L) == ParseScheduler.Admit.QUEUED)
            check("waiting count", s.waitingCount == 1)
            check("the waiting id tapped again is a duplicate", s.submit(b, 30L) == ParseScheduler.Admit.DUPLICATE)
            check("still only one running", s.runningId == a)
            check("finishing a stranger does nothing", s.finish(c) == null && s.runningId == a)
            check("finish names the next and runs it", s.finish(a) == b && s.runningId == b)
            check("finishing twice does nothing", s.finish(a) == null && s.runningId == b)
            check("last finish leaves nothing running", s.finish(b) == null && s.runningId == null)
            check("a finished id can be tapped again", s.submit(a, 40L) == ParseScheduler.Admit.START)
        }
        run {
            val s = ParseScheduler(maxWait = 2, maxStarts = 100)
            s.submit(a, 0L)
            check("wait 1", s.submit(b, 1L) == ParseScheduler.Admit.QUEUED)
            check("wait 2", s.submit(c, 2L) == ParseScheduler.Admit.QUEUED)
            check("wait list full", s.submit("d".repeat(32), 3L) == ParseScheduler.Admit.WAIT_FULL)
            check("a refused tap is not queued", s.waitingCount == 2)
        }
        run {
            val s = ParseScheduler(maxStarts = 3, windowMs = 1000L)
            val ids = (0 until 6).map { it.toString().padStart(32, '0') }
            check("rate 1", s.submit(ids[0], 0L) == ParseScheduler.Admit.START)
            check("rate 2", s.submit(ids[1], 10L) == ParseScheduler.Admit.QUEUED)
            check("rate 3", s.submit(ids[2], 20L) == ParseScheduler.Admit.QUEUED)
            check("rate limit reached", s.submit(ids[3], 30L) == ParseScheduler.Admit.RATE_LIMITED)
            check("still limited just inside the window", s.submit(ids[3], 999L) == ParseScheduler.Admit.RATE_LIMITED)
            check("the window passes", s.submit(ids[3], 1000L) == ParseScheduler.Admit.QUEUED)
        }
        run {
            val s = ParseScheduler(minIntervalMs = 250L)
            check("no delay before any start", s.startDelayMs(0L) == 0L)
            s.markStarted(1000L)
            check("delay right after a start", s.startDelayMs(1100L) == 150L)
            check("no delay after the interval", s.startDelayMs(1250L) == 0L && s.startDelayMs(5000L) == 0L)
        }

        // --- an expired item or a second tap cannot double-parse: the claim is the HeldStore's
        run {
            val dir = java.io.File(System.getProperty("java.io.tmpdir"), "parsecheck_" + System.nanoTime())
            var now = 1_000_000L
            val store = HeldStore(dir, { now })
            val id = store.put("invented body", now)
            check("held put", id != null)
            if (id != null) {
                check("first claim", store.claim(id))
                check("second tap cannot claim", !store.claim(id))
                store.release(id)
                check("claim again after release", store.claim(id))
                store.release(id)
                now += HeldWindow.WINDOW_MS
                check("expired: peek is gone", store.peek(id) == null)
                check("expired: cannot claim", !store.claim(id))
            }
            val id2 = store.put("invented body two", now)
            if (id2 != null) {
                check("claimed item is not evicted by a full store", store.claim(id2))
                store.ack(id2)
                check("ack clears the claim and the item", store.peek(id2) == null && store.claim(id2).not())
            }
            dir.deleteRecursively()
        }

        return fails
    }
}
