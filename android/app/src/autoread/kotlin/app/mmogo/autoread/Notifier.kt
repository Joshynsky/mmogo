package app.mmogo.autoread

import android.Manifest
import android.app.KeyguardManager
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

/**
 * §AUTOREAD.NOTIFIER. Posts the "a message is ready" notification. It carries only the held id as a
 * parameter. Its words are Generic (no amount, no name) unless the user chose "Show details" (see
 * [AlertText]; default Generic); the public lock-screen version is Generic in both cases. Stateless;
 * every function takes a Context. No logging.
 */
object Notifier {
    const val CHANNEL_ID = "mmogo_mpesa_messages"

    /** HIGH-importance channel of the "ready" alert: pops up (heads-up), then stays in the shade. One notification. */
    const val POPUP_CHANNEL_ID = "mmogo_mpesa_popup"
    const val EXTRA_HELD_ID = "app.mmogo.autoread.HELD_ID"

    private const val MAIN_ACTIVITY = "app.mmogo.MainActivity"

    /** Returns false (and does nothing) for an invalid id or when notifications are not allowed. */
    fun post(context: Context, heldId: String): Boolean {
        if (!HeldId.isValid(heldId)) return false
        // Never post without current consent (held on this side) and the SMS permission.
        if (!CaptureGuard.mayCapture(context)) return false
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return false
        if (!nm.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return false

        val genericTitle = context.getString(R.string.autoread_notification_title)
        val genericText = context.getString(R.string.autoread_notification_text)
        // "What alerts show": Generic (default) or Show details. The body is read only in details mode,
        // and only to build one short line; the lock-screen version below is generic in both modes.
        val showDetails = AutoReadSwitch.alertDetails(context)
        val body = if (showDetails) AutoReadStores.held(context).peek(heldId)?.body else null
        val locked = try {
            (context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager)?.isKeyguardLocked == true
        } catch (_: Throwable) {
            true // unknown: be generic
        }
        val shown = AlertText.choose(showDetails, body, AutoReadSwitch.parseOn(context), genericTitle, genericText, locked)
        val title = shown.title
        val text = shown.text
        val id = NotifierPure.notificationId(heldId)

        val intent = Intent().apply {
            component = ComponentName(context, MAIN_ACTIVITY)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_HELD_ID, heldId)
        }
        val tap = PendingIntent.getActivity(
            context, id, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder: Notification.Builder
        if (Build.VERSION.SDK_INT >= 26) {
            ensurePopupChannel(context, nm)
            builder = Notification.Builder(context, POPUP_CHANNEL_ID)
            builder.setTimeoutAfter(HeldWindow.WINDOW_MS)
        } else {
            @Suppress("DEPRECATION")
            builder = Notification.Builder(context)
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_HIGH)
        }

        // The public version (shown on a locked screen) carries the same generic words.
        val publicBuilder: Notification.Builder =
            if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, POPUP_CHANNEL_ID)
            else @Suppress("DEPRECATION") Notification.Builder(context)
        publicBuilder.setSmallIcon(R.mipmap.ic_launcher_monochrome)
            .setContentTitle(genericTitle)
            .setContentText(genericText)

        builder.setSmallIcon(R.mipmap.ic_launcher_monochrome)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(publicBuilder.build())
            .setContentIntent(tap)

        // Stage 2: the Parse button, only while the Parse switch is on (consent and permission were checked above).
        if (ParseGuard.mayParse(context)) {
            ParseComponent.ensureEnabled(context)
            builder.addAction(ParseNotifier.parseAction(context, heldId))
        }

        nm.notify(id, builder.build())
        return true
    }

    /** True only while our notification for [heldId] is still in the shade; false on any error. */
    fun isActive(context: Context, heldId: String): Boolean {
        return try {
            if (!HeldId.isValid(heldId)) return false
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                ?: return false
            val id = NotifierPure.notificationId(heldId)
            nm.activeNotifications.any { it.id == id }
        } catch (_: Throwable) {
            false
        }
    }

    /** Cancels the notification for [heldId]. An invalid id does nothing. */
    fun cancel(context: Context, heldId: String) {
        if (!HeldId.isValid(heldId)) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        nm.cancel(NotifierPure.notificationId(heldId))
    }

    /**
     * Cancels every active notification of ours on our channel. On API 26+ the channel is read from
     * the notification; below API 26 there is no channel, nothing is cancelled and the
     * notifications expire with the user's own dismissal. Notifications of other features are kept.
     */
    fun cancelAll(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        for (sbn in nm.activeNotifications) {
            val ch = sbn.notification.channelId
            if (ch == CHANNEL_ID || ch == POPUP_CHANNEL_ID) nm.cancel(sbn.tag, sbn.id)
        }
    }

    /** The held id carried by [intent], only when it is a valid id; the extra is outside input. */
    fun heldIdFrom(intent: Intent?): String? {
        if (intent == null) return null
        return NotifierPure.validated(object : NotifierPure.ExtraSource {
            override fun heldIdExtra(): String? = intent.getStringExtra(EXTRA_HELD_ID)
        })
    }

    /** Creates the HIGH channel once (importance cannot be raised later on an existing channel, hence a new id). */
    internal fun ensurePopupChannel(context: Context, nm: NotificationManager) {
        if (Build.VERSION.SDK_INT < 26) return
        if (nm.getNotificationChannel(POPUP_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            POPUP_CHANNEL_ID,
            context.getString(R.string.autoread_popup_channel_name),
            NotificationManager.IMPORTANCE_HIGH
        )
        channel.description = context.getString(R.string.autoread_popup_channel_description)
        channel.setShowBadge(false)
        channel.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        nm.createNotificationChannel(channel)
    }

    internal fun ensureChannel(context: Context, nm: NotificationManager) {
        if (Build.VERSION.SDK_INT < 26) return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.autoread_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT
        )
        channel.description = context.getString(R.string.autoread_channel_description)
        channel.setShowBadge(false)
        channel.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        nm.createNotificationChannel(channel)
    }
}
