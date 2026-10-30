// The analyzer reads `dart:nativewrappers` empty (`_embedder.yaml` of
// sky_engine), so it cannot see that `flutter_gpu`'s classes are native
// wrappers; the compiler can, and takes them.
// ignore_for_file: ffi_native_only_classes_extending_nativefieldwrapperclass1_can_be_pointer, must_be_a_subtype

import 'dart:ffi';

import 'package:flutter_gpu/gpu.dart' as gpu;

/// 🚨★★★`flutter_gpu`'S TWO BUFFER COPIES, PAST ITS DART LENGTH CHECK
/// (F-509-Q10, 유저 2026-10-30 — 「올릴때마다 무조건 맞추도록 주의」).
///
/// A texture in a format `flutter_gpu` has no name for reports
/// `PixelFormat.unknown`, zero bytes a texel: Apple's extended-range ones,
/// every picture on an Apple-silicon Mac with a P3 screen, where no key turns
/// wide gamut off. Its Dart check then asks a copy of zero bytes and the
/// engine's (`BlitPass::AddCopy`) `width * height * 8`, and no length passes
/// both (flutter/flutter#195675). These call the natives its own copies
/// call, so the engine's check still stands: a wrong length is refused.
///
/// 📐Both natives are exported by the engine, not resolved for one library:
/// `flutter_gpu` itself reaches them by the process's symbols, as this does.
///
/// ⚠️THE SIGNATURES ARE THE ENGINE'S. They have to equal `flutter_gpu`'s own
/// after every Flutter upgrade, and the day it names those formats this file
/// goes: `test/ui/playback/flutter_gpu_copies_match_the_sdk_test.dart` reads
/// the SDK and goes red on either.
@Native<
  Handle Function(
    Pointer<Void>,
    Pointer<Void>,
    Int,
    Int,
    Pointer<Void>,
    Int,
    Int,
    Int,
    Int,
    Int,
    Int,
  )
>(symbol: 'InternalFlutterGpu_CommandBuffer_CopyBufferToTexture')
external String? _copyBufferToTexture(
  gpu.CommandBuffer commands,
  gpu.DeviceBuffer source,
  int sourceOffsetInBytes,
  int sourceLengthInBytes,
  gpu.Texture destination,
  int destinationX,
  int destinationY,
  int destinationWidth,
  int destinationHeight,
  int mipLevel,
  int slice,
);

@Native<
  Handle Function(
    Pointer<Void>,
    Pointer<Void>,
    Int,
    Int,
    Int,
    Int,
    Pointer<Void>,
    Int,
  )
>(symbol: 'InternalFlutterGpu_CommandBuffer_CopyTextureToBuffer')
external String? _copyTextureToBuffer(
  gpu.CommandBuffer commands,
  gpu.Texture source,
  int sourceX,
  int sourceY,
  int sourceWidth,
  int sourceHeight,
  gpu.DeviceBuffer destination,
  int destinationOffsetInBytes,
);

/// Records the copy of [lengthInBytes] of [source] from [offsetInBytes] into
/// the [width] x [height] texels at ([x], [y]) of [destination]'s [mipLevel]
/// — throwing what the engine refuses, as `flutter_gpu`'s own copy does.
void copyBufferIntoTexture(
  gpu.CommandBuffer commands,
  gpu.DeviceBuffer source, {
  required int offsetInBytes,
  required int lengthInBytes,
  required gpu.Texture destination,
  required int x,
  required int y,
  required int width,
  required int height,
  required int mipLevel,
}) {
  final refused = _copyBufferToTexture(
    commands,
    source,
    offsetInBytes,
    lengthInBytes,
    destination,
    x,
    y,
    width,
    height,
    mipLevel,
    0,
  );
  if (refused != null) {
    throw Exception(refused);
  }
}

/// Records the copy of all of [source]'s base level to the start of
/// [destination] — throwing what the engine refuses, as `flutter_gpu`'s own
/// copy does.
void copyTextureIntoBuffer(
  gpu.CommandBuffer commands,
  gpu.Texture source,
  gpu.DeviceBuffer destination,
) {
  final refused = _copyTextureToBuffer(
    commands,
    source,
    0,
    0,
    source.width,
    source.height,
    destination,
    0,
  );
  if (refused != null) {
    throw Exception(refused);
  }
}
