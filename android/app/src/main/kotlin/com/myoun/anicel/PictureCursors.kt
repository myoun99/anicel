package com.myoun.anicel

import android.graphics.Bitmap
import android.view.PointerIcon
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer

// I-54 ⓔ · F-441: the cursors of one size - the pen, the fill's bucket, the
// eyedropper - as the system's own (user 2026-09-30: 「os커서를 바꿈으로서
// 앱이랑 관계없이 빠르게」). This engine takes no picture for a cursor - its
// mouse cursor handler sets the system's kinds alone - so the runner does,
// over 'anicel/cursor' with the two calls Windows's engine takes
// (lib/src/ui/brush/drawing_cursor.dart): a picture is made once a look and
// size and answered with its name, then worn by that name. It comes as
// premultiplied RGBA in the screen's pixels, which is what a pointer icon's
// bitmap holds.
//
// ⚠️Worn as the view's pointer icon, where the engine's handler wears its
// own - and that icon is a MOUSE's: a pen hovering is shown what the view
// resolves for a pen, which Flutter's view leaves to the system. So Dart
// draws the cursor itself for a pen (`systemShowsCursorFor`).
//
// UNVERIFIED-ON-DEVICE: authored on the Windows workstation.
internal fun FlutterActivity.wearPictureCursors(engine: FlutterEngine) {
    // Every picture made, by name - kept for the life of the activity.
    val cursors = HashMap<String, PointerIcon>()
    MethodChannel(
        engine.dartExecutor.binaryMessenger,
        "anicel/cursor",
    ).setMethodCallHandler { call, result ->
        val name = call.argument<String>("name")
        when {
            name == null -> result.notImplemented()
            call.method == "createCustomCursor" -> {
                val icon = pointerIconOf(
                    call.argument<ByteArray>("buffer"),
                    call.argument<Int>("width"),
                    call.argument<Int>("height"),
                    call.argument<Double>("hotX"),
                    call.argument<Double>("hotY"),
                )
                if (icon == null) {
                    result.error("argument", "not a cursor's picture", null)
                } else {
                    cursors[name] = icon
                    result.success(name)
                }
            }
            call.method == "setCustomCursor" -> {
                val icon = cursors[name]
                val view: View? = findViewById(FlutterActivity.FLUTTER_VIEW_ID)
                if (icon == null || view == null) {
                    result.error("argument", "no cursor is named $name", null)
                } else {
                    view.pointerIcon = icon
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }
}

// The picture handed over as a pointer icon, or null when it is not one.
private fun pointerIconOf(
    buffer: ByteArray?,
    width: Int?,
    height: Int?,
    hotX: Double?,
    hotY: Double?,
): PointerIcon? {
    if (buffer == null || width == null || height == null ||
        hotX == null || hotY == null ||
        width <= 0 || height <= 0 || buffer.size != width * height * 4
    ) {
        return null
    }
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(buffer))
    return try {
        PointerIcon.create(bitmap, hotX.toFloat(), hotY.toFloat())
    } catch (e: IllegalArgumentException) {
        // A hot spot outside the picture.
        null
    }
}
