package app.mmogo.autoread

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager

/**
 * Kotlin's own check before anything is stored or posted: the switch is on, the consent version
 * held in this side's prefs is current, and the SMS permission is granted right now. Whatever Dart
 * last said, a missing consent or permission means no capture and no notification.
 */
object CaptureGuard {
    fun smsGranted(context: Context): Boolean =
        try {
            context.checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
        } catch (_: Throwable) {
            false
        }

    fun mayCapture(context: Context): Boolean =
        ConsentGate.mayCapture(AutoReadSwitch.isOn(context), AutoReadSwitch.consentVersion(context), smsGranted(context))
}
