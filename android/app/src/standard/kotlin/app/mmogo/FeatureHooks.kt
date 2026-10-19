package app.mmogo

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine

/**
 * Hook seam (architecture E7). The standard flavor compiles these no-ops; the
 * other flavor's source set supplies its own implementation. Nothing here
 * touches SMS or notifications.
 */
object FeatureHooks {
    fun onCreate() {}

    fun configureFlutterEngine(
        @Suppress("UNUSED_PARAMETER") activity: Activity,
        @Suppress("UNUSED_PARAMETER") engine: FlutterEngine,
    ) {}

    fun onNewIntent(
        @Suppress("UNUSED_PARAMETER") activity: Activity,
        @Suppress("UNUSED_PARAMETER") intent: Intent,
    ) {}

    fun onRequestPermissionsResult(
        @Suppress("UNUSED_PARAMETER") requestCode: Int,
        @Suppress("UNUSED_PARAMETER") permissions: Array<out String>,
        @Suppress("UNUSED_PARAMETER") grantResults: IntArray,
    ) {}
}
