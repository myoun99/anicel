#ifndef FLUTTER_PLUGIN_GPU_ENGINE_PLUGIN_H_
#define FLUTTER_PLUGIN_GPU_ENGINE_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

#include <stdbool.h>
#include <stdint.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

FLUTTER_PLUGIN_EXPORT void gpu_engine_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

// Bound from Dart with dart:ffi (lib/src/texture_shim.dart), by the names
// and shapes the Windows shim's have (windows/include/gpu_engine/
// gpu_engine_plugin_c_api.h).

// Registers a texture Flutter reads from the dma-buf plane |front|, or from
// |back| once gpu_engine_texture_show picks slot 1 (|back| may be null) —
// the `DmaBuf`s gpu_engine_surface_handle gives, of |width| x |height|
// texels. |bgra| is not read: a plane's fourcc names its layout. Returns
// the texture id, or -1.
FLUTTER_PLUGIN_EXPORT int64_t gpu_engine_texture_register(void* front,
                                                          void* back,
                                                          uint32_t width,
                                                          uint32_t height,
                                                          bool bgra);

// Shows slot 0 (front) or 1 (back) on the next frame.
FLUTTER_PLUGIN_EXPORT bool gpu_engine_texture_show(int64_t texture_id,
                                                   int32_t slot);

// Flutter must no longer show the texture: its GL texture is freed by the
// next texture Flutter draws (gpu_engine_plugin.cc says why).
FLUTTER_PLUGIN_EXPORT void gpu_engine_texture_unregister(int64_t texture_id);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_GPU_ENGINE_PLUGIN_H_
