package app.mmogo

import android.app.Activity
import android.content.Intent
import app.mmogo.autoread.AutoReadBridge
import app.mmogo.autoread.BridgeLogic
import app.mmogo.autoread.PauseNotice
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hook seam, autoread flavor (architecture E7). Same shape as the standard
 * flavor's no-op object; this one registers the auto-read bridge and forwards to it.
 * 0.2.2 item 2 (B-PAUSE): also registers the pinned paused notice's channel ([PauseNotice.CHANNEL]).
 */
object FeatureHooks {
    fun onCreate() {}

    fun configureFlutterEngine(activity: Activity, engine: FlutterEngine) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, AutoReadBridge.CHANNEL)
        val bridge = AutoReadBridge(activity, channel)
        // B-PAUSE: Read off (and Delete data, which turns Read off first) removes the pinned paused notice BEFORE
        // the bridge handles the call. Removing is the safe side: if Read stays on, the app's pause notice sync
        // posts it again on the next open or resume. The call itself is passed on unchanged.
        channel.setMethodCallHandler { call, result ->
            if (call.method == "setEnabled" && BridgeLogic.enabledArg(call.arguments) == false) {
                PauseNotice.cancel(activity)
            }
            bridge.onMethodCall(call, result)
        }
        // B-PAUSE: the notice's own channel (show / cancel; Dart side lib/autoread/bridge/pause_notice_bridge.dart).
        MethodChannel(engine.dartExecutor.binaryMessenger, PauseNotice.CHANNEL)
            .setMethodCallHandler(PauseNotice.Handler(activity.applicationContext))
    }

    fun onNewIntent(@Suppress("UNUSED_PARAMETER") activity: Activity, intent: Intent) {
        AutoReadBridge.onNewIntent(intent)
    }

    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        AutoReadBridge.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
