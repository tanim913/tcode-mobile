package dev.tcode.mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException
import java.util.concurrent.Executors

/**
 * Storage Access Framework, exposed to Dart as one method channel.
 *
 * Design notes that matter:
 *
 *  * Every filesystem call runs on a background executor. `DocumentsContract`
 *    queries hit a ContentProvider in another process; on the main thread a
 *    folder with a few hundred entries is a visible stall.
 *  * Listing uses a single `query()` over the children URI, not
 *    `DocumentFile.listFiles()`. The latter issues one IPC round trip per child
 *    and is the usual reason SAF file managers feel slow.
 *  * Permission is taken persistably, so a workspace survives a reboot. Without
 *    that the picked folder stops working the moment the process dies.
 *  * Errors are returned as channel errors with a stable code, which the Dart
 *    side maps to the app's own `AppFailure` types.
 */
class SafPlugin(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.tcode.mobile/saf"
        private const val REQUEST_OPEN_TREE = 0x5AF0

        private val COLUMNS = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
    }

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** Held while the system picker is up; there can only be one. */
    private var pendingPick: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickTree" -> pickTree(result)
            "persistedRoots" -> background(result) { persistedRoots() }
            "releaseRoot" -> background(result) { releaseRoot(call.arg("uri")) }
            "list" -> background(result) { list(call.arg("uri")) }
            "stat" -> background(result) { stat(call.arg("uri")) }
            "readBytes" -> background(result) { readBytes(call.arg("uri")) }
            "writeBytes" -> background(result) {
                writeBytes(call.arg("uri"), call.argument<ByteArray>("bytes")!!)
            }
            "createFile" -> background(result) {
                create(call.arg("parent"), call.arg("name"), false)
            }
            "createFolder" -> background(result) {
                create(call.arg("parent"), call.arg("name"), true)
            }
            "rename" -> background(result) {
                rename(call.arg("uri"), call.arg("name"))
            }
            "delete" -> background(result) { delete(call.arg("uri")) }
            "exists" -> background(result) { exists(call.arg("uri")) }
            "openWith" -> openWith(call.arg("path"), call.arg("mime"), result)
            else -> result.notImplemented()
        }
    }

    private fun <T> MethodCall.arg(name: String): T = argument<T>(name)!!

    /**
     * Runs [work] off the main thread and replies on it.
     *
     * A `work` lambda that returns nothing yields `kotlin.Unit`, which Flutter's
     * StandardMessageCodec cannot encode — it throws on the main thread and
     * takes the whole process down. Void results must be sent as `null`.
     */
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(if (value is Unit) null else value) }
            } catch (e: SecurityException) {
                main.post { result.error("permission", e.message, null) }
            } catch (e: FileNotFoundException) {
                main.post { result.error("not_found", e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("io", e.message, null) }
            }
        }
    }

    // --- Picking --------------------------------------------------------------

    private fun pickTree(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "A folder picker is already open", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        activity.startActivityForResult(intent, REQUEST_OPEN_TREE)
    }

    /** Returns true when this plugin consumed the result. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_OPEN_TREE) return false
        val result = pendingPick ?: return true
        pendingPick = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            // Dismissing the picker is not an error; Dart treats null as
            // "cancelled" and leaves the current workspace alone.
            result.success(null)
            return true
        }

        return try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            result.success(describeTree(uri))
            true
        } catch (e: SecurityException) {
            result.error("permission", e.message, null)
            true
        }
    }

    // --- Roots ----------------------------------------------------------------

    /** Tree URIs still granted to this app, for restoring a saved session. */
    private fun persistedRoots(): List<Map<String, Any?>> =
        activity.contentResolver.persistedUriPermissions
            .filter { it.isReadPermission }
            .map { describeTree(it.uri) }

    private fun releaseRoot(uri: String) {
        activity.contentResolver.releasePersistableUriPermission(
            Uri.parse(uri),
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )
    }

    /**
     * A tree URI and the document URI for its root, which are different shapes:
     * the tree URI identifies the grant, the document URI identifies the folder.
     */
    private fun describeTree(tree: Uri): Map<String, Any?> {
        val documentId = DocumentsContract.getTreeDocumentId(tree)
        val document = DocumentsContract.buildDocumentUriUsingTree(tree, documentId)
        return mapOf(
            "treeUri" to tree.toString(),
            "uri" to document.toString(),
            "name" to (queryName(document) ?: documentId.substringAfterLast('/')),
        )
    }

    private fun queryName(document: Uri): String? =
        activity.contentResolver.query(
            document,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null,
        )?.use { if (it.moveToFirst()) it.getString(0) else null }

    // --- Reading --------------------------------------------------------------

    private fun list(uri: String): List<Map<String, Any?>> {
        val document = Uri.parse(uri)
        val tree = DocumentsContract.getTreeDocumentId(document)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            document,
            DocumentsContract.getDocumentId(document),
        )
        val out = ArrayList<Map<String, Any?>>()
        activity.contentResolver.query(children, COLUMNS, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                val id = c.getString(0)
                val mime = c.getString(2)
                out.add(
                    mapOf(
                        "uri" to DocumentsContract
                            .buildDocumentUriUsingTree(document, id).toString(),
                        "name" to c.getString(1),
                        "isDirectory" to (mime == DocumentsContract.Document.MIME_TYPE_DIR),
                        "size" to c.getLong(3),
                        "modified" to c.getLong(4),
                    ),
                )
            }
        } ?: throw FileNotFoundException("Cannot list $uri (tree $tree)")
        return out
    }

    private fun stat(uri: String): Map<String, Any?> {
        val document = Uri.parse(uri)
        activity.contentResolver.query(document, COLUMNS, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val mime = c.getString(2)
                return mapOf(
                    "uri" to uri,
                    "name" to c.getString(1),
                    "isDirectory" to (mime == DocumentsContract.Document.MIME_TYPE_DIR),
                    "size" to c.getLong(3),
                    "modified" to c.getLong(4),
                )
            }
        }
        throw FileNotFoundException(uri)
    }

    private fun exists(uri: String): Boolean = try {
        stat(uri); true
    } catch (_: Exception) {
        false
    }

    private fun readBytes(uri: String): ByteArray =
        activity.contentResolver.openInputStream(Uri.parse(uri))?.use { it.readBytes() }
            ?: throw FileNotFoundException(uri)

    // --- Writing --------------------------------------------------------------

    private fun writeBytes(uri: String, bytes: ByteArray) {
        // "wt" truncates. Without the t an existing longer file keeps its tail,
        // which silently corrupts every save that shortens a file.
        activity.contentResolver.openOutputStream(Uri.parse(uri), "wt")?.use {
            it.write(bytes)
            it.flush()
        } ?: throw FileNotFoundException(uri)
    }

    private fun create(parent: String, name: String, folder: Boolean): String {
        val parentUri = Uri.parse(parent)
        val mime = if (folder) {
            DocumentsContract.Document.MIME_TYPE_DIR
        } else {
            "application/octet-stream"
        }
        return DocumentsContract
            .createDocument(activity.contentResolver, parentUri, mime, name)
            ?.toString()
            ?: throw FileNotFoundException("Could not create $name in $parent")
    }

    private fun rename(uri: String, name: String): String =
        DocumentsContract
            .renameDocument(activity.contentResolver, Uri.parse(uri), name)
            ?.toString()
            ?: throw FileNotFoundException(uri)

    // --- Open with ------------------------------------------------------------

    /**
     * Hands [path] to another app with ACTION_VIEW.
     *
     * The file must already live under the cache's `shared/` directory, which
     * is the only path the FileProvider exposes — Dart copies it there first so
     * no other app ever receives a handle on the user's working file.
     */
    private fun openWith(path: String, mime: String, result: MethodChannel.Result) {
        try {
            val file = java.io.File(path)
            val uri = androidx.core.content.FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            // Refuse rather than crash when the device has nothing that opens
            // this type; Dart turns the false into a readable message.
            if (intent.resolveActivity(activity.packageManager) == null) {
                result.success(false)
                return
            }
            activity.startActivity(Intent.createChooser(intent, null))
            result.success(true)
        } catch (e: Exception) {
            result.error("io", e.message, null)
        }
    }

    private fun delete(uri: String) {
        if (!DocumentsContract.deleteDocument(activity.contentResolver, Uri.parse(uri))) {
            throw FileNotFoundException(uri)
        }
    }
}
