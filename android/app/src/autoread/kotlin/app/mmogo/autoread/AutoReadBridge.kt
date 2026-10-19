package app.mmogo.autoread

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * §AUTOREAD.RECEIVER (AutoReadBridge, K4a). Channel `app.mmogo/autoread`; the contract is
 * interface-K4-bridge-channel.md. The raw body leaves here ONLY in the peekHeld result. No
 * logging; error messages carry no argument and no body.
 */
class AutoReadBridge(private val activity: Activity, private val channel: MethodChannel) :
    MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "app.mmogo/autoread"
        const val REQUEST_CODE = 7421
        private const val RECEIVER_CLASS = "app.mmogo.autoread.SmsReceiver"

        @Volatile
        private var current: AutoReadBridge? = null

        /** Called by the autoread FeatureHooks. */
        fun onNewIntent(intent: Intent) {
            current?.handleNewIntent(intent)
        }

        fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
            current?.handlePermissionsResult(requestCode, permissions, grantResults)
        }
    }

    private var pending: MethodChannel.Result? = null

    init {
        current = this
    }

    private val store get() = AutoReadStores.held(activity)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "peekHeld" -> {
                    val id = BridgeLogic.idArg(call.arguments)
                    result.success(if (id == null) null else BridgeLogic.peekResult(store.peek(id)))
                }
                "claim" -> {
                    val id = BridgeLogic.idArg(call.arguments)
                    result.success(if (id == null) false else store.claim(id))
                }
                "release" -> {
                    val id = BridgeLogic.idArg(call.arguments)
                    if (id != null) store.release(id)
                    result.success(null)
                }
                "ackHeld" -> {
                    val id = BridgeLogic.idArg(call.arguments)
                    if (id != null) store.ack(id)
                    result.success(null)
                }
                "listHeldIds" -> result.success(store.listIds())
                "getState" -> result.success(
                    BridgeLogic.stateResult(
                        AutoReadSwitch.isOn(activity), smsGranted(), notifGranted(), store.count(),
                    ),
                )
                "setEnabled" -> {
                    val enabled = BridgeLogic.enabledArg(call.arguments)
                    if (enabled == null) result.error(BridgeLogic.ERR_FAILED, "bad argument", null)
                    else result.success(setEnabled(enabled))
                }
                "requestPermissions" -> requestPermissions(result)
                "takeLaunchId" -> result.success(takeLaunchId())
                "deleteAllHeld" -> {
                    store.deleteAll()
                    Notifier.cancelAll(activity)
                    result.success(null)
                }
                "openAppSettings" -> {
                    val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", activity.packageName, null))
                    activity.startActivity(i)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Throwable) {
            try {
                result.error(BridgeLogic.ERR_FAILED, "failed", null)
            } catch (_: Throwable) {
            }
        }
    }

    private fun smsGranted(): Boolean =
        activity.checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

    private fun notifGranted(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission("android.permission.POST_NOTIFICATIONS") == PackageManager.PERMISSION_GRANTED

    private fun setComponent(enabled: Boolean) {
        val state = if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        activity.packageManager.setComponentEnabledSetting(
            ComponentName(activity, RECEIVER_CLASS), state, PackageManager.DONT_KILL_APP,
        )
    }

    private fun setEnabled(enabled: Boolean): Boolean {
        if (enabled) {
            if (AutoReadSwitch.setEnabled(activity, true)) setComponent(true)
        } else {
            setComponent(false)
            AutoReadSwitch.setEnabled(activity, false)
            Notifier.cancelAll(activity)
        }
        return AutoReadSwitch.isOn(activity)
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (pending != null) {
            result.error(BridgeLogic.ERR_FAILED, "request pending", null)
            return
        }
        pending = result
        try {
            activity.requestPermissions(BridgeLogic.permissionsToRequest(Build.VERSION.SDK_INT).toTypedArray(), REQUEST_CODE)
        } catch (t: Throwable) {
            pending = null
            throw t
        }
    }

    private fun takeLaunchId(): String? {
        val intent = activity.intent ?: return null
        val id = Notifier.heldIdFrom(intent)
        if (id != null) intent.removeExtra(Notifier.EXTRA_HELD_ID)
        return id
    }

    private fun handleNewIntent(intent: Intent) {
        try {
            activity.intent = intent
            val id = Notifier.heldIdFrom(intent)
            if (id != null) channel.invokeMethod("onTapped", mapOf("id" to id))
        } catch (_: Throwable) {
        }
    }

    private fun handlePermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode != REQUEST_CODE) return
        val r = pending ?: return
        pending = null
        try {
            val sms = BridgeLogic.granted(Manifest.permission.RECEIVE_SMS, permissions, grantResults)
            val notif = if (Build.VERSION.SDK_INT < 33) true
            else BridgeLogic.granted("android.permission.POST_NOTIFICATIONS", permissions, grantResults)
            r.success(BridgeLogic.permissionsResult(sms, notif))
        } catch (_: Throwable) {
            try {
                r.error(BridgeLogic.ERR_FAILED, "failed", null)
            } catch (_: Throwable) {
            }
        }
    }
}
