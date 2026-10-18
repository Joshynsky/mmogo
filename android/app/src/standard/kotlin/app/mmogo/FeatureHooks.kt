package app.mmogo

import io.flutter.embedding.engine.FlutterEngine

/**
 * Hook seam (architecture E7). The standard flavor compiles these no-ops; the
 * autoread flavor's source set supplies its own implementation. Nothing here
 * touches SMS or notifications.
 */
object FeatureHooks {
    fun onCreate() {}

    fun configureFlutterEngine(@Suppress("UNUSED_PARAMETER") engine: FlutterEngine) {}
}
