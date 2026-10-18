package app.mmogo.autoread

/** Plain-JVM check of NotifierPure, run by tool/kotlin_selfcheck/run.ps1. Not part of the app. */
internal object NotifierSelfCheck {
    private fun src(v: String?) = object : NotifierPure.ExtraSource {
        override fun heldIdExtra(): String? = v
    }

    /** The failed checks; empty means every check passed. */
    fun runAll(): List<String> {
        val fails = ArrayList<String>()
        fun check(name: String, ok: Boolean) {
            if (!ok) fails.add(name)
        }

        val fixed = "0123456789abcdef0123456789abcdef"
        check("id stable", NotifierPure.notificationId(fixed) == NotifierPure.notificationId(fixed))
        check("id uses first 8 hex", NotifierPure.notificationId(fixed) == 0x01234567)
        check("id positive for ffffffff", NotifierPure.notificationId("ffffffff" + "0".repeat(24)) == 0x7fffffff)
        check("id never negative for 80000000", NotifierPure.notificationId("80000000" + "0".repeat(24)) == 0)

        val rnd = java.security.SecureRandom()
        val seen = HashSet<Int>()
        var allPositive = true
        var allValid = true
        var collisions = 0
        repeat(1000) {
            val id = HeldId.random(rnd)
            if (!HeldId.isValid(id) || id.length != 32) allValid = false
            val n = NotifierPure.notificationId(id)
            if (n < 0) allPositive = false
            if (!seen.add(n)) collisions++
        }
        check("1000 random ids valid", allValid)
        check("1000 random ids positive", allPositive)
        check("1000 random ids no collision (got $collisions)", collisions == 0)

        check("accepts valid", NotifierPure.validated(src(fixed)) == fixed)
        check("rejects null source", NotifierPure.validated(null) == null)
        check("rejects null extra", NotifierPure.validated(src(null)) == null)
        check("rejects empty", NotifierPure.validated(src("")) == null)
        check("rejects uppercase", NotifierPure.validated(src(fixed.uppercase())) == null)
        check("rejects 31 chars", NotifierPure.validated(src(fixed.substring(1))) == null)
        check("rejects 33 chars", NotifierPure.validated(src(fixed + "0")) == null)
        check("rejects path-like", NotifierPure.validated(src("../../etc/passwd")) == null)
        check("rejects path-like 32 chars", NotifierPure.validated(src("../" + "a".repeat(29))) == null)

        return fails
    }
}
