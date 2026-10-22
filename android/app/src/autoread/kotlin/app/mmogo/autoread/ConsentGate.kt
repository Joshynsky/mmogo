package app.mmogo.autoread

/**
 * The consent version, held HERE as well as in Dart (kReadingConsentVersion in
 * lib/autoread/logic/reading_controller.dart). A test (test/autoread/held_window_test.dart)
 * pins the two numbers together. Bump both, once, when the consent text changes in meaning.
 *
 * The Kotlin side checks consent and the SMS permission itself: the receiver and the notifier
 * never act without them, whatever Dart last said. Pure (no Android classes), so a plain JVM
 * check can run it.
 */
internal object ConsentGate {
    /** 2 (0.1.2): one consent screen with a switch per consent. */
    const val CONSENT_VERSION: Int = 2

    /** True only for the current version; 0 (never stored) and any older number are not consent. */
    fun isCurrent(stored: Int): Boolean = stored == CONSENT_VERSION

    /** Capture and notify need the switch, current consent AND the SMS permission. */
    fun mayCapture(switchOn: Boolean, storedConsent: Int, smsGranted: Boolean): Boolean =
        switchOn && isCurrent(storedConsent) && smsGranted
}
