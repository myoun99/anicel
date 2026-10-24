import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;

/// One write into a frame picture's texture: the [from] rect of [source]
/// laid at ([x], [y]) of mip [level] — texel for texel, a copy, not a draw.
typedef LevelWrite = ({ui.Image source, ui.Rect from, int x, int y, int level});

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

  /// Lays [writes] into [held]'s texture, in order, and answers once the
  /// GPU has done them — after which every draw of the image sees them.
  Future<bool> write(Object held, List<LevelWrite> writes);
}

/// [FramePictureGpu] on `flutter_gpu`.
///
/// 📐The base level takes a texture-to-texture copy. A halving level takes
/// the same texels through a buffer: `flutter_gpu` copies a texture into a
/// mip level only from a buffer, and renders into one not at all on GLES
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
  Future<bool> write(Object held, List<LevelWrite> writes) {
    final target = held as gpu.Texture;
    final context = gpu.gpuContext;
    final commands = context.createCommandBuffer();
    final sources = <ui.Image, gpu.Texture>{};
    for (final (:source, :from, :x, :y, :level) in writes) {
      final region = gpu.TextureRegion(
        sources.putIfAbsent(
          source,
          () => gpu.Texture.fromImage(context, source),
        ),
        x: from.left.toInt(),
        y: from.top.toInt(),
        width: from.width.toInt(),
        height: from.height.toInt(),
      );
      if (level == 0) {
        commands.copyTextureToTexture(
          region,
          gpu.TextureDestinationRegion(target, x: x, y: y),
        );
        continue;
      }
      final texture = region.texture;
      final perTexel = texture.getMipLevelSizeInBytes(0) ~/
          (texture.width * texture.height);
      final bytes = perTexel * from.width.toInt() * from.height.toInt();
      final view = gpu.BufferView(
        context.createDeviceBuffer(gpu.StorageMode.devicePrivate, bytes),
        offsetInBytes: 0,
        lengthInBytes: bytes,
      );
      commands
        ..copyTextureToBuffer(region, view)
        ..copyBufferToTexture(
          view,
          gpu.TextureRegion(
            target,
            x: x,
            y: y,
            width: from.width.toInt(),
            height: from.height.toInt(),
            mipLevel: level,
          ),
        );
    }
    final done = Completer<bool>();
    commands.submit(completionCallback: done.complete);
    return done.future;
  }
}
