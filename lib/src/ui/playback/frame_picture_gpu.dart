import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;

import 'flutter_gpu_copies.dart';

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
  /// render with it are out of the release, skia-devices-out-of-release).
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
    return gpu.Texture.fromImage(context, image);
  }

  /// How many bytes a texel of [format] takes — what a write into the levels
  /// under the base copies through a buffer by ([write]).
  ///
  /// 🚨★★★`unknown` IS 8 (F-509-Q9 · Q10, 유저 2026-10-30): an offscreen
  /// picture is `unknown` only where the screen renders with wide gamut, and
  /// both Apple surfaces do that in `BGRA10_XR` alone (iOS `FlutterView.mm`,
  /// macOS `FlutterSurface.mm`, engine 3.47.4). `flutter_gpu` has no name
  /// for it and calls it zero bytes a texel. A write sized so never came
  /// back: build 1083's trace, 2026-10-30, no write into a picture answered
  /// on an iPhone or iPad. iOS now renders without wide gamut
  /// (`FLTEnableWideGamut` false in its Info.plist, F-509-Q7); a Mac on
  /// Apple silicon with a P3 screen still renders with it — its embedder
  /// reads no such key. Should this be wrong the engine refuses the length,
  /// and the write goes as one not done ([FramePictureStore]).
  ///
  /// ↩️Such a picture was not held, its frame drawn as it stands
  /// (`f2495686f`) — correct, and a whole frame drawn at every step.
  static int bytesPerTexel(gpu.PixelFormat format) =>
      format == gpu.PixelFormat.unknown ? 8 : format.bytesPerBlock;

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
    final perTexel = bytesPerTexel(source.format);
    final buffer = context.createDeviceBuffer(
      gpu.StorageMode.devicePrivate,
      source.width * source.height * perTexel,
    );
    copyTextureIntoBuffer(commands, source, buffer);
    for (final (:start, :width, :height, :x, :y, :level) in levels.spans) {
      copyBufferIntoTexture(
        commands,
        buffer,
        offsetInBytes: start * perTexel,
        lengthInBytes: width * height * perTexel,
        destination: target,
        x: x,
        y: y,
        width: width,
        height: height,
        mipLevel: level,
      );
    }
  }

  static Future<bool> _submitted(gpu.CommandBuffer commands) {
    final done = Completer<bool>();
    commands.submit(completionCallback: done.complete);
    return done.future;
  }
}
