package app.mmogo.autoread

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.SecureRandom
import org.json.JSONException
import org.json.JSONObject

/**
 * §AUTOREAD.HELDSTORE (19-10-2026). The ONE place a raw SMS body rests until the user taps.
 *
 * One file per item: `<32-hex id>.json` holding `{"heldAt":<ms>,"body":"..."}`. Written to
 * `<id>.tmp` first, synced, then renamed, so a reader never sees a half file. File names come only
 * from ids that passed [HeldId.isValid]. Expiry (see [HeldWindow.expired]) is checked on every
 * put, peek, claim, listIds and count; there is no timer. Nothing here logs, and no error text
 * carries the body.
 *
 * Claims are in memory only (a process restart clears them). They are per HeldStore instance, so
 * callers that need one shared guard must share one instance.
 */
class HeldStore(
    private val dir: File,
    private val clock: () -> Long = System::currentTimeMillis,
    private val random: SecureRandom = SecureRandom(),
) {
    data class Held(val id: String, val body: String, val receivedAtMs: Long)

    companion object {
        /** Mirror of Dart kSmsMaxChars. */
        const val MAX_BODY_CHARS = 2000
        const val MAX_HELD = 20
        private const val ID_RETRIES = 3
        private const val JSON_EXT = ".json"
        private const val TMP_EXT = ".tmp"
    }

    private val claims = HashSet<String>()

    /**
     * New id, or null: empty body, body over [MAX_BODY_CHARS], no free id, or the store is full of
     * claimed (in flight) items. When the store is at [MAX_HELD] the oldest unclaimed item is
     * deleted to make room (PM decision 19-10-2026: a new message pushes the oldest away). Its
     * notification, if any, is left alone: tapping it finds no held message.
     */
    @Synchronized
    fun put(body: String, receivedAtMs: Long): String? {
        if (body.isEmpty() || body.length > MAX_BODY_CHARS) return null
        purgeExpired()
        if (jsonIds().size >= MAX_HELD && !evictOldest()) return null
        val now = clock()
        val heldAt = if (receivedAtMs > now) now else receivedAtMs
        try {
            if (!dir.isDirectory && !dir.mkdirs() && !dir.isDirectory) return null
        } catch (e: SecurityException) {
            return null
        }
        for (attempt in 0 until ID_RETRIES) {
            val id = HeldId.random(random)
            if (fileOf(id, JSON_EXT).exists()) continue
            if (write(id, body, heldAt)) return id
            return null
        }
        return null
    }

    /** The held item, or null for an invalid id, a missing or corrupt file, or an expired item (deleted here). */
    @Synchronized
    fun peek(id: String): Held? {
        if (!HeldId.isValid(id)) return null
        val f = fileOf(id, JSON_EXT)
        if (!f.exists()) return null
        val held = read(id, f) ?: return null
        if (HeldWindow.expired(held.receivedAtMs, clock())) {
            f.delete()
            claims.remove(id)
            return null
        }
        return held
    }

    /** True when this call took the in-flight guard for a live id; false when invalid, unknown, expired or already claimed. */
    @Synchronized
    fun claim(id: String): Boolean {
        if (peek(id) == null) return false
        return claims.add(id)
    }

    @Synchronized
    fun release(id: String) {
        if (!HeldId.isValid(id)) return
        claims.remove(id)
    }

    /** Deletes the item and clears its claim. Idempotent; an invalid id does nothing. */
    @Synchronized
    fun ack(id: String) {
        if (!HeldId.isValid(id)) return
        fileOf(id, JSON_EXT).delete()
        fileOf(id, TMP_EXT).delete()
        claims.remove(id)
    }

    /** Valid, unexpired ids, oldest first. Deletes expired files it meets. */
    @Synchronized
    fun listIds(): List<String> {
        val items = ArrayList<Held>()
        for (id in jsonIds()) {
            val h = peek(id) ?: continue
            items.add(h)
        }
        items.sortWith(compareBy<Held>({ it.receivedAtMs }, { it.id }))
        return items.map { it.id }
    }

    @Synchronized
    fun count(): Int = listIds().size

    /** Removes every file in the folder (including .tmp leftovers) and the folder; clears all claims. */
    @Synchronized
    fun deleteAll() {
        claims.clear()
        val files = dir.listFiles()
        if (files != null) {
            for (f in files) f.deleteRecursively()
        }
        dir.delete()
    }

    /** Deletes expired and corrupt files, and any leftover .tmp or unrecognised file. */
    @Synchronized
    fun purgeExpired() {
        val files = dir.listFiles() ?: return
        val now = clock()
        for (f in files) {
            val name = f.name
            val id = if (name.endsWith(JSON_EXT)) name.removeSuffix(JSON_EXT) else null
            if (id == null || !HeldId.isValid(id)) {
                f.delete()
                continue
            }
            val held = read(id, f)
            if (held == null || HeldWindow.expired(held.receivedAtMs, now)) {
                f.delete()
                claims.remove(id)
            }
        }
    }

    // --- private ---

    /** Deletes the oldest unclaimed item. False when every item is claimed, so no slot was freed. */
    private fun evictOldest(): Boolean {
        val items = ArrayList<Held>()
        for (id in jsonIds()) {
            if (id in claims) continue
            val h = peek(id) ?: continue
            items.add(h)
        }
        val oldest = items.minWithOrNull(compareBy<Held>({ it.receivedAtMs }, { it.id })) ?: return false
        ack(oldest.id)
        return jsonIds().size < MAX_HELD
    }

    private fun fileOf(id: String, ext: String): File = File(dir, id + ext)

    /** Ids of well-named .json files (not yet checked for content or expiry). */
    private fun jsonIds(): List<String> {
        val files = dir.listFiles() ?: return emptyList()
        val out = ArrayList<String>()
        for (f in files) {
            val name = f.name
            if (!name.endsWith(JSON_EXT)) continue
            val id = name.removeSuffix(JSON_EXT)
            if (HeldId.isValid(id)) out.add(id)
        }
        return out
    }

    private fun read(id: String, f: File): Held? {
        return try {
            val o = JSONObject(f.readText(Charsets.UTF_8))
            Held(id, o.getString("body"), o.getLong("heldAt"))
        } catch (e: IOException) {
            null
        } catch (e: JSONException) {
            null
        } catch (e: SecurityException) {
            null
        }
    }

    private fun write(id: String, body: String, heldAt: Long): Boolean {
        val tmp = fileOf(id, TMP_EXT)
        val dest = fileOf(id, JSON_EXT)
        try {
            val text = JSONObject().put("heldAt", heldAt).put("body", body).toString()
            FileOutputStream(tmp).use { out ->
                out.write(text.toByteArray(Charsets.UTF_8))
                out.flush()
                out.fd.sync()
            }
            if (!tmp.renameTo(dest)) {
                tmp.delete()
                return false
            }
            return true
        } catch (e: IOException) {
            tmp.delete()
            return false
        } catch (e: JSONException) {
            tmp.delete()
            return false
        } catch (e: SecurityException) {
            tmp.delete()
            return false
        }
    }
}
