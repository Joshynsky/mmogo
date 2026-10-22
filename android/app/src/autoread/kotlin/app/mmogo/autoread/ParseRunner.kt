package app.mmogo.autoread

import android.content.BroadcastReceiver
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin

/**
 * Runs the REAL Dart parser in a short-lived headless FlutterEngine for one held message.
 *
 * - ONE engine at a time ([ParseScheduler]); a few taps wait, the rest (and any burst over the rate
 *   limit) are left held, notification untouched.
 * - ONLY shared_preferences is registered (no plugin auto-registration): the engine can read and write
 *   preferences and nothing else. No foreground service, no wake lock, no battery request.
 * - A watchdog ([ParsePolicy.WATCHDOG_MS]) tears the engine down; the message then stays held.
 * - Sequence: peekHeld (this id only) -> Dart parses and writes the waiting item -> Dart reads it back
 *   -> ackHeld (refused when the generation moved or Parse is no longer allowed). The notification
 *   changes only after that. On any failure the notification stays and the message stays held (up to
 *   24 h), so the body tap still parses in the app.
 * - The body crosses the channel ONLY in the peekHeld answer. Nothing is logged.
 *
 * Everything runs on the main thread (receivers and the channel do). Design proven by the stage 2 spike
 * on three phones (D:\Projects\mmogo-spike, 21-10-2026).
 */
object ParseRunner {
    private val main = Handler(Looper.getMainLooper())
    private val scheduler = ParseScheduler()
    private val jobs = HashMap<String, Job>()

    private class Job(val ctx: Context, val id: String, val pending: BroadcastReceiver.PendingResult?) {
        var engine: FlutterEngine? = null
        var finished = false
        var watchdog: Runnable? = null
    }

    /** [id] is claimed by the caller. This takes over the claim and releases it at the end. */
    fun submit(ctx: Context, id: String, pending: BroadcastReceiver.PendingResult?) {
        val now = SystemClock.elapsedRealtime()
        when (scheduler.submit(id, now)) {
            ParseScheduler.Admit.START -> {
                val job = Job(ctx, id, pending)
                jobs[id] = job
                val delay = scheduler.startDelayMs(now)
                if (delay <= 0L) start(job) else main.postDelayed({ start(job) }, delay)
            }
            ParseScheduler.Admit.QUEUED -> {
                // Waits for the running one. The broadcast is released now (it would time out while waiting);
                // if the process is gone before its turn the message simply stays held.
                jobs[id] = Job(ctx, id, null)
                try { pending?.finish() } catch (_: Throwable) {}
            }
            ParseScheduler.Admit.DUPLICATE -> {
                try { pending?.finish() } catch (_: Throwable) {}
            }
            ParseScheduler.Admit.WAIT_FULL, ParseScheduler.Admit.RATE_LIMITED -> {
                // Left held and untouched: the body tap still parses it in the app.
                AutoReadStores.held(ctx).release(id)
                try { pending?.finish() } catch (_: Throwable) {}
            }
        }
    }

    private fun start(job: Job) {
        // A queued tap may have waited: check the switches again before an engine starts.
        if (!ParseGuard.mayParse(job.ctx)) {
            finish(job, ParsePolicy.Outcome.ERROR.code, 0)
            return
        }
        scheduler.markStarted(SystemClock.elapsedRealtime())
        val wd = Runnable { finish(job, ParsePolicy.Outcome.WATCHDOG.code, 0) }
        job.watchdog = wd
        main.postDelayed(wd, ParsePolicy.WATCHDOG_MS)
        try {
            // automaticallyRegisterPlugins = false: only shared_preferences is registered below.
            val engine = FlutterEngine(job.ctx, null, false)
            job.engine = engine
            engine.plugins.add(SharedPreferencesPlugin())
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, ParsePolicy.BG_CHANNEL)
            channel.setMethodCallHandler { call, result -> onCall(job, call, result) }
            val path = FlutterInjector.instance().flutterLoader().findAppBundlePath()
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(path, ParsePolicy.ENTRY_LIBRARY, ParsePolicy.ENTRY_FUNCTION),
                listOf(job.id),
            )
        } catch (_: Throwable) {
            finish(job, ParsePolicy.Outcome.ERROR.code, 0)
        }
    }

    private fun onCall(job: Job, call: MethodCall, result: MethodChannel.Result) {
        try {
            // Only this job's message is visible to this engine.
            val argId = BridgeLogic.idArg(call.arguments)
            when (call.method) {
                "peekHeld" ->
                    result.success(if (argId == job.id) BridgeLogic.peekResult(AutoReadStores.held(job.ctx).peek(job.id)) else null)
                "claim" -> result.success(argId == job.id) // the receiver already holds the claim for this id
                "release" -> result.success(null) // released by [finish]
                "ackHeld" -> {
                    val dartGen = ParsePolicy.generationArg(call.arguments)
                    val allowed = argId == job.id &&
                        ParsePolicy.ackAllowed(dartGen, AutoReadSwitch.pendingGeneration(job.ctx), ParseGuard.mayParse(job.ctx))
                    if (allowed) {
                        AutoReadStores.held(job.ctx).ack(job.id)
                        result.success("acked")
                    } else {
                        result.success("stale") // the held copy stays; Dart removes the item it wrote
                    }
                }
                "done" -> {
                    result.success(null)
                    finish(job, ParsePolicy.outcomeOf(ParsePolicy.outcomeArg(call.arguments)).code, ParsePolicy.waitingArg(call.arguments))
                }
                else -> result.notImplemented()
            }
        } catch (_: Throwable) {
            try { result.error("failed", "failed", null) } catch (_: Throwable) {}
        }
    }

    private fun finish(job: Job, code: String, waiting: Int) {
        if (job.finished) return
        job.finished = true
        val ctx = job.ctx
        try {
            job.watchdog?.let { main.removeCallbacks(it) }
            when (ParsePolicy.effectOf(ParsePolicy.outcomeOf(code))) {
                ParsePolicy.Effect.SHOW_PARSED -> ParseNotifier.postParsed(ctx, job.id, waiting)
                ParsePolicy.Effect.SHOW_COULD_NOT_READ -> ParseNotifier.postCouldNotRead(ctx, job.id)
                ParsePolicy.Effect.CANCEL -> Notifier.cancel(ctx, job.id)
                ParsePolicy.Effect.LEAVE -> {}
            }
        } catch (_: Throwable) {
            // The notification is cosmetic; the data is already settled.
        } finally {
            try { job.engine?.destroy() } catch (_: Throwable) {}
            AutoReadStores.held(ctx).release(job.id)
            jobs.remove(job.id)
            try { job.pending?.finish() } catch (_: Throwable) {}
            var next = scheduler.finish(job.id)
            while (next != null && jobs[next] == null) next = scheduler.finish(next) // no job object: skip it
            val nextJob = if (next == null) null else jobs[next]
            if (nextJob != null) {
                main.postDelayed({ start(nextJob) }, scheduler.startDelayMs(SystemClock.elapsedRealtime()))
            }
        }
    }
}
