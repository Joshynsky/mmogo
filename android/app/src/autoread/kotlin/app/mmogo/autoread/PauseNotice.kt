package app.mmogo.autoread

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import app.mmogo.R
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * §AUTOREAD.PAUSE_NOTICE_KT - 0.2.2 item 2 (B-PAUSE): the pinned "Auto-record is paused" phone notice with ONE
 * action, Resume ([PauseActionReceiver]). Dart decides WHEN it shows (lib/autoread/rules/pause_notice_sync.dart:
 * paused AND at least one person on Auto-record); this side only posts, cancels and re-checks its own guards.
 *
 *  - Its OWN channel ([CHANNEL_ID], low importance: no sound, no pop-up) so [Notifier.cancelAll] (which cancels only
 *    CHANNEL_ID / POPUP_CHANNEL_ID) never removes it.
 *  - A TAG plus a NEGATIVE id: [NotifierPure.notificationId] is always >= 0 (masked with 0x7fffffff) and
 *    [Notifier.cancel] cancels by id with no tag, so no held-message cancel can ever hit this notice.
 *  - Ongoing (not swipeable before Android 14). NOT a foreground service (none in this app; check_apk_manifest
 *    denies FOREGROUND_SERVICE). On Android 14+ the user can swipe it away; Dart re-posts it on app open and resume.
 *  - Words: never written here. Dart passes the signed texts (kHardPausedNoticeTitle, kHardResume in
 *    lib/autoread/ui/levels/hard_rule_copy.dart) and the channel name; a missing or odd text = no notice.
 *  - Posts only while Auto-record is live ([HardRuleLogic.AUTO_RECORD_LIVE]), Read is on with consent and the SMS permission ([CaptureGuard.mayCapture]), notifications are
 *    allowed, and the stored pause reads as paused (fail closed: doubt = paused, the notice shows). Read off is
 *    also handled in FeatureHooks (the "setEnabled" false call cancels it first), so Delete data (Read off first)
 *    removes it too.
 * No logging; nothing here throws.
 */
object PauseNotice {
    /** Method channel name; Dart mirror: kPauseNoticeChannel (lib/autoread/bridge/pause_notice_bridge.dart). */
    const val CHANNEL = "app.mmogo/pause_notice"

    /** The notice's own channel. Never CHANNEL_ID / POPUP_CHANNEL_ID. */
    const val CHANNEL_ID = "mmogo_autorecord_paused"
    const val TAG = "app.mmogo.autoread.PAUSE_NOTICE"
    const val NOTIFICATION_ID = -7422
    const val ACTION_RESUME = "app.mmogo.autoread.PAUSE_RESUME"

    /** Longest text accepted from Dart (the signed lines are far shorter). */
    const val MAX_TEXT = 120

    private const val MAIN_ACTIVITY = "app.mmogo.MainActivity"
    private const val REQUEST_TAP = -7423
    private const val REQUEST_RESUME = -7424

    // ------------------------------------------------------------ pure (no Android)

    /** What the Resume button does with what it read. */
    enum class ResumeStep {
        /** Stored pause is exactly `true`: write `false`, then remove the notice. */
        RESUME,

        /** Stored pause is absent or exactly `false`: nothing to resume; the notice is stale, remove it. */
        ALREADY,

        /** Anything else (wrong type, unreadable): do NOTHING, the pause and the notice stay (fail closed). */
        KEEP,
    }

    /** Dart mirror: pauseResumeStep (lib/autoread/rules/prefs_hard_rule_pause.dart). */
    fun resumeStep(raw: Any?, unreadable: Boolean = false): ResumeStep =
        if (unreadable) ResumeStep.KEEP else when (raw) {
            true -> ResumeStep.RESUME
            null, false -> ResumeStep.ALREADY
            else -> ResumeStep.KEEP
        }

    /** A text from Dart: a non-blank String of at most [MAX_TEXT] characters, else null (no notice). */
    fun cleanText(v: Any?): String? {
        val s = (v as? String)?.trim() ?: return null
        return if (s.isEmpty() || s.length > MAX_TEXT) null else s
    }

    // ------------------------------------------------------------ Android

    private fun nm(ctx: Context): NotificationManager? =
        ctx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager

    /** The stored pause as Dart and [HardRuleLogic] read it (doubt = paused). */
    private fun storedPaused(ctx: Context): Boolean =
        try {
            val p = ctx.getSharedPreferences(AskStore.FLUTTER_PREFS, Context.MODE_PRIVATE)
            HardRuleLogic.pausedFrom(p.all[HardRuleLogic.PAUSED_KEY])
        } catch (_: Throwable) {
            true
        }

    /**
     * Posts (or re-posts, silently) the notice. Returns true when it was posted. Any guard that says no CANCELS
     * an existing notice instead (a stale notice must not stay) and returns false.
     */
    fun show(ctx: Context, title: String, resume: String, channelName: String): Boolean {
        return try {
            val nm = nm(ctx) ?: return false
            // Dormancy: while Auto-record is not live there is nothing to pause, so no notice (Dart gates on autoRecordUi too).
            val ok = HardRuleLogic.AUTO_RECORD_LIVE &&
                CaptureGuard.mayCapture(ctx) &&
                nm.areNotificationsEnabled() &&
                (Build.VERSION.SDK_INT < 33 ||
                    ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
                storedPaused(ctx)
            if (!ok) {
                cancel(ctx)
                return false
            }
            val b: Notification.Builder
            if (Build.VERSION.SDK_INT >= 26) {
                ensureChannel(nm, channelName)
                b = Notification.Builder(ctx, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                b = Notification.Builder(ctx)
                @Suppress("DEPRECATION")
                b.setPriority(Notification.PRIORITY_LOW)
            }
            @Suppress("DEPRECATION")
            val resumeAction = Notification.Action.Builder(0, resume, resumeIntent(ctx)).build()
            b.setSmallIcon(R.mipmap.ic_launcher_monochrome)
                .setContentTitle(title)
                .setOngoing(true)
                .setAutoCancel(false)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setCategory(Notification.CATEGORY_STATUS)
                // The title holds no amount, name or number: the same words on a locked screen.
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setContentIntent(openApp(ctx))
                .addAction(resumeAction)
            nm.notify(TAG, NOTIFICATION_ID, b.build())
            true
        } catch (_: Throwable) {
            false
        }
    }

    /** Removes the notice (tag + id). Never touches any other notification. */
    fun cancel(ctx: Context) {
        try {
            nm(ctx)?.cancel(TAG, NOTIFICATION_ID)
        } catch (_: Throwable) {
        }
    }

    /** Creates the channel, or renames it (createNotificationChannel updates the name of an existing channel). */
    private fun ensureChannel(nm: NotificationManager, name: String) {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_LOW)
        channel.setShowBadge(false)
        channel.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        nm.createNotificationChannel(channel)
    }

    /** Explicit, immutable, to our own not-exported receiver; no extras. */
    private fun resumeIntent(ctx: Context): PendingIntent {
        val i = Intent(ctx, PauseActionReceiver::class.java).apply { action = ACTION_RESUME }
        return PendingIntent.getBroadcast(
            ctx, REQUEST_RESUME, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /** The body tap opens mmogo (no extras, no action: the app's launch router sees a plain open). */
    private fun openApp(ctx: Context): PendingIntent {
        val i = Intent().apply {
            component = ComponentName(ctx, MAIN_ACTIVITY)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            ctx, REQUEST_TAP, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /** Channel [CHANNEL]: "show" {title, resume, channelName} -> Boolean; "cancel" -> null. */
    class Handler(private val ctx: Context) : MethodChannel.MethodCallHandler {
        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            try {
                when (call.method) {
                    "show" -> {
                        val a = call.arguments as? Map<*, *>
                        val title = cleanText(a?.get("title"))
                        val resume = cleanText(a?.get("resume"))
                        val channelName = cleanText(a?.get("channelName"))
                        if (title == null || resume == null || channelName == null) {
                            result.success(false)
                        } else {
                            result.success(show(ctx.applicationContext, title, resume, channelName))
                        }
                    }
                    "cancel" -> {
                        cancel(ctx.applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Throwable) {
                try {
                    result.success(false)
                } catch (_: Throwable) {
                }
            }
        }
    }
}
