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
            // The one process-wide store (a Parse in flight is claimed there, so it is never evicted).
            val id = AutoReadStores.held(context).put(body, parts[0].timestampMillis) ?: return
            // Only a recognised outgoing kind interrupts the user; the rest stay held, silently.
            if (SmsReceiverLogic.trackedKind(body)) Notifier.post(context, id)
        } catch (_: Throwable) {
            // A receiver must never crash on a hostile message.
        }
    }
}
