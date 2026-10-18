package app.mmogo

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hook seam, autoread flavor (architecture E7). Same shape as the standard
 * flavor's no-op object; this one registers the (still empty) auto-read bridge.
 */
object FeatureHooks {
    fun onCreate() {}

    fun configureFlutterEngine(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, AutoReadBridge.CHANNEL)
            .setMethodCallHandler(AutoReadBridge())
    }
}
