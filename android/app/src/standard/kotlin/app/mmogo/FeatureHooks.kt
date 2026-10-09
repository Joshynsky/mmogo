package app.mmogo

/**
 * Hook seam (architecture E7). The standard flavor compiles these no-ops; the
 * autoread flavor's source set supplies its own implementation later. Nothing
 * calls this yet (slice S0 row I1 adds the seam only).
 */
object FeatureHooks {
    fun onCreate() {}
}
