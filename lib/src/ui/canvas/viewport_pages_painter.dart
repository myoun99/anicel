import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../models/canvas_viewport.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart' show ByList;
import 'paper_background.dart' show paintAlphaCheckerboard;
import 'viewport_canvas_transform.dart';

/// What lies under a page before its raster is drawn.
enum ViewportPageGround {
  /// Nothing: the panel shows through.
  none,

  /// Opaque white — a PDF's paper, a picture on the light table.
  paper,

  /// The app's ONE transparency checker ([paintAlphaCheckerboard]), in
  /// canvas-space cells — a file whose alpha stays open.
  checker,
}

/// The pages a canvas-base panel shows as RASTERS, each drawn into where it
/// lies in document space through the view.
///
/// One painter for the surfaces that show a document's pages this way: the
/// media viewer, and the export window's preview (F-289, 유저 2026-10-06 —
/// the preview is a canvas-base panel like the viewer). It was the viewer's
/// own, and a second surface drawing pages through a view would have been
/// a second copy of it.
class ViewportPagesPainter extends CustomPainter with RepaintOnProps {
  const ViewportPagesPainter({
    required this.pages,
    required this.ground,
    required this.viewport,
    required this.effectiveRatio,
  });

  /// The pages on screen, each where it lies in document space with its
  /// raster — null draws the ground alone (a page still rendering). A
  /// raster draws scaled INTO its rect, so a higher-tier render stays
  /// sharp under zoom.
  final List<({Rect rect, ui.Image? image})> pages;

  final ViewportPageGround ground;
  final CanvasViewport viewport;

  /// The view's DPR, for [applyViewportTransform]'s pan-phase snap.
  final double effectiveRatio;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // P8's ONE transform. ⛔The snap already happened at the host, so the
    // ratio here keeps the helper's own snap idempotent.
    applyViewportTransform(canvas, viewport, devicePixelRatio: effectiveRatio);
    for (final (:rect, :image) in pages) {
      switch (ground) {
        case ViewportPageGround.none:
          break;
        case ViewportPageGround.paper:
          canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
        case ViewportPageGround.checker:
          paintAlphaCheckerboard(canvas, rect);
      }
      if (image != null) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          rect,
          Paint()
            ..filterQuality = FilterQuality.high
            ..isAntiAlias = true,
        );
      }
    }
    canvas.restore();
  }

  /// ⚠️The pages by their CONTENTS: the list is built afresh every build.
  @override
  Object get props => (ByList(pages), ground, viewport, effectiveRatio);
}
