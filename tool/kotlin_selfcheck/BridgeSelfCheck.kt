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
        check("state keys", s.keys == setOf("enabled", "smsGranted", "notifGranted", "heldCount", "parseOn", "autostartHelp", "consentVersion"))
        check("state values", s["enabled"] == true && s["smsGranted"] == false && s["notifGranted"] == true && s["heldCount"] == 3)
        check("state parse and autostart default off", s["parseOn"] == false && s["autostartHelp"] == false)
        val s2 = BridgeLogic.stateResult(false, true, true, 0, parseOn = true, autostartHelp = true)
        check("state parse and autostart values", s2["parseOn"] == true && s2["autostartHelp"] == true)

        check("version arg", BridgeLogic.versionArg(mapOf("version" to 2)) == 2)
        check("version string rejected", BridgeLogic.versionArg(mapOf("version" to "2")) == null)
        check("version missing rejected", BridgeLogic.versionArg(mapOf<String, Any?>()) == null)
        check("version null args rejected", BridgeLogic.versionArg(null) == null)
        check("on arg true", BridgeLogic.onArg(mapOf("on" to true)) == true)
        check("on arg false", BridgeLogic.onArg(mapOf("on" to false)) == false)
        check("on arg string rejected", BridgeLogic.onArg(mapOf("on" to "true")) == null)
        check("on arg null args rejected", BridgeLogic.onArg(null) == null)

        check("xiaomi family: Xiaomi", BridgeLogic.autostartHelp("Xiaomi"))
        check("xiaomi family: XIAOMI", BridgeLogic.autostartHelp("XIAOMI"))
        check("xiaomi family: Redmi", BridgeLogic.autostartHelp("Redmi"))
        check("xiaomi family: POCO", BridgeLogic.autostartHelp("POCO"))
        check("xiaomi family: padded", BridgeLogic.autostartHelp(" xiaomi "))
        check("not xiaomi: samsung", !BridgeLogic.autostartHelp("samsung"))
        check("not xiaomi: OPPO", !BridgeLogic.autostartHelp("OPPO"))
        check("not xiaomi: null", !BridgeLogic.autostartHelp(null))
        check("not xiaomi: empty", !BridgeLogic.autostartHelp(""))
        check("autostart target: Xiaomi goes to MIUI", BridgeLogic.autostartTarget("Xiaomi") == BridgeLogic.AUTOSTART_MIUI)
        check("autostart target: Redmi goes to MIUI", BridgeLogic.autostartTarget("redmi") == BridgeLogic.AUTOSTART_MIUI)
        check("autostart target: samsung goes to own settings", BridgeLogic.autostartTarget("samsung") == BridgeLogic.AUTOSTART_OWN_SETTINGS)
        check("autostart target: null goes to own settings", BridgeLogic.autostartTarget(null) == BridgeLogic.AUTOSTART_OWN_SETTINGS)
        check("autostart target: a package-name lookalike goes to own settings", BridgeLogic.autostartTarget("com.miui.securitycenter") == BridgeLogic.AUTOSTART_OWN_SETTINGS)
        val s3 = BridgeLogic.stateResult(false, false, false, 0, consentVersion = 2)
        check("state carries the consent version Kotlin holds", s3["consentVersion"] == 2 && BridgeLogic.stateResult(false, false, false, 0)["consentVersion"] == 0)

        check("consent: current is consent", ConsentGate.isCurrent(ConsentGate.CONSENT_VERSION))
        check("consent: never stored is not", !ConsentGate.isCurrent(0))
        check("consent: version 1 is not", !ConsentGate.isCurrent(1))
        check("consent: a newer number is not", !ConsentGate.isCurrent(ConsentGate.CONSENT_VERSION + 1))
        val cv = ConsentGate.CONSENT_VERSION
        check("capture: all three", ConsentGate.mayCapture(true, cv, true))
        check("capture: switch off", !ConsentGate.mayCapture(false, cv, true))
        check("capture: old consent", !ConsentGate.mayCapture(true, 1, true))
        check("capture: no consent", !ConsentGate.mayCapture(true, 0, true))
        check("capture: no sms permission", !ConsentGate.mayCapture(true, cv, false))

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
