package app.mmogo.autoread

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * §AUTOREAD.HARD_RULE_ARRIVAL_KT - 0.2.2 item 2 (B2c): the Android side of an Auto-record arrival. Every read is
 * native, from the plugin's preference file, at the moment of the alert; every function fails closed (false or
 * null) and never throws. No logging; no message text, amount or person is ever shown.
 *  - [queueIfAuto]: after a parse, writes the AUTOMATIC mark (the queued-Yes key with "auto:<ms>") only when
 *    [HardRuleLogic.AUTO_RECORD_LIVE] and [HardRuleLogic.mayRecord] both say so. The app records it when it next
 *    opens, after its own re-check (lib/autoread/data/hard_rule_arrival.dart).
 *  - [postQueued]: the alert for it: the existing [AskAlert.TEXT_QUEUED] line with ONLY "Change category" (no Yes,
 *    no Undo: PM 24-11). It follows the generic alert rule (the held window), not the 6 s self dismiss, so the
 *    button stays usable. It pops up (POPUP channel, IMPORTANCE_HIGH) and never says "recorded": the app records it.
 *    Then [AutoReadBridge.onArrived] tells an open app to import at once (B-4); the app cancels the alert once the
 *    entry is recorded (B-2, AutoReadBridge "cancelAlert").
 *  - [autoHintCategory]: an `auto` item Kotlin did NOT record gets today's "Record as X?" alert with this category.
 *  - [dropOnChange]: "Change category" opens mmogo; the automatic mark of that item is removed FIRST (before the
 *    app's import can run), so the item waits for the user's own choice.
 */
internal object HardRuleArrival {
    private fun flutter(ctx: Context) = ctx.getSharedPreferences(AskStore.FLUTTER_PREFS, Context.MODE_PRIVATE)

    fun queueIfAuto(ctx: Context, heldId: String, nowMs: Long): Boolean {
        if (!HardRuleLogic.AUTO_RECORD_LIVE) return false
        return try {
            if (!HeldId.isValid(heldId)) return false
            val p = flutter(ctx)
            val all = p.all // one snapshot; an unreadable file throws: no mark
            HardRuleLogic.mayRecord(all[AskStore.PENDING_PREFIX + heldId] as? String) { k -> all[k] } &&
                p.edit().putString(AskStore.yesKey(heldId), HardRuleLogic.autoMarkValue(nowMs)).commit()
        } catch (_: Throwable) {
            false
        }
    }

    fun autoHintCategory(ctx: Context, heldId: String): Long? =
        try {
            if (!HeldId.isValid(heldId)) null
            else HardRuleLogic.autoHintCategory(flutter(ctx).getString(AskStore.PENDING_PREFIX + heldId, null))
        } catch (_: Throwable) {
            null
        }

    fun dropOnChange(ctx: Context, intent: Intent?) {
        try {
            if (intent?.action != AskAlert.ACTION_CHANGE) return
            val id = Notifier.heldIdFrom(intent) ?: return
            val p = flutter(ctx)
            val key = AskStore.yesKey(id)
            if (HardRuleLogic.isAutoMark(p.all[key])) {
                p.edit().remove(key).commit()
                // 0.2.2 (F-4): its "Queued. It will be added when mmogo opens." alert is no longer true; the item
                // now waits for the user's choice in the app that is opening. Only this item's notification id.
                Notifier.cancel(ctx, id)
            }
        } catch (_: Throwable) {
        }
    }

    fun postQueued(ctx: Context, heldId: String): Boolean {
        try {
            val nm = ParseNotifier.manager(ctx, heldId) ?: return false
            val b = ParseNotifier.builder(ctx, nm, AskAlert.TEXT_QUEUED, popup = true)
            b.addAction(changeAction(ParseNotifier.openApp(ctx, heldId, AskAlert.ACTION_CHANGE)))
            b.setContentIntent(ParseNotifier.openApp(ctx, heldId, null))
            if (Build.VERSION.SDK_INT >= 26) {
                b.setTimeoutAfter(AskAlert.timeoutMs(false, HeldWindow.WINDOW_MS, AutoReadSwitch.alertMinutes(ctx)))
            }
            nm.notify(NotifierPure.notificationId(heldId), b.build())
            return true
        } finally {
            // 0.2.2 (B-4): AFTER the alert is up (so the app's cancel, B-2, always comes after it), and even when no
            // alert could be posted (the mark is written): an app in front imports now. No argument crosses.
            AutoReadBridge.onArrived()
        }
    }

    @Suppress("DEPRECATION")
    private fun changeAction(pi: PendingIntent): Notification.Action =
        Notification.Action.Builder(0, AskAlert.LABEL_CHANGE, pi).build()
}
