package app.mmogo.autoread

import android.content.BroadcastReceiver
import android.content.Context
import android.os.Handler
import android.os.Looper

/**
 * Starts the existing background Parse for a message that has just arrived (Ask first, 0.2.1). The
 * decision is [ArrivalParse.shouldParse]; the work is [ParseRunner] exactly as for a Parse tap, with all
 * its guards (one engine at a time, rate limit, watchdog, generation check, ack after read-back). No new
 * component and no permission. Nothing is logged.
 */
internal object ArrivalParser {
    /** Whether a just-stored, transaction-looking message should be parsed now (guards read live). */
    fun wanted(ctx: Context, tracked: Boolean): Boolean =
        ArrivalParse.shouldParse(
            tracked = tracked,
            mayParse = ParseGuard.mayParse(ctx),
            receiverDetailsOn = AskFirstPrefs.receiverDetailsOn(ctx),
            anyAskFirst = AskFirstPrefs.anyAskFirstRule(ctx),
        )

    /**
     * Claims [id] and hands it to [ParseRunner] on the main thread (the runner's one thread). On true the
     * runner owns [pending] and finishes it; on false nothing was started and the caller finishes it.
     */
    fun start(ctx: Context, id: String, pending: BroadcastReceiver.PendingResult?): Boolean {
        return try {
            if (!AutoReadStores.held(ctx).claim(id)) return false
            Handler(Looper.getMainLooper()).post {
                try {
                    ParseRunner.submit(ctx, id, pending)
                } catch (_: Throwable) {
                    try { AutoReadStores.held(ctx).release(id) } catch (_: Throwable) {}
                    try { pending?.finish() } catch (_: Throwable) {}
                }
            }
            true
        } catch (_: Throwable) {
            false
        }
    }
}
