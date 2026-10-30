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

/// The writes into a frame picture's levels under the base: [run]'s texels
/// copied out of the GPU once, each of [spans] laid from them.
typedef LevelWrites = ({ui.Image run, List<RunSpan> spans});

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
  /// render with it are out of the release, skia-devices-out-of-release),
  /// or no write into it could be sized ([FlutterGpuFramePictures.sizes]).
  Object? hold(ui.Image image);

  /// The mip levels [held]'s texture has: the base and every halving down
  /// to one texel.
  int levelsOf(Object held);

  /// A NEW image of [held]'s texture — another identity each time, the
  /// texels shared, none copied ([FramePicture.image]: a picture written
  /// into is a new image).
  ui.Image imageOf(Object held);

  /// Lays [base] into [held]'s base level and then [levels] into the
  /// levels under it, each in order, in ONE submission, and answers once
  /// the GPU has done them all — after which every draw of the image sees
  /// them.
  Future<bool> write(Object held, List<BaseWrite> base, LevelWrites? levels);
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
    final texture = gpu.Texture.fromImage(context, image);
    return sizes(texture.format) ? texture : null;
  }

  /// Whether `flutter_gpu` knows how many bytes a texel of [format] takes —
  /// what a write into the levels under the base copies through a buffer
  /// by ([write]).
  ///
  /// 🚨★★★A PICTURE IN A FORMAT IT CANNOT SIZE IS NOT HELD: its frame is
  /// drawn as it stands (F-509). An iPhone's or iPad's Impeller renders
  /// with wide gamut by default, its pictures in Apple's extended-range
  /// formats, which `flutter_gpu` names `unknown` — zero bytes a texel. A
  /// write into one sized its buffer and its spans at zero and never came
  /// back: build 1083's trace, 2026-10-30, no write into a picture answered
  /// on either.
  static bool sizes(gpu.PixelFormat format) => format.bytesPerBlock > 0;

  @override
  int levelsOf(Object held) => (held as gpu.Texture).mipLevelCount;

  @override
  ui.Image imageOf(Object held) => (held as gpu.Texture).asImage();

  @override
  Future<bool> write(Object held, List<BaseWrite> base, LevelWrites? levels) {
    final target = held as gpu.Texture;
    final context = gpu.gpuContext;
    final commands = context.createCommandBuffer();
    for (final (:source, :x, :y) in base) {
      commands.copyTextureToTexture(
        gpu.TextureRegion(gpu.Texture.fromImage(context, source)),
        gpu.TextureDestinationRegion(target, x: x, y: y),
      );
    }
    if (levels != null) {
      _writeLevels(context, commands, target, levels);
    }
    return _submitted(commands);
  }

  static void _writeLevels(
    gpu.GpuContext context,
    gpu.CommandBuffer commands,
    gpu.Texture target,
    LevelWrites levels,
  ) {
    final source = gpu.Texture.fromImage(context, levels.run);
    final bytes = source.getMipLevelSizeInBytes(0);
    final perTexel = bytes ~/ (source.width * source.height);
    final buffer = context.createDeviceBuffer(
      gpu.StorageMode.devicePrivate,
      bytes,
    );
    commands.copyTextureToBuffer(
      gpu.TextureRegion(source),
      gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: bytes),
    );
    for (final (:start, :width, :height, :x, :y, :level) in levels.spans) {
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
  }

  static Future<bool> _submitted(gpu.CommandBuffer commands) {
    final done = Completer<bool>();
    commands.submit(completionCallback: done.complete);
    return done.future;
  }
}
