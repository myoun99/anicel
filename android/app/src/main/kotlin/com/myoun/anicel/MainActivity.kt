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
                "pickProjectFolder" -> pickProjectFolder(result)
                // Android hands out durable real paths, so there is no
                // bookmark to resolve and no scope to re-acquire. Both
                // answer honestly rather than pretending.
                "resolveFolderBookmark" ->
                    result.success(mapOf("status" to "unavailable"))
                "ensureFolderAccess" ->
                    result.success(
                        (call.argument<String>("path") ?: "").let {
                            it.isNotEmpty() && java.io.File(it).isDirectory
                        }
                    )
                else -> result.notImplemented()
            }
        }
    }

    // PICK-2: the folder grant. The Result waits here the same way the mic
    // grant does - the answer arrives in onActivityResult.
    private var pendingFolderResult: MethodChannel.Result? = null

    // 4801 and 4802 are taken by the two permission requests below.
    private val folderPickRequestCode = 4803

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
    // providers, SD cards, USB), that is reported rather than papered over:
    // a project saved to a path the writer cannot edit in place would fail
    // later and silently.
    private fun pickProjectFolder(result: MethodChannel.Result) {
        // A second request while one is open answers the first rather than
        // leaking it - the same discipline requestMicrophone uses.
        pendingFolderResult?.success(mapOf("status" to "cancelled"))
        pendingFolderResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        }
        try {
            startActivityForResult(intent, folderPickRequestCode)
        } catch (_: Exception) {
            pendingFolderResult = null
            result.success(mapOf("status" to "unavailable"))
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // MUST come first: FlutterActivity forwards activity results to the
        // plugin delegate here, and every plugin that opens an activity -
        // file_selector above all - stops returning if this is shadowed.
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != folderPickRequestCode) {
            return
        }
        val waiting = pendingFolderResult
        pendingFolderResult = null
        if (waiting == null) {
            return
        }
        val tree = data?.data
        if (resultCode != RESULT_OK || tree == null) {
            waiting.success(mapOf("status" to "cancelled"))
            return
        }
        // Keep the grant across restarts. Harmless when the real path is
        // what ends up being used, and it keeps the choice visible in the
        // system's permission list.
        try {
            contentResolver.takePersistableUriPermission(
                tree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: Exception) {
            // Not every provider offers a persistable grant; the real path
            // below is what this app actually uses.
        }
        val path = realPathForTree(tree)
        if (path == null) {
            waiting.success(mapOf("status" to "noFilesystemPath"))
        } else {
            // No bookmark: an Android path is durable on its own.
            waiting.success(mapOf("status" to "granted", "path" to path))
        }
    }

    // Resolves a SAF tree Uri to a filesystem path, or null when none
    // exists.
    //
    // Only primary shared storage is resolvable. A document id looks like
    // "primary:Documents/Anicel"; the part before the colon names the
    // volume, and anything other than "primary" is an SD card or USB stick
    // whose mount point cannot be derived reliably. A Drive or Dropbox
    // provider does not use this authority at all.
    private fun realPathForTree(tree: Uri): String? {
        if (tree.authority != "com.android.externalstorage.documents") {
            return null
        }
        val documentId = try {
            android.provider.DocumentsContract.getTreeDocumentId(tree)
        } catch (_: Exception) {
            return null
        }
        val separator = documentId.indexOf(':')
        if (separator < 0) {
            return null
        }
        val volume = documentId.substring(0, separator)
        val relative = documentId.substring(separator + 1)
        if (!volume.equals("primary", ignoreCase = true)) {
            return null
        }
        val root = Environment.getExternalStorageDirectory() ?: return null
        val resolved = if (relative.isEmpty()) {
            root
        } else {
            java.io.File(root, relative)
        }
        // The grant is what makes this readable; if it is missing the
        // directory probe fails here rather than at save time.
        return if (resolved.isDirectory) resolved.absolutePath else null
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
