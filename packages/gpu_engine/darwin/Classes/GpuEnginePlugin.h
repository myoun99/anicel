#import <TargetConditionals.h>

#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif

// The iOS and macOS half of the GPU engine's way to the screen
// (gpu-engine-skeleton): it keeps the registrar's texture registry and
// shows the engine's CVPixelBuffers as Flutter textures. Dart binds its
// three texture calls (GpuEnginePlugin.m) with dart:ffi, from the process.
@interface GpuEnginePlugin : NSObject <FlutterPlugin>
@end
