package app.mmogo

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * MethodChannel `app.mmogo/storage` (architecture D4). Folder picker and file
 * access through the Storage Access Framework, no permissions needed.
 *
 * Contract: nothing here throws across the channel. Every failure is answered
 * once, as `result.error(code, ...)` with code `grantLost`, `tooLarge` or `io`.
 * A cancelled picker answers `null`. Only one picker may be pending at a time.
 */
class StorageBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "app.mmogo/storage"
        const val URL_SITE = "https://joshynsky.github.io/mmogo/"
        const val URL_ISSUES = "https://github.com/Joshynsky/mmogo/issues"
        private const val REQ_FOLDER = 7101
        private const val REQ_FILE = 7102
    }

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var pendingMaxBytes = 0L

    private class Fail(val code: String, message: String) : Exception(message)

    private fun reply(result: MethodChannel.Result, block: () -> Any?) {
        // Runs on the calling thread; always answers exactly once.
        try {
            result.success(block())
        } catch (f: Fail) {
            result.error(f.code, f.message, null)
        } catch (e: SecurityException) {
            result.error("grantLost", e.message, null)
        } catch (e: Throwable) {
            result.error("io", e.message, null)
        }
    }

    /** Runs [block] off the main thread and answers [result] on the main thread. */
    private fun async(result: MethodChannel.Result, block: () -> Any?) {
        try {
            worker.execute {
                var value: Any? = null
                var failure: Fail? = null
                try {
                    value = block()
                } catch (f: Fail) {
                    failure = f
                } catch (e: SecurityException) {
                    failure = Fail("grantLost", e.message ?: "grant lost")
                } catch (e: Throwable) {
                    failure = Fail("io", e.message ?: "io error")
                }
                main.post {
                    try {
                        if (failure != null) result.error(failure.code, failure.message, null)
                        else result.success(value)
                    } catch (_: Throwable) {
                    }
                }
            }
        } catch (e: Throwable) {
            result.error("io", e.message, null)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pickFolder" -> pickFolder(result)
                "hasWriteGrant" -> {
                    val tree = arg(call, "treeUri")
                    async(result) { hasWriteGrant(tree) }
                }
                "releaseGrant" -> {
                    val tree = arg(call, "treeUri")
                    reply(result) { releaseGrant(tree); null }
                }
                "createFile" -> {
                    val tree = arg(call, "treeUri")
                    val name = arg(call, "name")
                    val bytes = call.argument<ByteArray>("bytes") ?: throw Fail("io", "missing bytes")
                    async(result) { createFile(tree, name, bytes) }
                }
                "listFiles" -> {
                    val tree = arg(call, "treeUri")
                    async(result) { listFiles(tree) }
                }
                "deleteFile" -> {
                    val doc = arg(call, "docUri")
                    async(result) { deleteFile(doc) }
                }
                "pickFile" -> {
                    val max = call.argument<Number>("maxBytes")?.toLong() ?: throw Fail("io", "missing maxBytes")
                    pickFile(result, max)
                }
                "openUrl" -> reply(result) { openUrl(call.argument<String>("url")) }
                else -> result.notImplemented()
            }
        } catch (f: Fail) {
            result.error(f.code, f.message, null)
        } catch (e: Throwable) {
            result.error("io", e.message, null)
        }
    }

    private fun arg(call: MethodCall, key: String): String =
        call.argument<String>(key)?.takeIf { it.isNotEmpty() } ?: throw Fail("io", "missing $key")

    // ---- pickers -------------------------------------------------------

    private fun startPicker(result: MethodChannel.Result, intent: Intent, request: Int) {
        if (pending != null) throw Fail("io", "another picker is open")
        pending = result
        try {
            activity.startActivityForResult(intent, request)
        } catch (e: Throwable) {
            pending = null
            throw Fail("io", e.message ?: "cannot open picker")
        }
    }

    private fun pickFolder(result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        startPicker(result, intent, REQ_FOLDER)
    }

    private fun pickFile(result: MethodChannel.Result, maxBytes: Long) {
        if (maxBytes < 0) throw Fail("io", "bad maxBytes")
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        pendingMaxBytes = maxBytes
        startPicker(result, intent, REQ_FILE)
    }

    /** Called from MainActivity.onActivityResult. Returns true when it was ours. */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_FOLDER && requestCode != REQ_FILE) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // cancelled
            return true
        }
        if (requestCode == REQ_FOLDER) {
            reply(result) {
                activity.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
                mapOf("uri" to uri.toString(), "name" to folderName(uri))
            }
        } else {
            val max = pendingMaxBytes
            async(result) { readPicked(uri, max) }
        }
        return true
    }

    private fun folderName(tree: Uri): String {
        try {
            val doc = treeDocUri(tree)
            activity.contentResolver.query(doc, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
                ?.use { if (it.moveToFirst()) it.getString(0)?.let { n -> if (n.isNotEmpty()) return n } }
        } catch (_: Throwable) {
        }
        return Uri.decode(tree.lastPathSegment ?: "").substringAfterLast(':').ifEmpty { "Folder" }
    }

    private fun readPicked(uri: Uri, maxBytes: Long): Map<String, Any?> {
        val resolver = activity.contentResolver
        var name = ""
        resolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) name = it.getString(0) ?: "" }
        val limit = maxBytes + 1
        val out = ByteArrayOutputStream()
        val input = resolver.openInputStream(uri) ?: throw Fail("io", "cannot open file")
        input.use { s ->
            val buf = ByteArray(8192)
            var total = 0L
            while (total < limit) {
                val n = s.read(buf, 0, minOf(buf.size.toLong(), limit - total).toInt())
                if (n < 0) break
                out.write(buf, 0, n)
                total += n
            }
            if (total > maxBytes) throw Fail("tooLarge", "file is larger than $maxBytes bytes")
        }
        return mapOf("name" to name, "bytes" to out.toByteArray())
    }

    // ---- folder access -------------------------------------------------

    private fun treeDocUri(tree: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))

    private fun hasWriteGrant(treeUri: String): Boolean {
        val tree = Uri.parse(treeUri)
        val held = activity.contentResolver.persistedUriPermissions.any { it.uri == tree && it.isWritePermission }
        if (!held) return false
        return try {
            activity.contentResolver.query(
                treeDocUri(tree), arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null
            )?.use { it.moveToFirst() } ?: false
        } catch (_: Throwable) {
            false
        }
    }

    private fun releaseGrant(treeUri: String) {
        try {
            activity.contentResolver.releasePersistableUriPermission(
                Uri.parse(treeUri),
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (_: Throwable) {
            // Already released or never held: nothing to undo.
        }
    }

    /** Creates a NEW document and writes it; never opens an existing document for write. */
    private fun createFile(treeUri: String, name: String, bytes: ByteArray): String {
        val resolver = activity.contentResolver
        val tree = Uri.parse(treeUri)
        if (!hasWriteGrant(treeUri)) throw Fail("grantLost", "folder access is gone")
        val doc = DocumentsContract.createDocument(resolver, treeDocUri(tree), "application/json", name)
            ?: throw Fail("io", "cannot create file")
        try {
            val out = resolver.openOutputStream(doc, "w") ?: throw Fail("io", "cannot open file")
            out.use { it.write(bytes); it.flush() }
            var size = -1L
            resolver.query(doc, arrayOf(DocumentsContract.Document.COLUMN_SIZE), null, null, null)
                ?.use { if (it.moveToFirst() && !it.isNull(0)) size = it.getLong(0) }
            if (size != bytes.size.toLong()) throw Fail("io", "written size $size, expected ${bytes.size}")
            return doc.toString()
        } catch (e: Throwable) {
            try {
                DocumentsContract.deleteDocument(resolver, doc)
            } catch (_: Throwable) {
            }
            throw e
        }
    }

    private fun listFiles(treeUri: String): List<Map<String, Any?>> {
        val tree = Uri.parse(treeUri)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val cols = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        val rows = ArrayList<Map<String, Any?>>()
        val cursor = activity.contentResolver.query(children, cols, null, null, null)
            ?: throw Fail("io", "cannot list folder")
        cursor.use {
            while (it.moveToNext()) {
                if (it.getString(4) == DocumentsContract.Document.MIME_TYPE_DIR) continue
                rows.add(
                    mapOf(
                        "name" to (it.getString(1) ?: ""),
                        "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, it.getString(0)).toString(),
                        "size" to (if (it.isNull(2)) 0L else it.getLong(2)),
                        "lastModified" to (if (it.isNull(3)) 0L else it.getLong(3)),
                    )
                )
            }
        }
        return rows
    }

    private fun deleteFile(docUri: String) {
        if (!DocumentsContract.deleteDocument(activity.contentResolver, Uri.parse(docUri))) {
            throw Fail("io", "delete failed")
        }
    }

    // ---- links ---------------------------------------------------------

    private fun openUrl(url: String?): Boolean {
        if (url != URL_SITE && url != URL_ISSUES) return false
        return try {
            activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }
}
