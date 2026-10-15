import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';

import '../../models/canvas_viewport.dart';
import '../../models/cel_photo.dart';
import '../../models/layer_blend_mode.dart';
import '../../services/import/raster_cel_import.dart' show picturePlacement;
import '../canvas/display_resample.dart'
    show displayScaleOf, filterQualityForDisplayScale;
import '../canvas/layer_image_draw.dart' show drawPosedLayerImage;
import '../canvas/viewport_canvas_transform.dart' show applyViewportTransform;

/// Draws [photos] — a sheet ink picture's (I-97) — on [canvas], whose space
/// is that picture's SURFACE PIXELS: each the pool file [imageFor] decodes,
/// where its reference stands it ([picturePlacement], a reference row's own
/// law), bottom → top. One whose file is not decoded yet is left out; the
/// caller's repaint brings it when it lands.
///
/// 🗣️I-97-Q1 (b, 유저 2026-10-15): drawn from the original — 「키워도 원본
/// 해상도까지 선명」 — so never from a raster of the ink. ONE answer for the
/// live window, the print and the export: they differ only in the space
/// they hand in, and in [displayScale] — how many target pixels one surface
/// pixel is — which the sampling is chosen by, with the photo's own scale
/// ([filterQualityForDisplayScale]).
void paintSheetPhotos(
  ui.Canvas canvas,
  List<CelPhoto> photos, {
  required ui.Image? Function(String assetPath) imageFor,
  required double displayScale,
}) {
  for (final photo in photos) {
    final reference = photo.reference;
    final image = imageFor(reference.assetPath);
    if (image == null) {
      continue;
    }
    final pose = reference.pose;
    final picture = reference.pictureSize;
    final own = ui.Rect.fromLTWH(
      0,
      0,
      picture.width.toDouble(),
      picture.height.toDouble(),
    );
    // Surface pixels per pixel of the file, on its narrower axis.
    final perTexel = math.min(
      pose.scaleX.abs() * picture.width / image.width,
      pose.scaleY.abs() * picture.height / image.height,
    );
    drawPosedLayerImage(
      canvas,
      image: image,
      worldRect: own,
      extent: own,
      placement: picturePlacement(pose, picture),
      opacity: 1,
      blendMode: LayerBlendMode.normal,
      texelScale: null,
      filterQuality: filterQualityForDisplayScale(displayScale * perTexel),
    );
  }
}

/// One sheet window's [photos], under its ink on screen — through the
/// window's ink [viewport] at [devicePixelRatio], the transform and the
/// snap its brush view draws the ink with (`applyViewportTransform`). The
/// live layer mounts it and the print runs it, so the brush switch moves
/// no photo (F-215).
class SheetPhotosPainter extends CustomPainter {
  SheetPhotosPainter({
    required this.photos,
    required this.viewport,
    required this.devicePixelRatio,
    required this.imageFor,
    super.repaint,
  });

  final List<CelPhoto> photos;
  final CanvasViewport viewport;
  final double devicePixelRatio;

  /// Null where nothing decodes pool files — a sheet with no photo to show.
  final ui.Image? Function(String assetPath)? imageFor;

  @override
  void paint(Canvas canvas, Size size) {
    final decoded = imageFor;
    if (photos.isEmpty || decoded == null) {
      return;
    }
    canvas.save();
    applyViewportTransform(
      canvas,
      viewport,
      devicePixelRatio: devicePixelRatio,
    );
    paintSheetPhotos(
      canvas,
      photos,
      imageFor: decoded,
      displayScale: displayScaleOf(viewport.zoom, devicePixelRatio),
    );
    canvas.restore();
  }

  /// ⚠️[imageFor] is not compared: a host hands a fresh tear-off each build,
  /// and a decode that lands repaints through `repaint`.
  @override
  bool shouldRepaint(SheetPhotosPainter oldDelegate) =>
      !listEquals(oldDelegate.photos, photos) ||
      oldDelegate.viewport != viewport ||
      oldDelegate.devicePixelRatio != devicePixelRatio ||
      (oldDelegate.imageFor == null) != (imageFor == null);
}
