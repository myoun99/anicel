package com.myoun.anicel

import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.MotionEvent
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap

// SAVE-1c: the storage channel - the Android real-path model.
//
// The app works on REAL file paths (the desktop model): the app's
// project home is the PUBLIC Documents folder (visible in 내 파일/Files
// apps). Shared storage needs All-Files access, granted through the
// system settings toggle this channel opens.
//
// PICK-7: a document with NO filesystem path behind it (Google Drive and
// its kind) is no longer turned away. It is handed to Dart as its URI,
// copied into the app to be worked on, and written back whole through the
// provider after each save - see ProviderDocuments on the Dart side.
class MainActivity : FlutterActivity() {
    // AUDIO-PRO R5: the mic grant is a system dialog whose answer arrives
    // in a callback; the channel result waits here for it.
    private var pendingMicResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "qa_storage",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAllFilesAccessGranted" -> result.success(isAllFilesAccessGranted())
                "requestAllFilesAccess" -> {
                    requestAllFilesAccess()
                    result.success(null)
                }
                "appDocumentsPath" -> result.success(appDocumentsPath())
                "requestMicrophone" -> requestMicrophone(result)
                "pickProjectFolder" ->
                    pickProjectFolder(call.argument<String>("initialDirectory"), result)
                "pickFiles" ->
                    pickFiles(
                        call.argument<List<String>>("mimeTypes") ?: emptyList(),
                        call.argument<Boolean>("allowMultiple") ?: false,
                        result,
                    )
                // Android hands out durable real paths, so there is no
                // bookmark to resolve and no scope to re-acquire. It
                // answers honestly rather than pretending.
                "exportFile" ->
                    exportFile(
                        call.argument<String>("sourcePath"),
                        call.argument<String>("suggestedName"),
                        result,
                    )
                "resolveBookmark" ->
                    result.success(mapOf("status" to "unavailable"))
                "copyDocument" ->
                    copyDocument(
                        call.argument<String>("uri"),
                        call.argument<String>("destinationPath"),
                        result,
                    )
                "cancelDocumentCopy" -> {
                    call.argument<String>("destinationPath")?.let {
                        cancelledTransfers.add(it)
                    }
                    result.success(null)
                }
                "writeDocument" ->
                    writeDocument(
                        call.argument<String>("uri"),
                        call.argument<String>("sourcePath"),
                        result,
                    )
                "documentTransferred" ->
                    result.success(transfers[call.argument<String>("path") ?: ""])
                else -> result.notImplemented()
            }
        }
    }

    // F-193 (user 2026-09-27, Android): a pen hovering over a tool button
    // and then lifted away left the button lit - its hover never ended.
    //
    // Flutter's Android embedding drops ACTION_HOVER_EXIT: FlutterView hands
    // the framework HOVER_MOVE and SCROLL only (its own TODO: "implementing
    // ADD, REMOVE"). So a pen leaving hover range is never said to have left,
    // and every MouseRegion it was over keeps its hover until the pen comes
    // back somewhere else. iOS (UIHoverGestureRecognizer's end) and Windows
    // (WM_POINTERLEAVE) do send the leave; this is the Android gap only.
    //
    // The exit is handed on as a hover FAR outside the window, in order with
    // the events around it - synchronously, before the ACTION_DOWN that
    // follows when the pen touches rather than leaves. The framework's hit
    // test finds nothing there and exits every region the pen was over,
    // exactly as a real leave would.
    override fun dispatchGenericMotionEvent(ev: MotionEvent): Boolean {
        val handled = super.dispatchGenericMotionEvent(ev)
        if (ev.actionMasked == MotionEvent.ACTION_HOVER_EXIT &&
            ev.getToolType(0) == MotionEvent.TOOL_TYPE_STYLUS
        ) {
            val flutterView: View? = findViewById(FlutterActivity.FLUTTER_VIEW_ID)
            if (flutterView != null) {
                val away = MotionEvent.obtain(ev)
                away.action = MotionEvent.ACTION_HOVER_MOVE
                away.setLocation(-100000f, -100000f)
                flutterView.onGenericMotionEvent(away)
                away.recycle()
            }
        }
        return handled
    }

    // PICK-2: the path grant. The Result waits here the same way the mic
    // grant does - the answer arrives in onActivityResult. ONE waiter for
    // both modes: only one picker can be on screen, and the request code
    // says which one came back.
    private var pendingPickResult: MethodChannel.Result? = null

    // 4801 and 4802 are taken by the two permission requests below.
    private val folderPickRequestCode = 4803
    private val filePickRequestCode = 4804
    private val exportRequestCode = 4805

    // PICK-2: asks the system for a folder, then converts what it hands back
    // into a REAL PATH.
    //
    // ACTION_OPEN_DOCUMENT_TREE returns a SAF tree Uri, and this app is
    // built on real paths end to end: incremental saves rewrite the single
    // `.anicel` ZIP's central directory in place, and carried-media reads
    // seek into it by offset. None of that survives a content:// Uri. So
    // the tree is used as a LOCATION CHOOSER only - the system UI picks the
    // folder, and the existing MANAGE_EXTERNAL_STORAGE grant is what
    // actually opens it.
    //
    // When no real path exists behind the choice (Drive and other document
    // providers), that is reported rather than papered over: a project saved
    // to a path the writer cannot edit in place would fail later and
    // silently.
    private fun pickProjectFolder(initialDirectory: String?, result: MethodChannel.Result) {
        // REFUSE a second pick rather than replacing the waiter. Replacing it
        // does not cancel the activity already on screen, and nothing ties a
        // result to its request - so picker #1's answer would be handed to
        // picker #2's caller and picker #2's own answer dropped. The user
        // would receive the folder they chose in the OTHER dialog.
        if (pendingPickResult != null) {
            result.success(mapOf("status" to "cancelled"))
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            // Open where the app lives rather than at "Internal storage".
            // Without this the user re-walks Internal storage > Documents >
            // Anicel on every save - a straight regression against the in-app
            // browser, which started at the app documents home.
            initialUriFor(initialDirectory)?.let {
                putExtra(android.provider.DocumentsContract.EXTRA_INITIAL_URI, it)
            }
        }
        launch(intent, folderPickRequestCode, result)
    }

    // PICK-5: files, by REAL PATH.
    //
    // file_selector reaches ACTION_OPEN_DOCUMENT too, but then copies the
    // document into getCacheDir() and returns the copy's path (its
    // FileUtils.getPathFromCopyOfFileFromUri, with deleteOnExit on the
    // directory). A media asset imported "by reference" therefore pointed at
    // a temporary duplicate that the next cache sweep removes - the original
    // was never referenced at all.
    //
    // This resolves the document Uri to the real file the way the folder
    // path already does, so a reference is a reference. MANAGE_EXTERNAL_STORAGE
    // is what makes that path readable afterwards.
    //
    // PICK-7: a document with no filesystem path behind it (Drive) is no
    // longer dropped. It comes back as its URI with the provider's name and
    // size, and Dart decides: a project opens it through a working copy, a
    // caller that needs a real file says why it cannot.
    private fun pickFiles(
        mimeTypes: List<String>,
        allowMultiple: Boolean,
        result: MethodChannel.Result,
    ) {
        if (pendingPickResult != null) {
            result.success(mapOf("status" to "cancelled"))
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // WRITE as well: a project opened from a document with no path
            // is saved back into it (PICK-7).
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
            // A single "*/*" with no EXTRA_MIME_TYPES is the "everything"
            // spelling; DocumentsUI greys out every file when the extra is
            // present but empty.
            type = if (mimeTypes.size == 1) mimeTypes.first() else "*/*"
            if (mimeTypes.size > 1) {
                putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
            }
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
        }
        launch(intent, filePickRequestCode, result)
    }

    // PICK-6: hands a finished file to the user's chosen location.
    //
    // Same contract as the Apple runners even though Android could hand back
    // a destination first: Dart writes into the app container and asks for
    // the file to be PLACED. One contract means Dart never learns that one
    // platform gives a file and another gives a path.
    //
    // ACTION_CREATE_DOCUMENT creates an empty document at the chosen spot;
    // the bytes are moved onto it below, through the real path, because the
    // save stack rewrites a ZIP in place and no content:// stream survives
    // that. Where the document has no real path (PICK-7) they are poured
    // into it through the provider instead.
    private var pendingExportSource: String? = null

    private fun exportFile(
        sourcePath: String?,
        suggestedName: String?,
        result: MethodChannel.Result,
    ) {
        if (sourcePath.isNullOrEmpty()) {
            result.success(mapOf("status" to "unavailable"))
            return
        }
        if (pendingPickResult != null) {
            result.success(mapOf("status" to "cancelled"))
            return
        }
        pendingPickResult = result
        pendingExportSource = sourcePath
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // The project's own type is not one the system knows, and an
            // unknown type makes some providers refuse to create at all.
            type = "application/octet-stream"
            putExtra(
                Intent.EXTRA_TITLE,
                suggestedName ?: java.io.File(sourcePath).name,
            )
        }
        launch(intent, exportRequestCode, result)
    }

    // Moves the staged bytes onto the document the user just created, and
    // reports the real path the save stack will keep writing to.
    //
    // Off the main thread: a project is hundreds of megabytes, and a copy
    // that long on the main thread is the system's "not responding". The
    // channel is answered back on the main thread.
    private fun finishExport(waiting: MethodChannel.Result, uri: Uri?) {
        val source = pendingExportSource
        pendingExportSource = null
        if (uri == null || source == null) {
            waiting.success(mapOf("status" to "cancelled"))
            return
        }
        takePersistable(uri, writable = true)
        val path = realPathFor(uri, isTree = false)
        Thread {
            val answer = if (path != null) {
                placeAtPath(source, path)
            } else {
                placeInDocument(source, uri)
            }
            answerOnMain(waiting, answer)
        }.start()
    }

    private fun placeAtPath(source: String, path: String): Map<String, Any?> {
        val moved = try {
            // copy+delete rather than renameTo: the container and the
            // destination can be different volumes, and renameTo answers
            // false there instead of throwing.
            java.io.File(source).copyTo(java.io.File(path), overwrite = true)
            java.io.File(source).delete()
            true
        } catch (_: Exception) {
            false
        }
        if (!moved) {
            return mapOf("status" to "unavailable")
        }
        return mapOf(
            "status" to "granted",
            "items" to listOf(mapOf("path" to path, "bookmark" to null)),
        )
    }

    // PICK-7: a created document with no filesystem path behind it (Drive).
    // The staged bytes are POURED into it through the provider, and the
    // staged file STAYS where it is: Dart decides whether it becomes this
    // document's working copy (Save As keeps saving there) or goes (an
    // export never writes again).
    private fun placeInDocument(source: String, uri: Uri): Map<String, Any?> {
        return try {
            pourIntoDocument(uri, java.io.File(source), source)
            mapOf("status" to "granted", "items" to listOf(documentItem(uri)))
        } catch (error: Exception) {
            mapOf("status" to "unavailable", "error" to describe(error))
        } finally {
            transfers.remove(source)
        }
    }

    // PICK-7: bytes moving between the app and a document with no
    // filesystem path, by the local path they come from or go to - the
    // count Dart polls for its progress line (`documentTransferred`).
    private val transfers = ConcurrentHashMap<String, Long>()

    // The copies Dart asked to stop, by destination path.
    private val cancelledTransfers: MutableSet<String> =
        Collections.newSetFromMap(ConcurrentHashMap<String, Boolean>())

    private val mainThread = Handler(Looper.getMainLooper())

    private fun answerOnMain(result: MethodChannel.Result, answer: Map<String, Any?>) {
        mainThread.post { result.success(answer) }
    }

    private fun describe(error: Exception): String =
        error.message ?: error.javaClass.simpleName

    // PICK-7: brings a document with no filesystem path into the app - the
    // working copy a project from Drive is opened and saved in. It lands in
    // a `.part` beside the destination and takes the name only when whole,
    // so a copy cut short never stands under it.
    private fun copyDocument(
        uri: String?,
        destinationPath: String?,
        result: MethodChannel.Result,
    ) {
        if (uri.isNullOrEmpty() || destinationPath.isNullOrEmpty()) {
            result.success(mapOf("status" to "unavailable"))
            return
        }
        cancelledTransfers.remove(destinationPath)
        transfers[destinationPath] = 0L
        Thread {
            val part = java.io.File("$destinationPath.part")
            val answer = try {
                val input = contentResolver.openInputStream(Uri.parse(uri))
                    ?: throw java.io.FileNotFoundException(uri)
                input.use { stream ->
                    java.io.FileOutputStream(part).use { output ->
                        pour(stream, output, destinationPath)
                    }
                }
                when {
                    cancelledTransfers.contains(destinationPath) ->
                        mapOf("status" to "cancelled")
                    part.renameTo(java.io.File(destinationPath)) ->
                        mapOf("status" to "granted", "items" to listOf(mapOf("path" to destinationPath)))
                    else -> mapOf("status" to "unavailable", "error" to "rename")
                }
            } catch (error: Exception) {
                if (cancelledTransfers.contains(destinationPath)) {
                    mapOf("status" to "cancelled")
                } else {
                    mapOf("status" to "unavailable", "error" to describe(error))
                }
            } finally {
                // Gone already when the rename took it.
                part.delete()
                transfers.remove(destinationPath)
                cancelledTransfers.remove(destinationPath)
            }
            answerOnMain(result, answer)
        }.start()
    }

    // PICK-7: hands a saved working copy back to its document, whole.
    private fun writeDocument(
        uri: String?,
        sourcePath: String?,
        result: MethodChannel.Result,
    ) {
        if (uri.isNullOrEmpty() || sourcePath.isNullOrEmpty()) {
            result.success(mapOf("status" to "unavailable"))
            return
        }
        transfers[sourcePath] = 0L
        Thread {
            val document = Uri.parse(uri)
            val answer = try {
                pourIntoDocument(document, java.io.File(sourcePath), sourcePath)
                mapOf("status" to "granted", "items" to listOf(documentItem(document)))
            } catch (error: Exception) {
                mapOf("status" to "unavailable", "error" to describe(error))
            } finally {
                transfers.remove(sourcePath)
            }
            answerOnMain(result, answer)
        }.start()
    }

    // Replaces a document's content with [source]'s bytes.
    //
    // "wt" first: plain "w" does not truncate on every provider, and a
    // shorter file written over a longer one keeps the old tail - for a
    // ZIP, the OLD central directory at the very end, which is the first
    // thing a reader finds. The length is cut to what was written as well,
    // wherever the descriptor has one; a provider that streams through a
    // pipe has none, and takes what arrived.
    private fun pourIntoDocument(uri: Uri, source: java.io.File, key: String) {
        val descriptor = openForReplacing(uri)
        try {
            // Not closed on its own: the descriptor below owns the fd, and
            // the length is cut after the last byte.
            val output = java.io.FileOutputStream(descriptor.fileDescriptor)
            val written = java.io.FileInputStream(source).use { input ->
                pour(input, output, key)
            }
            output.flush()
            try {
                android.system.Os.ftruncate(descriptor.fileDescriptor, written)
            } catch (_: Exception) {
                // A pipe has no length to cut.
            }
        } finally {
            descriptor.close()
        }
    }

    private fun openForReplacing(uri: Uri): android.os.ParcelFileDescriptor {
        var refusal: Exception? = null
        for (mode in listOf("wt", "w")) {
            try {
                contentResolver.openFileDescriptor(uri, mode)?.let { return it }
            } catch (error: Exception) {
                refusal = error
            }
        }
        throw refusal ?: java.io.FileNotFoundException(uri.toString())
    }

    // Copies [input] into [output] a megabyte at a time, counting what has
    // moved into [transfers] under [key], and stops at a cancel.
    private fun pour(
        input: java.io.InputStream,
        output: java.io.OutputStream,
        key: String,
    ): Long {
        val buffer = ByteArray(1 shl 20)
        var moved = 0L
        while (!cancelledTransfers.contains(key)) {
            val read = input.read(buffer)
            if (read < 0) {
                break
            }
            output.write(buffer, 0, read)
            moved += read
            transfers[key] = moved
        }
        return moved
    }

    // A document with no filesystem path, as Dart receives it: the URI the
    // provider answers to, and the name and size it gives. Either may be
    // missing - a provider is not obliged to say.
    private fun documentItem(uri: Uri): Map<String, Any?> {
        var name: String? = null
        var size: Long? = null
        try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    name = cursor.getString(0)
                    if (!cursor.isNull(1)) {
                        size = cursor.getLong(1)
                    }
                }
            }
        } catch (_: Exception) {
            // A provider that will not answer a query still hands out bytes.
        }
        return mapOf("uri" to uri.toString(), "name" to name, "size" to size)
    }

    private fun launch(intent: Intent, requestCode: Int, result: MethodChannel.Result) {
        try {
            startActivityForResult(intent, requestCode)
        } catch (_: Exception) {
            pendingPickResult = null
            result.success(mapOf("status" to "unavailable"))
        }
    }

    // Turns a real path back into the document Uri DocumentsUI accepts as a
    // starting point (honoured from API 26). Null when the path is not on
    // primary storage, in which case the picker opens where it last was.
    private fun initialUriFor(path: String?): Uri? {
        if (path.isNullOrEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return null
        }
        val root = Environment.getExternalStorageDirectory()?.absolutePath ?: return null
        val normalized = path.replace('\\', '/').trimEnd('/')
        if (!normalized.startsWith(root)) {
            return null
        }
        val relative = normalized.removePrefix(root).trimStart('/')
        return try {
            android.provider.DocumentsContract.buildDocumentUri(
                "com.android.externalstorage.documents",
                "primary:$relative",
            )
        } catch (_: Exception) {
            null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // MUST come first: FlutterActivity forwards activity results to the
        // plugin delegate here, and every plugin that opens an activity -
        // file_selector above all - stops returning if this is shadowed.
        super.onActivityResult(requestCode, resultCode, data)
        val isFolder = requestCode == folderPickRequestCode
        val isFile = requestCode == filePickRequestCode
        val isExport = requestCode == exportRequestCode
        if (!isFolder && !isFile && !isExport) {
            return
        }
        val waiting = pendingPickResult
        pendingPickResult = null
        if (waiting == null) {
            return
        }
        if (isExport) {
            finishExport(waiting, if (resultCode == RESULT_OK) data?.data else null)
            return
        }
        val uris = if (resultCode == RESULT_OK && data != null) {
            if (isFolder) listOfNotNull(data.data) else pickedDocumentUris(data)
        } else {
            emptyList()
        }
        if (uris.isEmpty()) {
            waiting.success(mapOf("status" to "cancelled"))
            return
        }
        val items = mutableListOf<Map<String, Any?>>()
        for (uri in uris) {
            takePersistable(uri, writable = true)
            // No bookmark: an Android path is durable on its own, which is
            // exactly what the Apple runners have to mint a token for.
            val path = realPathFor(uri, isFolder)
            if (path != null) {
                items.add(mapOf("path" to path, "bookmark" to null))
            } else if (!isFolder) {
                // PICK-7: a FILE with no path behind it is still a file the
                // provider reads and writes - handed over as the document.
                // A folder is not: nothing works through a tree yet.
                items.add(documentItem(uri))
            }
        }
        if (items.isEmpty()) {
            waiting.success(mapOf("status" to "noFilesystemPath"))
        } else {
            waiting.success(mapOf("status" to "granted", "items" to items))
        }
    }

    // Multi-select answers in getClipData; a single pick answers in getData.
    // Reading only the latter silently imported one file out of ten.
    private fun pickedDocumentUris(data: Intent): List<Uri> {
        val clip = data.clipData ?: return listOfNotNull(data.data)
        return (0 until clip.itemCount).mapNotNull { clip.getItemAt(it)?.uri }
    }

    // Keep the grant across restarts. A document with no filesystem path
    // (PICK-7) is reopened from Recents through its URI, and this grant is
    // what lets the next launch read it and save back into it. It is not,
    // as an earlier comment here claimed, shown to the user anywhere in
    // Settings.
    //
    // Read AND write where the provider gave both; read alone where it
    // did not - persisting a flag the grant does not carry throws.
    private fun takePersistable(uri: Uri, writable: Boolean) {
        val read = Intent.FLAG_GRANT_READ_URI_PERMISSION
        val attempts = if (writable) {
            listOf(read or Intent.FLAG_GRANT_WRITE_URI_PERMISSION, read)
        } else {
            listOf(read)
        }
        for (flags in attempts) {
            try {
                contentResolver.takePersistableUriPermission(uri, flags)
                return
            } catch (_: Exception) {
                // Not every provider offers a persistable grant.
            }
        }
    }

    // Resolves a SAF Uri to a filesystem path, or null when none exists.
    // [isTree] tells the two shapes apart: a tree from
    // ACTION_OPEN_DOCUMENT_TREE must land on a directory, a document from
    // ACTION_OPEN_DOCUMENT on a file. The id lives under a different accessor
    // for each, and reading the wrong one throws.
    //
    // A document id looks like "<volume>:<relative>". The volume is asked of
    // the SYSTEM rather than guessed, because guessing gets three cases
    // wrong:
    //
    //   "primary"  internal shared storage.
    //   "home"     the Documents root that AOSP's ExternalStorageProvider
    //              registers on API 24-29 - which is where this app's own
    //              default project home lives, so refusing it meant refusing
    //              Documents/Anicel on every device below Android 11.
    //   <fs-uuid>  an SD card or USB volume. StorageManager knows its mount
    //              point, and MANAGE_EXTERNAL_STORAGE opens it, so calling
    //              these "unresolvable" sent Galaxy Tab users with a microSD
    //              card to the cloud-sync advice for storage that works.
    //
    // A Drive or Dropbox provider does not use this authority at all, and
    // that is the case that genuinely has no path.
    private fun realPathFor(uri: Uri, isTree: Boolean): String? {
        if (uri.authority != "com.android.externalstorage.documents") {
            return if (isTree) null else sharedStoragePathFor(uri)
        }
        val documentId = try {
            if (isTree) {
                android.provider.DocumentsContract.getTreeDocumentId(uri)
            } else {
                android.provider.DocumentsContract.getDocumentId(uri)
            }
        } catch (_: Exception) {
            return null
        }
        val separator = documentId.indexOf(':')
        if (separator < 0) {
            return null
        }
        val volume = documentId.substring(0, separator)
        val relative = documentId.substring(separator + 1)
        val root = rootForVolume(volume) ?: return null
        val resolved = if (relative.isEmpty()) root else java.io.File(root, relative)
        // The grant is what makes this readable; if it is missing the probe
        // fails here rather than at save (or at first decode) time.
        val matches = if (isTree) resolved.isDirectory else resolved.isFile
        return if (matches) resolved.absolutePath else null
    }

    // PICK-7: a file on shared storage that the picker handed out through
    // ANOTHER provider. The picker's Recent, Downloads and category tabs
    // answer through the downloads and media providers rather than through
    // "internal storage", so a file in the tablet's own storage came back
    // as "no folder path" - the Drive notice, for a local file (유저
    // 2026-09-27, Galaxy Tab: 「로컬에 있는파일 열려고해도 같은메시지뜨고
    // 안열려」). MediaStore knows where those files live, and the All-Files
    // grant opens the path - no copy, and saves stay incremental.
    //
    // Asked of the document's own provider (MediaStore.getMediaUri) rather
    // than read out of its ids, which are private to it. A provider with no
    // file behind the document (Drive) cannot answer, and that document
    // goes on as one (documentItem).
    private fun sharedStoragePathFor(uri: Uri): String? {
        val documentId = try {
            DocumentsContract.getDocumentId(uri)
        } catch (_: Exception) {
            return null
        }
        if (uri.authority == "com.android.providers.downloads.documents" &&
            documentId.startsWith("raw:")
        ) {
            return existingFile(documentId.removePrefix("raw:"))
        }
        val mediaUri = mediaUriFor(uri, documentId) ?: return null
        val path = try {
            // "_data" by name: the constant is deprecated for writing, and
            // reading it is exactly what All-Files access is for.
            contentResolver.query(mediaUri, arrayOf("_data"), null, null, null)
                ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        } catch (_: Exception) {
            null
        }
        return path?.let { existingFile(it) }
    }

    private fun mediaUriFor(uri: Uri, documentId: String): Uri? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return try {
                MediaStore.getMediaUri(this, uri)
            } catch (_: Exception) {
                null
            }
        }
        // Before Android 10 there is no such question, and the two system
        // providers' ids are the only way in: "<type>:<id>" for media, a
        // bare number for downloads.
        return when (uri.authority) {
            "com.android.providers.media.documents" -> {
                val id = documentId.substringAfter(':').toLongOrNull() ?: return null
                ContentUris.withAppendedId(MediaStore.Files.getContentUri("external"), id)
            }
            "com.android.providers.downloads.documents" -> {
                val id = documentId.toLongOrNull() ?: return null
                ContentUris.withAppendedId(
                    Uri.parse("content://downloads/public_downloads"),
                    id,
                )
            }
            else -> null
        }
    }

    private fun existingFile(path: String): String? {
        val file = java.io.File(path)
        return if (file.isFile) file.absolutePath else null
    }

    private fun rootForVolume(volume: String): java.io.File? {
        if (volume.equals("primary", ignoreCase = true)) {
            return Environment.getExternalStorageDirectory()
        }
        if (volume.equals("home", ignoreCase = true)) {
            return Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOCUMENTS
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val storage = getSystemService(android.os.storage.StorageManager::class.java)
            val match = storage?.storageVolumes?.firstOrNull {
                it.uuid?.equals(volume, ignoreCase = true) == true
            }
            return match?.directory
        }
        return null
    }

    private fun isMicrophoneGranted(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    // Answers true/false AFTER the user has spoken - an already-granted
    // (or pre-M) device answers immediately.
    private fun requestMicrophone(result: MethodChannel.Result) {
        if (isMicrophoneGranted()) {
            result.success(true)
            return
        }
        // A second tap while the dialog is up: answer the stale waiter
        // rather than leaking it.
        pendingMicResult?.success(false)
        pendingMicResult = result
        requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), 4802)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4802) {
            pendingMicResult?.success(
                grantResults.isNotEmpty() &&
                    grantResults[0] ==
                        android.content.pm.PackageManager.PERMISSION_GRANTED
            )
            pendingMicResult = null
        }
    }

    private fun isAllFilesAccessGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            // Pre-R shared storage is reachable with the legacy WRITE
            // permission; the app targets modern tablets, so the simple
            // answer keeps the channel honest.
            checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestAllFilesAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // The system settings screen with this app preselected; falls
            // back to the generic list when the direct route is missing.
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:$packageName"),
                    )
                )
            } catch (_: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else {
            requestPermissions(
                arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE),
                4801,
            )
        }
    }

    private fun appDocumentsPath(): String {
        // The PUBLIC Documents folder - a location every file manager
        // shows (the spec's 앱 문서 폴더). Falls back to the app's own
        // external dir when the public one is unavailable.
        val documents =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        val base = if (documents != null && (documents.exists() || documents.mkdirs())) {
            documents
        } else {
            getExternalFilesDir(null) ?: filesDir
        }
        return "${base.absolutePath}/Anicel"
    }
}
