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

    /** The `version` argument of setConsent, or null when missing or not an int. */
    fun versionArg(args: Any?): Int? {
        if (args !is Map<*, *>) return null
        val v = args["version"]
        return if (v is Int) v else null
    }

    /** The `on` argument of setParseOn, or null when missing or not a boolean. */
    fun onArg(args: Any?): Boolean? {
        if (args !is Map<*, *>) return null
        val v = args["on"]
        return if (v is Boolean) v else null
    }

    /**
     * True on a Xiaomi-family phone (Build.MANUFACTURER xiaomi, redmi or poco, any case): the
     * Autostart row shows. Decided here and passed over the channel; Dart never reads the maker.
     */
    fun autostartHelp(manufacturer: String?): Boolean {
        val m = manufacturer?.trim()?.lowercase() ?: return false
        return m == "xiaomi" || m == "redmi" || m == "poco"
    }

    const val AUTOSTART_MIUI = "miui_autostart"
    const val AUTOSTART_OWN_SETTINGS = "own_settings"

    /**
     * Where "Open Autostart settings" goes: the MIUI Autostart component only on a Xiaomi-family phone
     * (the same check as [autostartHelp]); on any other phone straight to the app's own settings page.
     */
    fun autostartTarget(manufacturer: String?): String =
        if (autostartHelp(manufacturer)) AUTOSTART_MIUI else AUTOSTART_OWN_SETTINGS

    fun stateResult(
        enabled: Boolean, smsGranted: Boolean, notifGranted: Boolean, heldCount: Int,
        parseOn: Boolean = false, autostartHelp: Boolean = false, consentVersion: Int = 0,
    ): Map<String, Any?> =
        mapOf(
            "enabled" to enabled, "smsGranted" to smsGranted, "notifGranted" to notifGranted, "heldCount" to heldCount,
            "parseOn" to parseOn, "autostartHelp" to autostartHelp, "consentVersion" to consentVersion,
        )

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
