import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/ui/canvas/layer_image_draw.dart';

/// 🚨★★★A TEXEL COPY RESAMPLES NOTHING, SO IT IS DRAWN AT `none` (유저
/// 2026-09-24 「통일해서」) — the law the sub-tree blit, the tile blits and
/// the buffer carry already keep, asked of a layer image.
///
/// ⚠️THE PIN READS THE PAINT, NOT THE PIXELS, and that is the point: in the
/// test runner (Skia) and on the Windows app (Impeller GLES) a bilinear
/// draw at 1:1 IS a copy, so a pixel pin here would stay green with the law
/// switched off. Where it is not — Impeller Vulkan, Android's default, up to
/// 9/255 off the source at 2340×1654 — is not an engine this runner has.
/// What the law decides is which filter reaches the engine, so that is what
/// this reads.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ui.Image imageOf(int width, int height) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF3050C0),
    );
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(width, height);
    } finally {
      picture.dispose();
    }
  }

  /// The filter [drawPosedLayerImage] handed the engine for one draw of
  /// [image] into [worldRect], the route having asked for `low`.
  ui.FilterQuality drawnWith(
    ui.Image image, {
    required ui.Rect worldRect,
    required double? texelScale,
    CameraPose? pose,
    bool drawAtOrigin = false,
  }) {
    final canvas = _SpyCanvas();
    drawPosedLayerImage(
      canvas,
      image: image,
      worldRect: worldRect,
      extent: worldRect,
      canvasSize: const CanvasSize(width: 120, height: 80),
      pose: pose,
      opacity: 1,
      blendMode: LayerBlendMode.normal,
      texelScale: texelScale,
      filterQuality: ui.FilterQuality.low,
      drawAtOriginWhen: (_, _) => drawAtOrigin,
    );
    expect(canvas.drawn, hasLength(1), reason: 'fixture: one image draw');
    return canvas.drawn.single;
  }

  const rect = ui.Rect.fromLTWH(8, 4, 60, 40);

  test('laid down one texel per pixel, a layer image is copied — at 100% '
      'and as a level below it', () {
    final full = imageOf(60, 40);
    final level = imageOf(30, 20);
    addTearDown(full.dispose);
    addTearDown(level.dispose);
    expect(
      drawnWith(full, worldRect: rect, texelScale: 1),
      ui.FilterQuality.none,
    );
    expect(
      drawnWith(level, worldRect: rect, texelScale: 0.5),
      ui.FilterQuality.none,
    );
    // The composite's legacy whole-image path is the same copy.
    expect(
      drawnWith(
        full,
        worldRect: const ui.Rect.fromLTWH(0, 0, 60, 40),
        texelScale: 1,
        drawAtOrigin: true,
      ),
      ui.FilterQuality.none,
    );
  });

  test('anything that resamples keeps the filter the route asked for', () {
    final full = imageOf(60, 40);
    final level = imageOf(30, 20);
    addTearDown(full.dispose);
    addTearDown(level.dispose);
    // The screen: a canvas that is not an aligned raster.
    expect(
      drawnWith(full, worldRect: rect, texelScale: null),
      ui.FilterQuality.low,
    );
    // A pose moves the image off the grid, whatever the canvas is.
    expect(
      drawnWith(
        full,
        worldRect: rect,
        texelScale: 1,
        pose: CameraPose(center: CanvasPoint(x: 61, y: 40), zoom: 1.2),
      ),
      ui.FilterQuality.low,
    );
    // Off the pixel grid by half a pixel.
    expect(
      drawnWith(
        full,
        worldRect: rect.translate(0.5, 0),
        texelScale: 1,
      ),
      ui.FilterQuality.low,
    );
    // A capped sub-tree raster: the image is magnified onto it.
    expect(
      drawnWith(level, worldRect: rect, texelScale: 1),
      ui.FilterQuality.low,
    );
  });
}

/// Records the filter of every image draw; everything else is a no-op.
class _SpyCanvas implements ui.Canvas {
  final List<ui.FilterQuality> drawn = [];

  @override
  void drawImageRect(
    ui.Image image,
    ui.Rect src,
    ui.Rect dst,
    ui.Paint paint,
  ) => drawn.add(paint.filterQuality);

  @override
  void drawImage(ui.Image image, ui.Offset offset, ui.Paint paint) =>
      drawn.add(paint.filterQuality);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
