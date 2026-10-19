package app.mmogo.autoread

/** Plain-JVM check of BridgeLogic, run by tool/kotlin_selfcheck/run.ps1. Not part of the app. */
internal object BridgeSelfCheck {
    /** The failed checks; empty means every check passed. */
    fun runAll(): List<String> {
        val fails = ArrayList<String>()
        fun check(name: String, ok: Boolean) {
            if (!ok) fails.add(name)
        }

        val good = "0123456789abcdef0123456789abcdef"
        check("channel name", "app.mmogo/autoread" == "app.mmogo/autoread")
        check("code bad_id", BridgeLogic.ERR_BAD_ID == "bad_id")
        check("code not_available", BridgeLogic.ERR_NOT_AVAILABLE == "not_available")
        check("code permission", BridgeLogic.ERR_PERMISSION == "permission")
        check("code failed", BridgeLogic.ERR_FAILED == "failed")

        check("good id accepted", BridgeLogic.idArg(mapOf("id" to good)) == good)
        check("null args rejected", BridgeLogic.idArg(null) == null)
        check("non-map args rejected", BridgeLogic.idArg(good) == null)
        check("missing id rejected", BridgeLogic.idArg(mapOf("x" to good)) == null)
        check("int id rejected", BridgeLogic.idArg(mapOf("id" to 5)) == null)
        check("null id rejected", BridgeLogic.idArg(mapOf("id" to null)) == null)
        check("uppercase id rejected", BridgeLogic.idArg(mapOf("id" to good.uppercase().replace("0123", "ABCD"))) == null)
        check("31 chars rejected", BridgeLogic.idArg(mapOf("id" to good.substring(1))) == null)
        check("33 chars rejected", BridgeLogic.idArg(mapOf("id" to good + "0")) == null)
        check("path id rejected", BridgeLogic.idArg(mapOf("id" to "../../../../etc/passwd000000000000")) == null)
        check("newline id rejected", BridgeLogic.idArg(mapOf("id" to good.substring(1) + "\n")) == null)

        check("enabled true", BridgeLogic.enabledArg(mapOf("enabled" to true)) == true)
        check("enabled false", BridgeLogic.enabledArg(mapOf("enabled" to false)) == false)
        check("enabled string rejected", BridgeLogic.enabledArg(mapOf("enabled" to "true")) == null)
        check("enabled missing rejected", BridgeLogic.enabledArg(mapOf<String, Any?>()) == null)
        check("enabled null args rejected", BridgeLogic.enabledArg(null) == null)

        check("peek null", BridgeLogic.peekResult(null) == null)
        val p = BridgeLogic.peekResult(HeldStore.Held(good, "hello", 1234L))
        check("peek keys", p != null && p.keys == setOf("id", "body", "receivedAtMs"))
        check("peek values", p != null && p["id"] == good && p["body"] == "hello" && p["receivedAtMs"] == 1234L)

        val s = BridgeLogic.stateResult(true, false, true, 3)
        check("state keys", s.keys == setOf("enabled", "smsGranted", "notifGranted", "heldCount"))
        check("state values", s["enabled"] == true && s["smsGranted"] == false && s["notifGranted"] == true && s["heldCount"] == 3)

        val pr = BridgeLogic.permissionsResult(true, false)
        check("perm keys", pr.keys == setOf("smsGranted", "notifGranted"))
        check("perm values", pr["smsGranted"] == true && pr["notifGranted"] == false)

        check("api 32 asks sms only", BridgeLogic.permissionsToRequest(32) == listOf("android.permission.RECEIVE_SMS"))
        check(
            "api 33 asks sms and notif",
            BridgeLogic.permissionsToRequest(33) == listOf("android.permission.RECEIVE_SMS", "android.permission.POST_NOTIFICATIONS"),
        )

        val perms = arrayOf("android.permission.RECEIVE_SMS", "android.permission.POST_NOTIFICATIONS")
        check("granted both", BridgeLogic.granted("android.permission.RECEIVE_SMS", perms, intArrayOf(0, 0)))
        check("denied notif", !BridgeLogic.granted("android.permission.POST_NOTIFICATIONS", perms, intArrayOf(0, -1)))
        check("absent permission false", !BridgeLogic.granted("android.permission.POST_NOTIFICATIONS", arrayOf("android.permission.RECEIVE_SMS"), intArrayOf(0)))
        check("short results false", !BridgeLogic.granted("android.permission.POST_NOTIFICATIONS", perms, intArrayOf(0)))

        return fails
    }
}
