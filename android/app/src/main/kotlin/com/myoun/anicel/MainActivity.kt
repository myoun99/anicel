package com.myoun.anicel

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// SAVE-1c: the storage channel - the Android real-path model.
//
// The app works on REAL file paths (the desktop model): the app's
// project home is the PUBLIC Documents folder (visible in 내 파일/Files
// apps), and cloud folders arrive as sync-app mirror folders in shared
// storage. Both need All-Files access, granted through the system
// settings toggle this channel opens.
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
                else -> result.notImplemented()
            }
        }
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
    // built on real paths end to end: incremental saves rewrite a ZIP's
    // central directory in place, the autosave sidecar is a sibling file,
    // and <project>.assets/ is a real directory tree. None of that survives
    // a content:// Uri. So the tree is used as a LOCATION CHOOSER only - the
    // system UI picks the folder, and the existing MANAGE_EXTERNAL_STORAGE
    // grant is what actually opens it.
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
    // is what makes that path readable afterwards; a provider with no
    // filesystem behind it (Drive) is reported rather than papered over.
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
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
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
    // that.
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
    private fun finishExport(waiting: MethodChannel.Result, uri: Uri?) {
        val source = pendingExportSource
        pendingExportSource = null
        if (uri == null || source == null) {
            waiting.success(mapOf("status" to "cancelled"))
            return
        }
        takePersistable(uri, writable = true)
        val path = realPathFor(uri, isTree = false)
        if (path == null) {
            // A provider with no filesystem behind it (Drive). Reported
            // rather than papered over: an in-place ZIP rewrite would fail
            // later and silently.
            waiting.success(mapOf("status" to "noFilesystemPath"))
            return
        }
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
            waiting.success(mapOf("status" to "unavailable"))
            return
        }
        waiting.success(
            mapOf(
                "status" to "granted",
                "items" to listOf(mapOf("path" to path, "bookmark" to null)),
            )
        )
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
            takePersistable(uri, writable = isFolder)
            // No bookmark: an Android path is durable on its own, which is
            // exactly what the Apple runners have to mint a token for.
            realPathFor(uri, isFolder)?.let {
                items.add(mapOf("path" to it, "bookmark" to null))
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

    // Keep the grant across restarts. It buys nothing TODAY - the app uses
    // the real path and never touches the Uri again - and is taken only so a
    // future content:// fallback has something to resume from. It is not, as
    // an earlier comment here claimed, shown to the user anywhere in
    // Settings.
    //
    // Read-only for files: ACTION_OPEN_DOCUMENT was not asked for write
    // access, and persisting a flag the grant does not carry throws.
    private fun takePersistable(uri: Uri, writable: Boolean) {
        val flags = if (writable) {
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        } else {
            Intent.FLAG_GRANT_READ_URI_PERMISSION
        }
        try {
            contentResolver.takePersistableUriPermission(uri, flags)
        } catch (_: Exception) {
            // Not every provider offers a persistable grant.
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
            return null
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
