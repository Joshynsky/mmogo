package app.mmogo.autoread

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * §AUTOREAD.RECEIVER (skeleton, AR1). Declared disabled in the autoread
 * manifest and does nothing: no reading, no storing, no logging, no
 * notification. The receiver logic arrives in a later slice.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Intentionally empty.
    }
}
