import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';

import '../../models/canvas_viewport.dart';
import '../../models/cel_photo.dart';
import '../../models/layer_blend_mode.dart';
import '../../services/layer_pose_matrix.dart' show picturePlacement;
import '../canvas/display_resample.dart'
    show displayScaleOf, filterQualityForDisplayScale;
import '../canvas/layer_image_draw.dart' show drawPosedLayerImage;
import '../canvas/viewport_canvas_transform.dart' show applyViewportTransform;
import '../media/viewer_render_tier.dart' show pictureRenderWidthFor;
import 'sheet_image_cache.dart' show SheetImageLookup;

/// Draws [photos] — a sheet ink picture's (I-97) — on [canvas], whose space
/// is that picture's SURFACE PIXELS: each the pool file [imageFor] reads,
/// where its reference stands it ([picturePlacement], a reference row's own
/// law), bottom → top. One whose file is not read yet is left out; the
/// caller's repaint brings it when it lands.
///
/// 🗣️I-97-Q1 (b, 유저 2026-10-15): drawn from the original — 「키워도 원본
/// 해상도까지 선명」 — so never from a raster of the ink. ONE answer for the
/// live window, the print and the export: they differ only in the space
/// they hand in, and in [displayScale] — how many target pixels one surface
/// pixel is — which the sampling is chosen by, with the photo's own scale
/// ([filterQualityForDisplayScale]).
///
/// Each file is asked for as wide as it is drawn, on its more magnified
/// axis — the viewer's ladder over its own pixels ([pictureRenderWidthFor],
/// 「화면이 필요한 만큼(최대 원본)」): up to the original as the sheet is
/// zoomed, and no more than a cell's worth while it is not.
void paintSheetPhotos(
  ui.Canvas canvas,
  List<CelPhoto> photos, {
  required SheetImageLookup imageFor,
  required double displayScale,
}) {
  for (final photo in photos) {
    final reference = photo.reference;
    final pose = reference.pose;
    final picture = reference.pictureSize;
    final image = imageFor(
      reference.assetPath,
      width: pictureRenderWidthFor(
        picture.height *
            math.max(pose.scaleX.abs(), pose.scaleY.abs()) *
            displayScale,
        ui.Size(picture.width.toDouble(), picture.height.toDouble()),
      ),
    );
    if (image == null) {
      continue;
    }
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
  final SheetImageLookup? imageFor;

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
