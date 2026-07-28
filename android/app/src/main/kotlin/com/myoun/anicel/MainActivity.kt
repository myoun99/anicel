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
                else -> result.notImplemented()
            }
        }
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
