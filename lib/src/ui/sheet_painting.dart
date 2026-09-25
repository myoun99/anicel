import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../core/contain_rect.dart';
import '../models/brush_frame_key.dart';
import '../models/canvas_viewport.dart';
import '../models/sheet_marks.dart';
import '../models/sheet_paint_layer.dart';
import 'canvas/viewport_canvas_transform.dart';

/// Draws one baked ink window into [rect]: the raster is [scale]× the
/// window in each axis, clipped to the window so a stroke that ran past
/// the box does not bleed into its neighbour.
///
/// ⛔BOTH SHEETS DRAW INK THIS WAY. The conte page and the cut envelope
/// each wrote out the save / clip / drawImageRect / restore with the same
/// medium filter. The SOURCE rect is the part that has to agree with
/// whatever rendered the ink, so two copies of it is two chances to scale
/// a sheet's ink differently from the sheet it was drawn on.
void paintSheetInkWindow(
  Canvas canvas,
  ui.Image image,
  Rect rect,
  double scale,
) {
  canvas.save();
  canvas.clipRect(rect);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, rect.width * scale, rect.height * scale),
    rect,
    Paint()..filterQuality = FilterQuality.medium,
  );
  canvas.restore();
}

/// Lays down a sheet's PAPER — the one way the timesheet, the conte and the
/// cut envelope fill it.
///
/// 🚨NOT anti-aliased (F-179, 유저 2026-09-25: 「용지 외곽에 반투명 라인
/// 있는데 이런거 필요없어」). A sheet's view never rotates, and its paper
/// edge lands wherever zoom × page size puts it — a fractional device
/// position more often than not. An anti-aliased fill covers that pixel
/// partly: a one-pixel line of paper blended over the backdrop, around
/// every page. Cut on the pixel centres, the edge is the same hard boundary
/// F-67 gives the drawing canvas's paper.
///
/// ↩️The timesheet also stroked a 1.4px border ON its page edge, half of
/// it over the backdrop — the other line. It is gone, not moved here.
void paintSheetPaper(Canvas canvas, Rect rect, Color color) {
  canvas.drawRect(
    rect,
    Paint()
      ..color = color
      ..isAntiAlias = false,
  );
}

/// Puts [canvas] into a sheet's PAPER units, either through the panel's
/// live viewport or by fitting the paper into [size].
///
/// ⛔BOTH SHEETS OPEN THIS WAY, AND THE COMMENT THAT MATTERS IS THE SHARED
/// ONE: the snap ALREADY HAPPENED at the host, so this viewport and the
/// one the ink windows derive from are the same value — which is what
/// keeps written ink on its cell. Passing the ratio here keeps that snap
/// idempotent rather than re-rounding to a coarser grid. Written out per
/// sheet, one of them starts re-rounding and its ink drifts off the boxes.
///
/// With no viewport it is the EXPORT/PREVIEW path: the export renders at
/// paper size (scale 1) and a preview at a fraction of it, both from these
/// same paper units.
void enterSheetPaperSpace(
  Canvas canvas,
  Size size,
  ({CanvasViewport? viewport, double devicePixelRatio, Size paper}) sheet,
) {
  final viewport = sheet.viewport;
  if (viewport != null) {
    canvas.clipRect(Offset.zero & size);
    applyViewportTransform(
      canvas,
      viewport,
      devicePixelRatio: sheet.devicePixelRatio,
    );
    return;
  }
  final scale = math.min(
    size.width / sheet.paper.width,
    size.height / sheet.paper.height,
  );
  canvas.scale(scale, scale);
}

/// Where a sheet's paper units land on the device: the panel's snapped
/// viewport, or the export's fit.
class SheetDeviceGrid {
  const SheetDeviceGrid._({
    required this.scale,
    required this.dx,
    required this.dy,
    required this.devicePixelRatio,
  });

  /// [enterSheetPaperSpace]'s two ways, said as a transform: the panel's
  /// viewport (already snapped by the host — P8 — and snapped again here,
  /// which changes nothing), or the paper fitted into [size] one pixel per
  /// canvas unit.
  factory SheetDeviceGrid.of(
    Size size,
    ({CanvasViewport? viewport, double devicePixelRatio, Size paper}) sheet,
  ) {
    final viewport = sheet.viewport;
    if (viewport != null) {
      final snapped = renderSnappedViewport(viewport, sheet.devicePixelRatio);
      return SheetDeviceGrid._(
        scale: snapped.zoom,
        dx: snapped.panX,
        dy: snapped.panY,
        devicePixelRatio: sheet.devicePixelRatio,
      );
    }
    return SheetDeviceGrid._(
      scale: math.min(
        size.width / sheet.paper.width,
        size.height / sheet.paper.height,
      ),
      dx: 0,
      dy: 0,
      devicePixelRatio: 1,
    );
  }

  final double scale;
  final double dx;
  final double dy;
  final double devicePixelRatio;

  /// 🚨THE ONE ROUNDING every fill edge and rule edge on a sheet goes
  /// through, from paper units to the device grid and back to canvas units:
  /// a silhouette that ends at x and a rule whose edge is x land on the same
  /// device pixel because they are the same call (유저 2026-09-25: 「절대
  /// 어긋나지않도록」). A rule drawn anti-aliased over a fill cut on the grid
  /// is a line and an edge that disagree by a fraction of a pixel.
  double _x(double paperX) =>
      ((dx + scale * paperX) * devicePixelRatio).roundToDouble() /
      devicePixelRatio;

  double _y(double paperY) =>
      ((dy + scale * paperY) * devicePixelRatio).roundToDouble() /
      devicePixelRatio;

  /// [rect] cut on the device grid.
  Rect snap(Rect rect) => Rect.fromLTRB(
    _x(rect.left),
    _y(rect.top),
    _x(rect.right),
    _y(rect.bottom),
  );

  /// [rule]'s rectangle cut on the grid — never thinner than one device
  /// pixel, so a rule survives any zoom out, and widened AWAY from the edge
  /// it holds ([SheetRule.hold]), so that edge still meets the mark it
  /// shares it with.
  Rect snapRule(SheetRule rule) {
    final cut = snap(rule.rect);
    final pixel = 1 / devicePixelRatio;
    (double, double) across(double near, double far, double middle) {
      if (far - near >= pixel - 1e-9) {
        return (near, far);
      }
      // The device pixel the rule's middle falls in.
      final start = middle.floorToDouble() / devicePixelRatio;
      return switch (rule.hold) {
        SheetRuleHold.near => (near, near + pixel),
        SheetRuleHold.far => (far - pixel, far),
        SheetRuleHold.middle => (start, start + pixel),
      };
    }

    final centre = rule.rect.center;
    if (rule.isUpright) {
      final (left, right) = across(
        cut.left,
        cut.right,
        (dx + scale * centre.dx) * devicePixelRatio,
      );
      return Rect.fromLTRB(
        left,
        cut.top,
        right,
        math.max(cut.bottom, cut.top + pixel),
      );
    }
    final (top, bottom) = across(
      cut.top,
      cut.bottom,
      (dy + scale * centre.dy) * devicePixelRatio,
    );
    return Rect.fromLTRB(
      cut.left,
      top,
      math.max(cut.right, cut.left + pixel),
      bottom,
    );
  }

  void enterPaperSpace(Canvas canvas) {
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);
  }
}

/// The images a Canvas printer finds by what a mark names.
class SheetMarkImages {
  const SheetMarkImages({
    this.pictureFor,
    this.imageFor,
    this.inkImageFor,
    this.liveInkKeys = const {},
    this.inkScale = 1,
  });

  final ui.Image? Function(String cutId, int pictureFrame)? pictureFor;
  final ui.Image? Function(String assetPath)? imageFor;
  final ui.Image? Function(BrushFrameKey key)? inkImageFor;

  /// Keys a LIVE input window is already showing: skipped, so translucent
  /// ink never composites twice.
  final Set<BrushFrameKey> liveInkKeys;

  /// Ink raster pixels per paper unit.
  final double inkScale;
}

/// The face a sheet sets its words in.
typedef SheetTextStyle =
    TextStyle Function(double size, {required bool bold, required Color color});

/// The size [words] print at: their own, or for [SheetWordsFit.shrink] the
/// largest up to it that sets the line within the slot's width.
///
/// ⛔ONE MEASUREMENT for every printer — the engine's, in [style]'s face;
/// the PDF prints at the size this returns rather than measuring its own
/// glyph runs, the way it prints the lines `conteWrappedLines` broke.
/// Width scales with size, so one measurement at the largest size gives
/// the fitted one; it is rounded DOWN to a tenth of a point so the line
/// never comes out a hair wider than its slot.
double sheetWordsSize(SheetWords words, SheetTextStyle style) {
  if (words.fit != SheetWordsFit.shrink || words.text.isEmpty) {
    return words.size;
  }
  final painter = TextPainter(
    text: TextSpan(
      text: words.text,
      style: style(words.size, bold: words.bold, color: Color(words.argb)),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  if (width <= words.slot.width || width <= 0) {
    return words.size;
  }
  return (words.size * words.slot.width / width * 10).floorToDouble() / 10;
}

/// Prints [marks] onto [canvas], in their order — the screen's and the PNG's
/// printer (the PDF replays the same list).
///
/// Fills and rules are cut on the device grid ([SheetDeviceGrid]) and drawn
/// without anti-aliasing; words, pictures and ink are drawn in paper space.
void paintSheetMarks(
  Canvas canvas,
  Size size,
  ({CanvasViewport? viewport, double devicePixelRatio, Size paper}) sheet,
  Iterable<SheetMark> marks, {
  required SheetTextStyle style,
  Set<SheetPaintLayer>? layers,
  SheetMarkImages images = const SheetMarkImages(),
}) {
  final grid = SheetDeviceGrid.of(size, sheet);
  canvas.save();
  if (sheet.viewport != null) {
    canvas.clipRect(Offset.zero & size);
  }
  for (final mark in marks) {
    if (layers != null && !layers.contains(mark.layer)) {
      continue;
    }
    _printMark(canvas, grid, mark, style, images);
  }
  canvas.restore();
}

void _printMark(
  Canvas canvas,
  SheetDeviceGrid grid,
  SheetMark mark,
  SheetTextStyle style,
  SheetMarkImages images,
) {
  switch (mark) {
    case SheetFill(:final rect, :final argb, :final cornerRadius)
        when cornerRadius > 0:
      // The app's corner. A corner is a curve, so it is anti-aliased; the
      // flat sides are still cut on the grid, so they stay one colour to
      // the pixel.
      canvas.drawRSuperellipse(
        ui.RSuperellipse.fromRectAndRadius(
          grid.snap(rect),
          Radius.circular(cornerRadius * grid.scale),
        ),
        Paint()..color = Color(argb),
      );
    case SheetFill(:final rect, :final argb):
      canvas.drawRect(
        grid.snap(rect),
        Paint()
          ..color = Color(argb)
          ..isAntiAlias = false,
      );
    case SheetRule(:final argb):
      canvas.drawRect(
        grid.snapRule(mark),
        Paint()
          ..color = Color(argb)
          ..isAntiAlias = false,
      );
    case SheetWords():
      _inPaperSpace(canvas, grid, () => _paintWords(canvas, mark, style));
    case SheetPicture(
      :final cutId,
      :final pictureFrame,
      :final slot,
      :final cornerRadius,
    ):
      final image = images.pictureFor?.call(cutId, pictureFrame);
      if (image != null) {
        _inPaperSpace(canvas, grid, () {
          canvas.save();
          if (cornerRadius > 0) {
            canvas.clipRSuperellipse(
              ui.RSuperellipse.fromRectAndRadius(
                slot,
                Radius.circular(cornerRadius),
              ),
            );
          }
          _paintContained(canvas, image, slot, FilterQuality.medium);
          canvas.restore();
        });
      }
    case SheetImage(:final assetPath, :final slot):
      final image = images.imageFor?.call(assetPath);
      if (image != null) {
        _inPaperSpace(
          canvas,
          grid,
          () => _paintContained(canvas, image, slot, FilterQuality.high),
        );
      }
    case SheetInk(:final key, :final rect):
      final image = images.liveInkKeys.contains(key)
          ? null
          : images.inkImageFor?.call(key);
      if (image != null) {
        _inPaperSpace(
          canvas,
          grid,
          () => paintSheetInkWindow(canvas, image, rect, images.inkScale),
        );
      }
  }
}

void _inPaperSpace(Canvas canvas, SheetDeviceGrid grid, VoidCallback draw) {
  canvas.save();
  grid.enterPaperSpace(canvas);
  draw();
  canvas.restore();
}

void _paintContained(
  Canvas canvas,
  ui.Image image,
  Rect slot,
  FilterQuality quality,
) {
  if (slot.width <= 0 || slot.height <= 0) {
    return;
  }
  final source = Size(image.width.toDouble(), image.height.toDouble());
  canvas.drawImageRect(
    image,
    Offset.zero & source,
    containRect(source, slot),
    Paint()..filterQuality = quality,
  );
}

/// Words wrapped to their slot's width, clipped to it, set where they are
/// told. The layout is [TextPainter]'s — the conte's PDF prints the lines
/// this very layout breaks (`conteWrappedLines`), and aligns EACH line the
/// way [TextAlign] does here, so a wrapped title centres line by line on
/// both.
void _paintWords(Canvas canvas, SheetWords words, SheetTextStyle style) {
  final slot = words.slot;
  if (words.text.isEmpty || slot.width <= 0 || slot.height <= 0) {
    return;
  }
  final size = sheetWordsSize(words, style);
  final painter = TextPainter(
    text: TextSpan(
      text: words.text,
      style: style(size, bold: words.bold, color: Color(words.argb)),
    ),
    textAlign: switch (words.h) {
      SheetAlign.start => TextAlign.left,
      SheetAlign.center => TextAlign.center,
      SheetAlign.end => TextAlign.right,
    },
    textDirection: TextDirection.ltr,
  )..layout(
      maxWidth: words.fit == SheetWordsFit.wrap ? slot.width : double.infinity,
    );
  final x = switch (words.h) {
    SheetAlign.start => slot.left,
    SheetAlign.center => slot.left + (slot.width - painter.width) / 2,
    SheetAlign.end => slot.right - painter.width,
  };
  final y = switch (words.v) {
    SheetAlign.start => slot.top,
    SheetAlign.center => slot.top + (slot.height - painter.height) / 2,
    SheetAlign.end => slot.bottom - painter.height,
  };
  canvas.save();
  canvas.clipRect(slot);
  painter.paint(canvas, Offset(x, y));
  canvas.restore();
  painter.dispose();
}
