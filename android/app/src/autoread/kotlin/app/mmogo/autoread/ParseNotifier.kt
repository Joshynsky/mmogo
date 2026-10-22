package app.mmogo.autoread

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import app.mmogo.R

/**
 * Stage 2 notification pieces: the Parse button on the "message received" notification, and the
 * notification the Parse tap leaves behind ("Parsed" with Categorize now and Later, or the could-not-read
 * line). Same notification id and channel as [Notifier], so each one REPLACES the one before.
 *
 * Privacy: no message text, amount, sender or name, ever. The only data is the hidden held id, and on
 * "Parsed" a count of waiting items. Every PendingIntent is immutable and explicit (our own component,
 * the held id as the only extra). No logging.
 *
 * Wording (the first line is from the signed notification mock, bell.html; the rest are existing copy):
 * - action "Parse": existing copy (kActionParse).
 * - "Categorize now" and "Later": the mock's wording (bell.html, bell-notes.md).
 * - text "Parsed. N waiting for a category": the mock shows "Parsed. 1 waiting for a category"; the
 *   count form for N other than 1 is NEW, needs PM signature.
 * - text "Could not read this one. Paste it instead.": existing copy (kCouldNotRead).
 */
object ParseNotifier {
    const val ACTION_PARSE = "app.mmogo.autoread.PARSE"
    const val ACTION_LATER = "app.mmogo.autoread.LATER"
    const val ACTION_CATEGORIZE = "app.mmogo.autoread.CATEGORIZE"

    private const val MAIN_ACTIVITY = "app.mmogo.MainActivity"
    private const val URI_SCHEME = "mmogo-autoread"

    /** The Parse button. Broadcast to our own non-exported receiver; the id is the only extra. */
    fun parseAction(context: Context, heldId: String): Notification.Action =
        action(context, R.string.autoread_action_parse, receiverIntent(context, heldId, ACTION_PARSE))

    /** Replaces the notification with "Parsed. N waiting for a category", Categorize now and Later; it removes itself after about 6 s. */
    fun postParsed(context: Context, heldId: String, waiting: Int): Boolean {
        val nm = manager(context, heldId) ?: return false
        val b = builder(context, nm, context.getString(R.string.autoread_parsed_text, waiting))
        // Categorize now: the same app intent as the body tap (the launch router sends a parsed item to Categorize),
        // told apart by its action so the two PendingIntents do not replace each other.
        b.addAction(action(context, R.string.autoread_action_categorize, openApp(context, heldId, ACTION_CATEGORIZE)))
        b.addAction(action(context, R.string.autoread_action_later, receiverIntent(context, heldId, ACTION_LATER)))
        if (Build.VERSION.SDK_INT >= 26) b.setTimeoutAfter(ParsePolicy.SELF_DISMISS_MS)
        b.setContentIntent(openApp(context, heldId, null))
        nm.notify(NotifierPure.notificationId(heldId), b.build())
        return true
    }

    /** Replaces the notification with the could-not-read line. No Parse button (the text will not read); the body tap opens the app. */
    fun postCouldNotRead(context: Context, heldId: String): Boolean {
        val nm = manager(context, heldId) ?: return false
        val b = builder(context, nm, context.getString(R.string.autoread_could_not_read))
        b.setContentIntent(openApp(context, heldId, null))
        nm.notify(NotifierPure.notificationId(heldId), b.build())
        return true
    }

    // --- private ---

    private fun manager(context: Context, heldId: String): NotificationManager? {
        if (!HeldId.isValid(heldId)) return null
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return null
        if (!nm.areNotificationsEnabled()) return null
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return null
        return nm
    }

    private fun builder(context: Context, nm: NotificationManager, text: String): Notification.Builder {
        val title = context.getString(R.string.autoread_notification_title)
        val b: Notification.Builder
        val publicBuilder: Notification.Builder
        if (Build.VERSION.SDK_INT >= 26) {
            Notifier.ensureChannel(context, nm)
            b = Notification.Builder(context, Notifier.CHANNEL_ID)
            publicBuilder = Notification.Builder(context, Notifier.CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            b = Notification.Builder(context)
            @Suppress("DEPRECATION")
            publicBuilder = Notification.Builder(context)
        }
        // The public version (locked screen) carries the generic words only.
        publicBuilder.setSmallIcon(R.mipmap.ic_launcher_monochrome)
            .setContentTitle(title)
            .setContentText(context.getString(R.string.autoread_notification_text))
        b.setSmallIcon(R.mipmap.ic_launcher_monochrome)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(publicBuilder.build())
        return b
    }

    @Suppress("DEPRECATION")
    private fun action(context: Context, label: Int, pi: PendingIntent): Notification.Action =
        Notification.Action.Builder(0, context.getString(label), pi).build()

    /** Explicit, immutable. Unique per id and action (data URI), so one id's buttons never replace another's. */
    private fun receiverIntent(context: Context, heldId: String, action: String): PendingIntent {
        val i = Intent(context, ParseActionReceiver::class.java).apply {
            this.action = action
            data = Uri.parse("$URI_SCHEME://$action/$heldId")
            putExtra(Notifier.EXTRA_HELD_ID, heldId)
        }
        return PendingIntent.getBroadcast(
            context, NotifierPure.notificationId(heldId), i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /**
     * The app intent: the held id is the only extra (the app's launch router reads it). An action, never a
     * data URI, tells the body tap and Categorize now apart (a data URI could be read as a deep link).
     */
    private fun openApp(context: Context, heldId: String, action: String?): PendingIntent {
        val i = Intent().apply {
            component = ComponentName(context, MAIN_ACTIVITY)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (action != null) this.action = action
            putExtra(Notifier.EXTRA_HELD_ID, heldId)
        }
        return PendingIntent.getActivity(
            context, NotifierPure.notificationId(heldId), i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
