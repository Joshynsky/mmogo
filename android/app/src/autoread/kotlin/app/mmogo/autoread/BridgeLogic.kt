package app.mmogo.autoread

/**
 * Pure helpers for AutoReadBridge (no Android classes), so they can be checked on a plain JVM.
 * Argument parsing, the id guard, the error codes and the result shapes of the channel contract
 * (interface-K4-bridge-channel.md).
 */
internal object BridgeLogic {
    const val ERR_BAD_ID = "bad_id"
    const val ERR_NOT_AVAILABLE = "not_available"
    const val ERR_PERMISSION = "permission"
    const val ERR_FAILED = "failed"

    /** The id argument when it is a valid held id; null for a missing map, missing key, wrong type or bad pattern. */
    fun idArg(args: Any?): String? {
        if (args !is Map<*, *>) return null
        val id = args["id"]
        return if (id is String && HeldId.isValid(id)) id else null
    }

    /** The `enabled` argument, or null when missing or not a boolean. */
    fun enabledArg(args: Any?): Boolean? {
        if (args !is Map<*, *>) return null
        val e = args["enabled"]
        return if (e is Boolean) e else null
    }

    fun peekResult(held: HeldStore.Held?): Map<String, Any?>? =
        if (held == null) null else mapOf("id" to held.id, "body" to held.body, "receivedAtMs" to held.receivedAtMs)

    fun stateResult(enabled: Boolean, smsGranted: Boolean, notifGranted: Boolean, heldCount: Int): Map<String, Any?> =
        mapOf("enabled" to enabled, "smsGranted" to smsGranted, "notifGranted" to notifGranted, "heldCount" to heldCount)

    fun permissionsResult(smsGranted: Boolean, notifGranted: Boolean): Map<String, Any?> =
        mapOf("smsGranted" to smsGranted, "notifGranted" to notifGranted)

    /** Permissions to ask for: RECEIVE_SMS always, POST_NOTIFICATIONS from API 33. */
    fun permissionsToRequest(sdkInt: Int): List<String> =
        if (sdkInt >= 33) listOf("android.permission.RECEIVE_SMS", "android.permission.POST_NOTIFICATIONS")
        else listOf("android.permission.RECEIVE_SMS")

    /** True when [permission] appears in [permissions] with a granted result (0) at the same index. */
    fun granted(permission: String, permissions: Array<out String>, grantResults: IntArray): Boolean {
        for (i in permissions.indices) {
            if (permissions[i] == permission) return i < grantResults.size && grantResults[i] == 0
        }
        return false
    }
}
