package app.mmogo.autoread

import android.app.KeyguardManager
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.os.Build

/**
 * The Ask first notifications (0.2.1). Same id and builder as [ParseNotifier], so each REPLACES the one
 * before.
 *  - [postAsk]: "Record as <Category>?" with exactly three actions (Android's limit), in this order: Not now,
 *    Change category, Yes (Yes last, on the right, as in the in-app rows).
 *    Yes is a broadcast to our own non-exported [ParseActionReceiver]; Change category opens
 *    mmogo (the app opens the Categorize sheet); Not now removes the alert (the item stays in To do).
 *  - [postQueued]: the line Yes leaves behind, "queued, added when mmogo opens". No buttons.
 *
 * Every PendingIntent is explicit and immutable (FLAG_IMMUTABLE | FLAG_UPDATE_CURRENT), the held id is the
 * only extra. On Android 12+ the Yes button asks for an unlocked phone. No message text, amount or name
 * of a person is ever used; the category name appears only with "Show details" on and an unlocked phone.
 */
internal object AskNotifier {
    fun postAsk(ctx: Context, heldId: String, categoryId: Long): Boolean {
        val nm = ParseNotifier.manager(ctx, heldId) ?: return false
        val unlocked = !isLocked(ctx)
        val name = if (AutoReadSwitch.alertDetails(ctx) && unlocked) AskFirstPrefs.categoryName(ctx, categoryId) else null
        val shown = AskAlert.text(name)
        val b = ParseNotifier.builder(ctx, nm, shown.text, popup = true)
        b.addAction(label(AskAlert.LABEL_NOT_NOW, ParseNotifier.receiverIntent(ctx, heldId, ParseNotifier.ACTION_LATER)))
        b.addAction(label(AskAlert.LABEL_CHANGE, ParseNotifier.openApp(ctx, heldId, AskAlert.ACTION_CHANGE)))
        b.addAction(label(AskAlert.LABEL_YES, ParseNotifier.receiverIntent(ctx, heldId, AskAlert.ACTION_YES), authRequired = true))
        b.setContentIntent(ParseNotifier.openApp(ctx, heldId, null))
        if (Build.VERSION.SDK_INT >= 26) {
            b.setTimeoutAfter(AskAlert.timeoutMs(shown.detailed, HeldWindow.WINDOW_MS, AutoReadSwitch.alertMinutes(ctx)))
        }
        nm.notify(NotifierPure.notificationId(heldId), b.build())
        return true
    }

    fun postQueued(ctx: Context, heldId: String): Boolean {
        val nm = ParseNotifier.manager(ctx, heldId) ?: return false
        val b = ParseNotifier.builder(ctx, nm, AskAlert.TEXT_QUEUED)
        b.setContentIntent(ParseNotifier.openApp(ctx, heldId, null))
        if (Build.VERSION.SDK_INT >= 26) b.setTimeoutAfter(ParsePolicy.SELF_DISMISS_MS)
        nm.notify(NotifierPure.notificationId(heldId), b.build())
        return true
    }

    private fun isLocked(ctx: Context): Boolean =
        try {
            (ctx.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager)?.isKeyguardLocked == true
        } catch (_: Throwable) {
            true // unknown: be generic
        }

    @Suppress("DEPRECATION")
    private fun label(text: String, pi: PendingIntent, authRequired: Boolean = false): Notification.Action {
        val a = Notification.Action.Builder(0, text, pi)
        if (authRequired && Build.VERSION.SDK_INT >= 31) a.setAuthenticationRequired(true)
        return a.build()
    }
}
