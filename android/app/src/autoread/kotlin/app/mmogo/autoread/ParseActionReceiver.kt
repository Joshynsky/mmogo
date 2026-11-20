package app.mmogo.autoread

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper

/**
 * The Parse button and the Later button of the notification. NOT exported, no intent-filter, declared
 * disabled until the Parse switch is on (see [ParseComponent]). Only our own immutable explicit
 * PendingIntents reach it; the only extra is the hidden held id, which is validated here.
 *
 * Parse order: id check, switch/consent/permission check ([ParseGuard]), the held message must still
 * exist, then the in-flight claim (a second tap finds it taken), then [ParseRunner] (a busy claim is retried once, see [ClaimRetry]). Any "no" leaves
 * the notification and the held message exactly as they were, so the user can still tap the body and
 * parse in the app. No logging; never throws.
 */
class ParseActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            val ctx = context.applicationContext
            val id = Notifier.heldIdFrom(intent) ?: return
            when (intent.action) {
                ParseNotifier.ACTION_LATER -> Notifier.cancel(ctx, id)
                ParseNotifier.ACTION_PARSE -> parse(ctx, id)
                AskAlert.ACTION_YES -> yes(ctx, id)
                else -> return
            }
        } catch (_: Throwable) {
            // A receiver must never crash.
        }
    }

    /**
     * The Yes button of an Ask first alert: a deliberate tap, nothing else. Same guards as Parse. It only
     * QUEUES the answer (one preference key, see [AskFirstPrefs.writeYes]); the app records it when it next
     * opens, from its own copy of the hint. No hint any more (item gone): the alert is removed.
     */
    private fun yes(ctx: Context, id: String) {
        if (!ParseGuard.mayParse(ctx)) return
        if (AskFirstPrefs.writeYes(ctx, id, System.currentTimeMillis())) AskNotifier.postQueued(ctx, id) else Notifier.cancel(ctx, id)
    }

    private fun parse(ctx: Context, id: String) {
        if (!ParseGuard.mayParse(ctx)) return
        val store = AutoReadStores.held(ctx)
        if (store.peek(id) == null) {
            // Expired or already handled: nothing to parse; the button must not stay.
            Notifier.cancel(ctx, id)
            return
        }
        // A second tap on a message that is already being parsed finds the claim taken. The app's list can
        // also hold it for a moment while it describes the message, so a busy claim is tried once more
        // after a short wait (never blocking this thread); still busy: give up as before.
        var pending: PendingResult? = null
        var claimedNotHandedOver = false
        // finish() may throw if the broadcast was already finished; it is only ever called through here.
        fun finishQuietly() {
            try { pending?.finish() } catch (_: Throwable) {}
        }
        ClaimRetry.run(
            claim = { store.claim(id) },
            later = { ms, task ->
                pending = goAsync()
                Handler(Looper.getMainLooper()).postDelayed({
                    try {
                        task()
                    } catch (_: Throwable) {
                        // submit() failed after the claim was taken: give the claim back so the user can tap again.
                        if (claimedNotHandedOver) try { store.release(id) } catch (_: Throwable) {}
                        finishQuietly()
                    }
                }, ms)
            },
            onClaimed = {
                claimedNotHandedOver = true
                ParseRunner.submit(ctx, id, pending ?: goAsync())
                claimedNotHandedOver = false
            },
            onGaveUp = { finishQuietly() },
        )
    }
}
