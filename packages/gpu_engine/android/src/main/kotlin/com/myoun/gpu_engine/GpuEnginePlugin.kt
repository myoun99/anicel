package com.myoun.gpu_engine

import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * The Android half of the GPU engine's way to the screen
 * (gpu-engine-skeleton): a Flutter texture whose window the Rust engine
 * presents into. On Impeller the window is an ImageReader whose buffers
 * Flutter imports as they are (FlutterRenderer.java:455-462, 940-965).
 *
 * The producer keeps the default manual lifecycle, so its window outlives
 * the app going to the background (TextureRegistry.SurfaceLifecycle).
 */
class GpuEnginePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var textures: TextureRegistry
    private val producers = HashMap<Long, TextureRegistry.SurfaceProducer>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        textures = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, "gpu_engine")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "window" -> {
                val producer = textures.createSurfaceProducer()
                producer.setSize(call.argument<Int>("width")!!, call.argument<Int>("height")!!)
                val window = nativeWindow(producer.surface)
                if (window == 0L) {
                    producer.release()
                    result.error("no_window", "ANativeWindow_fromSurface gave none", null)
                    return
                }
                producers[producer.id()] = producer
                result.success(mapOf("textureId" to producer.id(), "window" to window))
            }
            "release" -> {
                producers.remove(call.argument<Number>("textureId")!!.toLong())?.release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        producers.values.forEach { it.release() }
        producers.clear()
    }

    /**
     * The ANativeWindow of [surface], with a reference of its own that
     * `gpu_engine_window_new` takes over; 0 when there is none
     * (rust/src/platform/android.rs).
     */
    private external fun nativeWindow(surface: Surface): Long

    companion object {
        init {
            // The engine's code asset, built by hook/build.dart.
            System.loadLibrary("gpu_engine")
        }
    }
}
