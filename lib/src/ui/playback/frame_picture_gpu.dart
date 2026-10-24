import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;

/// One write into a frame picture's base level: [source] laid whole at
/// ([x], [y]) — texel for texel, a copy, not a draw.
typedef BaseWrite = ({ui.Image source, int x, int y});

/// One write into a frame picture's mip [level] out of a run: the [width] x
/// [height] texels from texel [start] of the run on, row after row, laid at
/// ([x], [y]) of that level.
typedef RunSpan = ({int start, int width, int height, int x, int y, int level});

/// What a [FramePictureStore] asks of the GPU — the one seam between its
/// logic and `flutter_gpu`, so the logic is proven on any runner and the
/// writes on one with Impeller ([FlutterGpuFramePictures]).
abstract interface class FramePictureGpu {
  /// [picture] rastered at [width] x [height] — asynchronously, the only
  /// image `flutter_gpu` can write into (a `toImageSync` one it refuses to
  /// wrap, measured 2026-10-24). The engine gives it a whole mip chain.
  Future<ui.Image> render(ui.Picture picture, int width, int height);

  /// The texture behind [image], to write into where it stands — null where
  /// the engine has no GPU context to write with (Skia: the devices that
  /// render with it are out of the release, skia-devices-out-of-release).
  Object? hold(ui.Image image);

  /// The mip levels [held]'s texture has: the base and every halving down
  /// to one texel.
  int levelsOf(Object held);

  /// Lays [writes] into [held]'s base level, in order, and answers once the
  /// GPU has done them — after which every draw of the image sees them.
  Future<bool> writeBase(Object held, List<BaseWrite> writes);

  /// Copies [run]'s texels out of the GPU once and lays each of [spans]
  /// from them into [held]'s levels, in order; answers once the GPU has
  /// done them.
  Future<bool> writeLevels(Object held, ui.Image run, List<RunSpan> spans);
}

/// [FramePictureGpu] on `flutter_gpu`.
///
/// 📐The base level takes a texture-to-texture copy. A halving level takes
/// its texels through a buffer: `flutter_gpu` copies a texture into a mip
/// level only from a buffer, and renders into one not at all on GLES
/// (`doesSupportFramebufferRenderMipmap` false on the Surface Pro 11).
/// Both kinds landed and showed under `FilterQuality.medium` at every zoom
/// from 1/2 to 1/128 there (2026-10-24).
class FlutterGpuFramePictures implements FramePictureGpu {
  @override
  Future<ui.Image> render(ui.Picture picture, int width, int height) =>
      picture.toImage(width, height);

  @override
  Object? hold(ui.Image image) {
    final gpu.GpuContext context;
    try {
      context = gpu.gpuContext;
    } on Exception {
      return null;
    }
    return gpu.Texture.fromImage(context, image);
  }

  @override
  int levelsOf(Object held) => (held as gpu.Texture).mipLevelCount;

  @override
  Future<bool> writeBase(Object held, List<BaseWrite> writes) {
    final target = held as gpu.Texture;
    final context = gpu.gpuContext;
    final commands = context.createCommandBuffer();
    for (final (:source, :x, :y) in writes) {
      commands.copyTextureToTexture(
        gpu.TextureRegion(gpu.Texture.fromImage(context, source)),
        gpu.TextureDestinationRegion(target, x: x, y: y),
      );
    }
    return _submitted(commands);
  }

  @override
  Future<bool> writeLevels(Object held, ui.Image run, List<RunSpan> spans) {
    final target = held as gpu.Texture;
    final context = gpu.gpuContext;
    final source = gpu.Texture.fromImage(context, run);
    final bytes = source.getMipLevelSizeInBytes(0);
    final perTexel = bytes ~/ (source.width * source.height);
    final buffer = context.createDeviceBuffer(
      gpu.StorageMode.devicePrivate,
      bytes,
    );
    final commands = context.createCommandBuffer()
      ..copyTextureToBuffer(
        gpu.TextureRegion(source),
        gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: bytes),
      );
    for (final (:start, :width, :height, :x, :y, :level) in spans) {
      commands.copyBufferToTexture(
        gpu.BufferView(
          buffer,
          offsetInBytes: start * perTexel,
          lengthInBytes: width * height * perTexel,
        ),
        gpu.TextureRegion(
          target,
          x: x,
          y: y,
          width: width,
          height: height,
          mipLevel: level,
        ),
      );
    }
    return _submitted(commands);
  }

  static Future<bool> _submitted(gpu.CommandBuffer commands) {
    final done = Completer<bool>();
    commands.submit(completionCallback: done.complete);
    return done.future;
  }
}
