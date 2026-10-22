package app.mmogo.autoread

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * The Parse button and the Later button of the notification. NOT exported, no intent-filter, declared
 * disabled until the Parse switch is on (see [ParseComponent]). Only our own immutable explicit
 * PendingIntents reach it; the only extra is the hidden held id, which is validated here.
 *
 * Parse order: id check, switch/consent/permission check ([ParseGuard]), the held message must still
 * exist, then the in-flight claim (a second tap finds it taken), then [ParseRunner]. Any "no" leaves
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
                else -> return
            }
        } catch (_: Throwable) {
            // A receiver must never crash.
        }
    }

    private fun parse(ctx: Context, id: String) {
        if (!ParseGuard.mayParse(ctx)) return
        val store = AutoReadStores.held(ctx)
        if (store.peek(id) == null) {
            // Expired or already handled: nothing to parse; the button must not stay.
            Notifier.cancel(ctx, id)
            return
        }
        if (!store.claim(id)) return // a second tap on a message that is already being parsed
        val pending = goAsync()
        ParseRunner.submit(ctx, id, pending)
    }
}
