#import "GpuEnginePlugin.h"

#import <CoreVideo/CoreVideo.h>

#include <stdbool.h>
#include <stdint.h>

// Looked up by Dart through DynamicLibrary.process() (lib/src/
// texture_shim.dart), as the app looks up qa_native's: nothing in the app
// calls them, so they are kept from dead-code stripping and from hidden
// visibility.
#define GPU_ENGINE_EXPORT __attribute__((visibility("default"), used))

// One registered texture: the CVPixelBuffers of two engine surfaces, of
// which Flutter shows the one |shown| names. The slots never change after
// registration, so the raster thread reading them races with nothing;
// only |shown| moves, atomically — as the Windows shim's slots do
// (windows/gpu_engine_plugin_c_api.cpp).
//
// Each slot holds its own reference, and a CVPixelBuffer holds its
// IOSurface: the pixels outlive the engine's surface for as long as
// Flutter keeps this texture, which it does past unregistration until its
// raster thread lets go (FlutterDarwinExternalTextureMetal holds it).
@interface GpuEngineSharedTexture : NSObject <FlutterTexture>
@property(atomic) int32_t shown;
- (instancetype)initWithFront:(CVPixelBufferRef)front
                         back:(CVPixelBufferRef)back;
@end

@implementation GpuEngineSharedTexture {
  CVPixelBufferRef _slots[2];
}

- (instancetype)initWithFront:(CVPixelBufferRef)front
                         back:(CVPixelBufferRef)back {
  if ((self = [super init])) {
    _slots[0] = CVPixelBufferRetain(front);
    _slots[1] = CVPixelBufferRetain(back);
  }
  return self;
}

- (void)dealloc {
  CVPixelBufferRelease(_slots[0]);
  CVPixelBufferRelease(_slots[1]);
}

// Flutter releases what this returns (FlutterTexture.h, "Copy"), so each
// call hands over a reference of its own.
- (CVPixelBufferRef _Nullable)copyPixelBuffer {
  return CVPixelBufferRetain(_slots[self.shown]);
}

@end

// Every call below comes on the platform thread, where textures must be
// registered (FlutterTexture.h): Dart runs there, the platform and UI
// threads being one on iOS always and on macOS by default
// (FlutterDartProject.mm, FlutterEngine.mm — FLTEnableMergedPlatformUIThread).
static id<FlutterTextureRegistry> gTextures;
static NSMutableDictionary<NSNumber*, GpuEngineSharedTexture*>* gRegistered;

@implementation GpuEnginePlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  gTextures = [registrar textures];
  gRegistered = [NSMutableDictionary dictionary];
}

@end

// Registers a texture Flutter reads from CVPixelBuffer |front|, or from
// |back| once gpu_engine_texture_show picks slot 1 (|back| may be null) —
// the buffers gpu_engine_surface_handle gives. A buffer carries its own
// size and layout, so |width|, |height| and |bgra| — the Windows shim's —
// are not read. Returns the texture id, or -1.
GPU_ENGINE_EXPORT int64_t gpu_engine_texture_register(void* front,
                                                      void* back,
                                                      uint32_t width,
                                                      uint32_t height,
                                                      bool bgra) {
  if (gTextures == nil || front == NULL) {
    return -1;
  }
  GpuEngineSharedTexture* texture = [[GpuEngineSharedTexture alloc]
      initWithFront:(CVPixelBufferRef)front
               back:(CVPixelBufferRef)(back != NULL ? back : front)];
  // 0 is the registry's failure (FlutterTexture.h; FlutterTextureRegistrar.mm).
  const int64_t texture_id = [gTextures registerTexture:texture];
  if (texture_id == 0) {
    return -1;
  }
  gRegistered[@(texture_id)] = texture;
  return texture_id;
}

// Shows slot 0 (front) or 1 (back) on the next frame.
GPU_ENGINE_EXPORT bool gpu_engine_texture_show(int64_t texture_id,
                                               int32_t slot) {
  GpuEngineSharedTexture* texture = gRegistered[@(texture_id)];
  if (texture == nil) {
    return false;
  }
  texture.shown = slot == 1 ? 1 : 0;
  [gTextures textureFrameAvailable:texture_id];
  return true;
}

GPU_ENGINE_EXPORT void gpu_engine_texture_unregister(int64_t texture_id) {
  if (gRegistered[@(texture_id)] == nil) {
    return;
  }
  [gTextures unregisterTexture:texture_id];
  [gRegistered removeObjectForKey:@(texture_id)];
}
