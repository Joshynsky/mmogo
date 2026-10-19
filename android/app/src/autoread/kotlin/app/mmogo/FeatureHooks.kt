package app.mmogo

import android.app.Activity
import android.content.Intent
import app.mmogo.autoread.AutoReadBridge
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hook seam, autoread flavor (architecture E7). Same shape as the standard
 * flavor's no-op object; this one registers the auto-read bridge and forwards to it.
 */
object FeatureHooks {
    fun onCreate() {}

    fun configureFlutterEngine(activity: Activity, engine: FlutterEngine) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, AutoReadBridge.CHANNEL)
        channel.setMethodCallHandler(AutoReadBridge(activity, channel))
    }

    fun onNewIntent(@Suppress("UNUSED_PARAMETER") activity: Activity, intent: Intent) {
        AutoReadBridge.onNewIntent(intent)
    }

    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        AutoReadBridge.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
