package com.myoun.gpu_engine

import android.content.Context
import android.hardware.HardwareBuffer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * The Android half of the GPU engine's way to the screen
 * (gpu-engine-skeleton): a Flutter texture of the AHardwareBuffer an
 * engine surface lives in, one buffer for the texture's life — Flutter's
 * `createHardwareBufferTexture`, which Anicel's Flutter patch 0006 adds
 * (tool/flutter_engine/3.47.4). Two surfaces are shown turn about as on
 * every other platform (rust/src/platform/android.rs).
 */
class GpuEnginePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var textures: TextureRegistry
    private val entries = HashMap<Long, TextureRegistry.TextureEntry>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Before Dart's main can open a sound device: cpal's AAudio host
        // asks the JVM through this context, and died without it (board
        // android-dies-opening-the-sound-output).
        handAndroidContext(binding.applicationContext)
        textures = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, "gpu_engine")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "register" -> {
                val buffer = hardwareBufferOf(call.argument<Number>("buffer")!!.toLong())
                if (buffer == null) {
                    result.error("no_buffer", "the surface has no AHardwareBuffer", null)
                    return
                }
                val entry =
                    try {
                        hardwareBufferTexture(buffer)
                    } catch (refused: UnsupportedOperationException) {
                        buffer.close()
                        result.error("no_texture", "Flutter takes no HardwareBuffer texture: ${refused.message}", null)
                        return
                    }
                entries[entry.id()] = entry
                result.success(entry.id())
            }
            "release" -> {
                entries.remove(call.argument<Number>("textureId")!!.toLong())?.release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        entries.values.forEach { it.release() }
        entries.clear()
    }

    /**
     * Flutter's `createHardwareBufferTexture(buffer)`, which only Anicel's
     * engine has (patch 0006). Asked for by name, not linked, so the app
     * still builds against Flutter's own engine — CI's debug APK, or a
     * build made without the patched artifacts — where the screen is then
     * refused by name (`path … refused: Flutter takes no HardwareBuffer
     * texture`) instead of the build failing (board
     * the-galaxy-tab-canvas-went-slow-on-build-1095, 관제 2026-11-24).
     */
    private fun hardwareBufferTexture(buffer: HardwareBuffer): TextureRegistry.TextureEntry {
        val create =
            try {
                textures.javaClass.getMethod("createHardwareBufferTexture", HardwareBuffer::class.java)
            } catch (missing: NoSuchMethodException) {
                throw UnsupportedOperationException("this engine is not Anicel's (patch 0006)")
            }
        return try {
            create.invoke(textures, buffer) as TextureRegistry.TextureEntry
        } catch (thrown: java.lang.reflect.InvocationTargetException) {
            throw thrown.targetException
        }
    }

    /**
     * The HardwareBuffer of [buffer], a surface's AHardwareBuffer
     * (`gpu_engine_surface_handle`), with a reference of its own that
     * Flutter's texture takes over; null when there is none
     * (rust/src/platform/android.rs).
     */
    private external fun hardwareBufferOf(buffer: Long): HardwareBuffer?

    /**
     * Hands the engine the application's context, once for the process
     * (rust/native/audio_device/src/android.rs).
     */
    private external fun handAndroidContext(context: Context)

    companion object {
        init {
            // The engine's code asset, built by hook/build.dart.
            System.loadLibrary("gpu_engine_core")
        }
    }
}
