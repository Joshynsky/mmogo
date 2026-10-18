package app.mmogo.autoread

import java.io.File
import java.security.SecureRandom

/**
 * Self check for HeldStore (no JUnit in this build). run(dir) returns the failed assertions;
 * an empty list is a pass. [dir] must be a folder that does not exist yet (it is deleted at the end).
 * Invented data only.
 */
object HeldStoreSelfCheck {
    private const val HOUR = 60L * 60L * 1000L

    fun run(dir: File): List<String> {
        val fails = ArrayList<String>()
        fun check(name: String, ok: Boolean) {
            if (!ok) fails.add(name)
        }

        var now = 1_000_000_000_000L
        val store = HeldStore(dir, { now }, SecureRandom())
        val body = "Invented body QWE123 sent to Test Shop"
        fun names(): List<String> = (dir.list() ?: emptyArray()).sorted()

        check("constructor creates nothing", !dir.exists())

        // roundtrip
        val id = store.put(body, now)
        check("put returns a valid id", HeldId.isValid(id))
        val got = if (id == null) null else store.peek(id)
        check("peek roundtrip body", got?.body == body)
        check("peek roundtrip id and time", got?.id == id && got?.receivedAtMs == now)
        check("count is 1", store.count() == 1)
        check("listIds has the id", store.listIds() == listOfNotNull(id))
        check("file is <id>.json only", id != null && names() == listOf("$id.json"))

        // rejects
        check("empty body rejected", store.put("", now) == null)
        check("2000 chars accepted", store.put("a".repeat(2000), now) != null)
        check("2001 chars rejected", store.put("a".repeat(2001), now) == null)
        store.deleteAll()
        check("deleteAll leaves no folder", !dir.exists())

        // the agreed numbers, typed here on purpose: a change to the constants must fail this check
        check("cap constant is 20", HeldStore.MAX_HELD == 20)
        check("body limit constant is 2000", HeldStore.MAX_BODY_CHARS == 2000)

        // cap
        val ids = ArrayList<String>()
        for (i in 0 until HeldStore.MAX_HELD) {
            val x = store.put("m$i", now - 1000L + i)
            check("put $i under cap", x != null)
            if (x != null) ids.add(x)
        }
        check("21st put is null", store.put("one too many", now) == null)
        check("count is 20 at cap", store.count() == HeldStore.MAX_HELD)
        check("listIds oldest first", store.listIds() == ids)
        if (ids.isNotEmpty()) store.ack(ids[0])
        check("put works again after an ack", store.put("after ack", now) != null)
        store.deleteAll()

        // expiry on peek, claim, listIds, count; file deleted
        val e1 = store.put(body, now)
        val e2 = store.put(body, now)
        val e3 = store.put(body, now)
        val e4 = store.put(body, now)
        now += 24 * HOUR
        check("expired peek null", e1 != null && store.peek(e1) == null)
        check("expired peek deleted the file", e1 != null && !File(dir, "$e1.json").exists())
        check("expired claim false", e2 != null && !store.claim(e2))
        check("expired claim deleted the file", e2 != null && !File(dir, "$e2.json").exists())
        check("expired listIds empty", store.listIds().isEmpty())
        check("expired listIds deleted files", e3 != null && !File(dir, "$e3.json").exists())
        check("expired count 0", store.count() == 0)
        check("expired count deleted files", e4 != null && !File(dir, "$e4.json").exists())
        store.deleteAll()

        // just under the window is still alive
        val live = store.put(body, now)
        now += 24 * HOUR - 1
        check("one ms before the window is alive", live != null && store.peek(live) != null)
        store.deleteAll()

        // clock set back beyond the skew: gone; within the skew: alive
        val f1 = store.put(body, now)
        now -= 10 * 60 * 1000L
        check("future-stamped beyond skew gone", f1 != null && store.peek(f1) == null)
        check("future-stamped file deleted", f1 != null && !File(dir, "$f1.json").exists())
        now += 10 * 60 * 1000L
        val f2 = store.put(body, now)
        now -= 4 * 60 * 1000L
        check("future-stamped within skew alive", f2 != null && store.peek(f2) != null)
        now += 4 * 60 * 1000L
        // a receivedAt in the future is clamped to now on put
        val f3 = store.put(body, now + 5 * HOUR)
        check("future receivedAt clamped on put", f3 != null && store.peek(f3)?.receivedAtMs == now)
        store.deleteAll()

        // expired items do not count against the cap
        for (i in 0 until HeldStore.MAX_HELD) store.put("old$i", now)
        now += 24 * HOUR
        check("expired items purged before the cap check", store.put("fresh", now) != null)
        check("only the fresh one remains", store.count() == 1)
        store.deleteAll()

        // invalid ids rejected everywhere, nothing touched
        val keeper = store.put(body, now)
        val before = names()
        val bad = listOf(
            "", "a".repeat(31), "a".repeat(33), "A".repeat(32), "../x", "../../etc/passwd",
            "a/b", "a\\b", "g".repeat(32), "0123456789abcdef0123456789abcde/",
        )
        for (b in bad) {
            check("peek rejects '$b'", store.peek(b) == null)
            check("claim rejects '$b'", !store.claim(b))
            store.release(b)
            store.ack(b)
        }
        check("invalid ids touched no file", names() == before)
        check("keeper survived invalid ids", keeper != null && store.peek(keeper) != null)

        // claim exclusive until release or ack
        if (keeper != null) {
            check("first claim true", store.claim(keeper))
            check("second claim false", !store.claim(keeper))
            store.release(keeper)
            check("claim after release true", store.claim(keeper))
            check("claim again false", !store.claim(keeper))
            store.ack(keeper)
            check("ack removed the item", store.peek(keeper) == null && !File(dir, "$keeper.json").exists())
            store.ack(keeper)
            check("ack twice is fine", store.peek(keeper) == null)
            check("claim after ack false", !store.claim(keeper))
        }
        store.deleteAll()

        // a claim does not survive a new instance (process restart)
        val c1 = store.put(body, now)
        if (c1 != null) {
            check("claim on instance A", store.claim(c1))
            val other = HeldStore(dir, { now }, SecureRandom())
            check("claim on a fresh instance", other.claim(c1))
        }
        store.deleteAll()

        // .tmp leftover: never listed, removed by purgeExpired and by deleteAll
        val keep = store.put(body, now)
        val tmpName = "a".repeat(32) + ".tmp"
        File(dir, tmpName).writeText("{\"heldAt\":1,\"body\":\"half\"")
        check("tmp is never listed", store.listIds() == listOfNotNull(keep))
        check("tmp is never counted", store.count() == 1)
        store.purgeExpired()
        check("purgeExpired removes the tmp", !File(dir, tmpName).exists())
        check("purgeExpired keeps the live item", keep != null && store.peek(keep) != null)
        File(dir, tmpName).writeText("x")
        store.deleteAll()
        check("deleteAll removes tmp and folder", !dir.exists())

        // corrupt file treated as absent
        val good = store.put(body, now)
        val badId = "b".repeat(32)
        File(dir, "$badId.json").writeText("not json at all")
        val noBody = "c".repeat(32)
        File(dir, "$noBody.json").writeText("{\"heldAt\":$now}")
        check("corrupt peek null", store.peek(badId) == null)
        check("corrupt claim false", !store.claim(badId))
        check("missing-body peek null", store.peek(noBody) == null)
        check("corrupt never listed", store.listIds() == listOfNotNull(good))
        store.purgeExpired()
        check("purgeExpired removes corrupt", !File(dir, "$badId.json").exists() && !File(dir, "$noBody.json").exists())
        store.deleteAll()

        // body with quotes, newlines and unicode survives
        val odd = "Line1\n\"quoted\" \\ back € tab\t end"
        val o = store.put(odd, now)
        check("odd characters roundtrip", o != null && store.peek(o)?.body == odd)
        store.deleteAll()
        check("end state: no folder", !dir.exists())

        return fails
    }
}
