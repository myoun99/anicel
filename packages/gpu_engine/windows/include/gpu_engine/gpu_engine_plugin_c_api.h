#ifndef FLUTTER_PLUGIN_GPU_ENGINE_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_GPU_ENGINE_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>

#include <stdint.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void GpuEnginePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

// Bound from Dart with dart:ffi (lib/src/texture_shim.dart).

// The LUID of the adapter Flutter draws with, high part in the upper 32
// bits; 0 when Flutter gave none.
FLUTTER_PLUGIN_EXPORT uint64_t gpu_engine_flutter_adapter_luid(void);

// Registers a texture Flutter reads from DXGI shared handle |front|, or
// from |back| once gpu_engine_texture_show picks slot 1 (|back| may be
// null). |bgra| names the texels' order. Returns the texture id, or -1.
FLUTTER_PLUGIN_EXPORT int64_t gpu_engine_texture_register(void* front,
                                                          void* back,
                                                          uint32_t width,
                                                          uint32_t height,
                                                          bool bgra);

// Shows slot 0 (front) or 1 (back) on the next frame.
FLUTTER_PLUGIN_EXPORT bool gpu_engine_texture_show(int64_t texture_id,
                                                   int32_t slot);

FLUTTER_PLUGIN_EXPORT void gpu_engine_texture_unregister(int64_t texture_id);

// Opens |handle| on a D3D11 device of Flutter's adapter -- as ANGLE will --
// and reports what ANGLE sees: DXGI format, bind flags, misc flags.
// Returns false when it cannot be opened.
FLUTTER_PLUGIN_EXPORT bool gpu_engine_inspect_shared(void* handle,
                                                     uint32_t* format,
                                                     uint32_t* bind_flags,
                                                     uint32_t* misc_flags);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_GPU_ENGINE_PLUGIN_C_API_H_
