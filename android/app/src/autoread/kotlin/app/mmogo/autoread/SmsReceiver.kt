package app.mmogo.autoread

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * §AUTOREAD.RECEIVER. Fixed order: action, switch, sender (address only), body, size, store, notify
 * (notify only when the body is a recognised outgoing kind; see SmsReceiverLogic.trackedKind).
 * Short synchronous file work; no logging; never throws.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "android.provider.Telephony.SMS_RECEIVED") return
        try {
            // Switch on, CURRENT consent version (held on this side) and SMS permission, all
            // checked here: nothing is stored or posted without them.
            if (!CaptureGuard.mayCapture(context)) return
            val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            if (parts == null || parts.isEmpty()) return
            if (!SmsReceiverLogic.senderAllowed(parts[0]?.originatingAddress)) return
            val sb = StringBuilder()
            for (p in parts) {
                if (p != null && SmsReceiverLogic.senderAllowed(p.originatingAddress)) {
                    sb.append(p.messageBody ?: "")
                }
            }
            val body = sb.toString()
            if (!SmsReceiverLogic.bodyAcceptable(body)) return
            // Known non-transaction notice (the Safaricom recharge notice): dropped, not held, not listed.
            if (SmsReceiverLogic.isNonTransactionNotice(body)) return
            // The one process-wide store (a Parse in flight is claimed there, so it is never evicted).
            val id = AutoReadStores.held(context).put(body, parts[0].timestampMillis) ?: return
            // Only a recognised outgoing kind interrupts the user; the rest stay held, silently.
            // The held message is already saved; only the heads-up is late (SmsReceiverLogic.ALERT_DELAY_MS),
            // so M-Pesa's own notification does not push it off the screen.
            if (SmsReceiverLogic.trackedKind(body)) {
                val pending = goAsync()
                if (pending == null) {
                    Notifier.post(context, id)
                } else {
                    val app = context.applicationContext ?: context
                    val t = Thread {
                        try {
                            try {
                                Thread.sleep(SmsReceiverLogic.ALERT_DELAY_MS)
                            } catch (_: InterruptedException) {
                                // Carry on: the held check below decides.
                            }
                            // Still held (not parsed or removed meanwhile): post; else stay silent.
                            if (AutoReadStores.held(app).peek(id) != null) Notifier.post(app, id)
                            try {
                                Thread.sleep(SmsReceiverLogic.ALERT_REPEAT_AFTER_MS)
                            } catch (_: InterruptedException) {
                                // Carry on: the checks below decide.
                            }
                            // Repeat once (same id, so it updates and pops up again) only if the message is
                            // still held AND our notification is still shown: a dismissed or tapped one stays gone.
                            if (AutoReadStores.held(app).peek(id) != null && Notifier.isActive(app, id)) {
                                Notifier.post(app, id)
                            }
                        } catch (_: Throwable) {
                            // Never crash on the late post.
                        } finally {
                            try {
                                pending.finish()
                            } catch (_: Throwable) {
                            }
                        }
                    }
                    t.isDaemon = true
                    t.start()
                }
            }
        } catch (_: Throwable) {
            // A receiver must never crash on a hostile message.
        }
    }
}
