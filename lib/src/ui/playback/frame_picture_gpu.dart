import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;

/// One write into a frame picture's base level out of a run: the [width] x
/// [height] texels at ([left], [top]) of the run laid at ([x], [y]) —
/// texel for texel, a copy, not a draw.
typedef RunBlock = ({
  int left,
  int top,
  int width,
  int height,
  int x,
  int y,
});

/// One write into a frame picture's mip [level] out of a run: the [width] x
/// [height] texels from texel [start] of the run on, row after row, laid at
/// ([x], [y]) of that level.
typedef RunSpan = ({int start, int width, int height, int x, int y, int level});

/// The writes into a frame picture's levels out of one [run]: each of
/// [base] into the base level, then each of [spans] into a level under it,
/// in order.
typedef LevelWrites = ({
  ui.Image run,
  List<RunBlock> base,
  List<RunSpan> spans,
});

/// What a [FramePictureStore] asks of the GPU — the one seam between its
/// logic and `flutter_gpu`, so the logic is proven on any runner and the
/// writes on one with Impeller ([FlutterGpuFramePictures]).
abstract interface class FramePictureGpu {
  /// [picture] rastered at [width] x [height] — asynchronously, the only
  /// image `flutter_gpu` can write into or copy out of (a `toImageSync` one
  /// it refuses to wrap, measured 2026-10-24). The engine gives it a whole
  /// mip chain.
  Future<ui.Image> render(ui.Picture picture, int width, int height);

  /// [picture] rastered at [width] x [height] in its turn on the raster
  /// thread, nothing here waiting for it: an image only DRAWN from — a
  /// patch's texels, its deepest level — on the way into one [render]
  /// makes, which the raster thread makes after it.
  ui.Image renderInTurn(ui.Picture picture, int width, int height);

  /// The texture behind [image], to write into where it stands — null where
  /// the engine has no GPU context to write with (Skia: the devices that
  /// render with it are out of the release, skia-devices-out-of-release).
  Object? hold(ui.Image image);

  /// The mip levels [held]'s texture has: the base and every halving down
  /// to one texel.
  int levelsOf(Object held);

  /// Lays [writes] into [held]'s levels in ONE submission, and answers once
  /// the GPU has done them all — after which every draw of the image sees
  /// them.
  Future<bool> write(Object held, LevelWrites writes);
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
  ui.Image renderInTurn(ui.Picture picture, int width, int height) =>
      picture.toImageSync(width, height);

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
  Future<bool> write(Object held, LevelWrites writes) {
    final target = held as gpu.Texture;
    final context = gpu.gpuContext;
    final commands = context.createCommandBuffer();
    final source = gpu.Texture.fromImage(context, writes.run);
    for (final (:left, :top, :width, :height, :x, :y) in writes.base) {
      commands.copyTextureToTexture(
        gpu.TextureRegion(
          source,
          x: left,
          y: top,
          width: width,
          height: height,
        ),
        gpu.TextureDestinationRegion(target, x: x, y: y),
      );
    }
    if (writes.spans.isNotEmpty) {
      _writeLevels(context, commands, source, target, writes.spans);
    }
    return _submitted(commands);
  }

  /// [spans] out of [source] through one buffer: the rows from the first
  /// one a span reads to the end, copied out once.
  static void _writeLevels(
    gpu.GpuContext context,
    gpu.CommandBuffer commands,
    gpu.Texture source,
    gpu.Texture target,
    List<RunSpan> spans,
  ) {
    final from = spans.map((span) => span.start).reduce(math.min) ~/
        source.width;
    final rows = source.height - from;
    final perTexel =
        source.getMipLevelSizeInBytes(0) ~/ (source.width * source.height);
    final skipped = from * source.width;
    final bytes = source.width * rows * perTexel;
    final buffer = context.createDeviceBuffer(
      gpu.StorageMode.devicePrivate,
      bytes,
    );
    commands.copyTextureToBuffer(
      gpu.TextureRegion(source, y: from, height: rows),
      gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: bytes),
    );
    for (final (:start, :width, :height, :x, :y, :level) in spans) {
      commands.copyBufferToTexture(
        gpu.BufferView(
          buffer,
          offsetInBytes: (start - skipped) * perTexel,
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
  }

  static Future<bool> _submitted(gpu.CommandBuffer commands) {
    final done = Completer<bool>();
    commands.submit(completionCallback: done.complete);
    return done.future;
  }
}
