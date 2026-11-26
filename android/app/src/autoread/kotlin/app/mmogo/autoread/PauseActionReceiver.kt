package app.mmogo.autoread

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * §AUTOREAD.PAUSE_ACTION_RECEIVER_KT - 0.2.2 item 2 (B-PAUSE): the Resume button of the pinned paused notice
 * ([PauseNotice]). NOT exported, no intent-filter, no permission: only our own immutable explicit PendingIntent
 * reaches it, and it carries no extras. Works with mmogo closed (a plain broadcast; no service).
 *
 * Resume writes `flutter.autoread_hard_paused` = false (Dart key kHardPausedPrefsKey,
 * lib/autoread/rules/prefs_hard_rule_pause.dart, which reads `false` as not paused) and then removes the notice.
 * Fail closed: whatever cannot be read cleanly ([PauseNotice.resumeStep] KEEP), a failed write, or a read-back
 * that is not `false` does NOTHING more: the pause stays on and the notice stays. The app follows on its next
 * open or resume (the Dart pause port re-reads the key). No logging; never throws.
 */
class PauseActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            if (intent.action != PauseNotice.ACTION_RESUME) return
            val ctx = context.applicationContext
            val p = ctx.getSharedPreferences(AskStore.FLUTTER_PREFS, Context.MODE_PRIVATE)
            val raw = try {
                p.all[HardRuleLogic.PAUSED_KEY]
            } catch (_: Throwable) {
                return // unreadable: KEEP
            }
            when (PauseNotice.resumeStep(raw)) {
                PauseNotice.ResumeStep.KEEP -> return
                PauseNotice.ResumeStep.ALREADY -> PauseNotice.cancel(ctx)
                PauseNotice.ResumeStep.RESUME -> {
                    if (!p.edit().putBoolean(HardRuleLogic.PAUSED_KEY, false).commit()) return
                    if (p.all[HardRuleLogic.PAUSED_KEY] == false) PauseNotice.cancel(ctx)
                }
            }
        } catch (_: Throwable) {
            // A receiver must never crash; the pause stays as it is.
        }
    }
}
