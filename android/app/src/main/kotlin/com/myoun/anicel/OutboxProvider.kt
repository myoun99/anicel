package com.myoun.anicel

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileNotFoundException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

// drive-folder-windows-Q1 (user 2026-09-27: "hand the outputs over to Drive
// when the export is done - through a file window"): Android's road for
// SEVERAL finished outputs. No system window places more than one file, so
// they leave through the share sheet, where Drive's "Save to Drive" takes
// them. A share hands out content:// URIs, and only a provider answers
// those.
//
// This one answers for exactly the files MainActivity.shareFiles offered in
// this process, by a token minted per offer - never for a path the URI
// names, so no URI can reach any other file of the app. Read-only.
class OutboxProvider : ContentProvider() {
    companion object {
        private val offered = ConcurrentHashMap<String, File>()

        fun offer(authority: String, file: File): Uri {
            val token = UUID.randomUUID().toString()
            offered[token] = file
            // The name rides along as the last segment for readers that take
            // it from the path; the display-name column is the real answer.
            return Uri.Builder()
                .scheme("content")
                .authority(authority)
                .appendPath(token)
                .appendPath(file.name)
                .build()
        }

        fun mimeTypeOf(file: File): String =
            MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(file.extension.lowercase())
                ?: "application/octet-stream"
    }

    override fun onCreate(): Boolean = true

    private fun fileOf(uri: Uri): File? =
        uri.pathSegments.firstOrNull()?.let { offered[it] }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? {
        val file = fileOf(uri) ?: return null
        val columns = projection
            ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val row = columns.map {
            when (it) {
                OpenableColumns.DISPLAY_NAME -> file.name
                OpenableColumns.SIZE -> file.length()
                else -> null
            }
        }
        return MatrixCursor(columns, 1).apply { addRow(row) }
    }

    override fun getType(uri: Uri): String? = fileOf(uri)?.let { mimeTypeOf(it) }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val file = fileOf(uri) ?: throw FileNotFoundException(uri.toString())
        if (mode != "r") {
            throw SecurityException("The outbox is read-only")
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(
        uri: Uri,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0
}
