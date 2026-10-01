import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../core/contain_rect.dart';
import '../core/convex_clip.dart' show convexIntersection;
import '../models/brush_frame_key.dart';
import '../models/canvas_viewport.dart';
import '../models/sheet_marks.dart';
import '../models/sheet_paint_layer.dart';
import 'canvas/display_resample.dart';
import 'canvas/viewport_canvas_transform.dart';

/// Draws one baked ink window: the raster where its [placement] lays it,
/// clipped to the window so a stroke that ran past the box does not bleed
/// into its neighbour.
///
/// ⛔EVERY SHEET DRAWS INK THIS WAY. The conte page and the cut envelope
/// each wrote out the save / clip / drawImageRect / restore with the same
/// medium filter, and the PDF laid its own; where the raster lands is the
/// part that has to agree with whatever rendered the ink, so two copies of
/// it is two chances to scale a sheet's ink differently from the sheet it
/// was drawn on.
void paintSheetInkWindow(
  Canvas canvas,
  ui.Image image,
  SheetInkPlacement placement,
) {
  canvas.save();
  canvas.clipRect(placement.window);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    placement.rasterRect(image.width, image.height),
    Paint()..filterQuality = FilterQuality.medium,
  );
  canvas.restore();
}

/// Draws [image] contained in [slot] — as large as fits, centred, its own
/// shape kept — the way every sheet prints a media image. (A cell's picture
/// fills the frame its mark names instead — [SheetPicture.frame].)
void paintSheetImageContained(
  Canvas canvas,
  ui.Image image,
  Rect slot,
  FilterQuality quality,
) {
  if (slot.width <= 0 || slot.height <= 0) {
    return;
  }
  paintSheetImageIn(
    canvas,
    image,
    containRect(Size(image.width.toDouble(), image.height.toDouble()), slot),
    quality,
  );
}

/// The quality a cell's picture, [image] as it was rendered, is laid into
/// its [shot] with: what is left of the reduction, as the canvas's display
/// takes it — the picture was rendered down by the display's own levels
/// (`CameraFrameRenderService.renderThroughCamera`'s `displayLevels`), so
/// the print and the live composite beside it reduce one way (F-215, 유저
/// 2026-09-30: 「왜 브러시허용이랑 렌더링이랑 연관있는거냐고」). ↩️It was
/// `medium`, which mipmaps where an engine has mips and does not where it
/// has none.
FilterQuality sheetPictureQuality(
  ui.Image image,
  Rect shot,
  double devicePixelRatio,
) => filterQualityForDisplayScale(shot.width * devicePixelRatio / image.width);

/// Draws [image] filling [rect] — the one image draw a sheet prints a
/// picture or a media image through, owning the quality its caller names.
void paintSheetImageIn(
  Canvas canvas,
  ui.Image image,
  Rect rect,
  FilterQuality quality,
) {
  canvas.drawImageRect(
    image,
    Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
    rect,
    Paint()..filterQuality = quality,
  );
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
      return SheetDeviceGrid.through(viewport, sheet.devicePixelRatio);
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

  /// The panel's way alone: its [viewport] at [devicePixelRatio] — for a
  /// layer over the page that has no size of its own to fit.
  factory SheetDeviceGrid.through(
    CanvasViewport viewport,
    double devicePixelRatio,
  ) {
    final snapped = renderSnappedViewport(viewport, devicePixelRatio);
    return SheetDeviceGrid._(
      scale: snapped.zoom,
      dx: snapped.panX,
      dy: snapped.panY,
      devicePixelRatio: devicePixelRatio,
    );
  }

  final double scale;
  final double dx;
  final double dy;
  final double devicePixelRatio;

  /// 🚨THE ONE ROUNDING every fill, rule and picture edge on a sheet goes
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

  /// The device pixels [rect] covers WHOLLY — its edges moved in to the
  /// grid, where [snap] moves them to the nearest line. For a view laid over
  /// the page that must never show past what it draws.
  Rect inside(Rect rect) {
    double on(double at, double Function(double device) round) =>
        round(at * devicePixelRatio) / devicePixelRatio;
    const slack = 1e-6;
    double up(double device) => (device - slack).ceilToDouble();
    double down(double device) => (device + slack).floorToDouble();
    return Rect.fromLTRB(
      on(dx + scale * rect.left, up),
      on(dy + scale * rect.top, up),
      on(dx + scale * rect.right, down),
      on(dy + scale * rect.bottom, down),
    );
  }

  /// [paper] where this grid lays it, off the grid — a point of a shape the
  /// grid does not cut: the cut's canvas, turned with its camera.
  Offset onDevice(Offset paper) =>
      Offset(dx + scale * paper.dx, dy + scale * paper.dy);

  /// Where [picture]'s PRINT shows on this grid: the frame it fills, cut
  /// on the NEAREST lines, as the well under it is.
  Rect printedPicture(SheetPicture picture) => snap(picture.frame);

  /// Where a LIVE composite of [picture] shows on this grid: its frame cut
  /// INSIDE (F-197) — the composite ends where its frame ends, and a clip
  /// reaching past that end showed the ground under the frame's edge, a
  /// light line round a dark picture.
  Rect livePicture(SheetPicture picture) => inside(picture.frame);

  /// Where [shot] shows the cut's canvas: the shot, and in it the canvas
  /// [canvas] outlines on the paper. The paper's own ink shows everywhere
  /// else — up to this edge, on this grid, and the piece of a stroke either
  /// side keeps a ring past it (`sheetInkApron`, F-216).
  Path pictureCanvas(Rect shot, List<Offset> canvas) => Path.combine(
    PathOperation.intersect,
    Path()..addRect(shot),
    Path()..addPolygon([for (final point in canvas) onDevice(point)], true),
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

/// A picture the paper's ink yields to: the picture, [canvas] — the corners
/// of the cut's canvas on the paper, as its camera lays them — and
/// [canvasToPaper], the map that lays them there (`conteCanvasToPaper`):
/// the one its live composite is drawn through, and so the one its print
/// is laid by (F-215).
typedef SheetPictureOverInk = ({
  SheetPicture picture,
  List<Offset> canvas,
  Matrix4 canvasToPaper,
});

/// Where [over]'s picture shows its cut's canvas on [grid], the brush on or
/// off: its frame cut INSIDE, as its live composite is
/// ([SheetDeviceGrid.livePicture], F-197), and in it the canvas — what the
/// paper's ink yields to on screen (F-216), in a live window and in the
/// print alike (F-215).
Path pictureShowsOnScreen(SheetDeviceGrid grid, SheetPictureOverInk over) =>
    grid.pictureCanvas(grid.livePicture(over.picture), over.canvas);

/// The view a picture's live composite draws its cut's canvas through: the
/// page's [view] after [canvasToPaper]. Its painter snaps it to the device
/// grid at its own scale ([renderSnappedViewport]).
CanvasViewport pictureCanvasViewport(
  CanvasViewport view,
  Matrix4 canvasToPaper,
) => viewportOfSimilarity(
  viewportTransformMatrix(view).multiplied(canvasToPaper),
)!;

/// Where the print of [over]'s picture is laid on screen so that each of its
/// pixels lands where the live composite shows it (F-215, 유저 2026-10-01:
/// 「픽쳐칸 그림은 왼쪽위 0.5픽셀?1픽셀? 이동. 대체 왜?」): its frame through
/// the page's [view], moved by the snap the composite's own painter gives
/// the canvas ([pictureCanvasViewport]). ↩️It was the frame cut on the
/// page's grid ([SheetDeviceGrid.printedPicture]): the print pinned its
/// edges to the grid, the composite its canvas's origin, and the brush
/// switch moved the picture by the difference.
Rect pictureLaidAsLive(
  SheetPictureOverInk over,
  CanvasViewport view,
  double devicePixelRatio,
) {
  final canvas = pictureCanvasViewport(view, over.canvasToPaper);
  final snapped = renderSnappedViewport(canvas, devicePixelRatio);
  final frame = over.picture.frame;
  return Rect.fromLTRB(
    view.panX + view.zoom * frame.left,
    view.panY + view.zoom * frame.top,
    view.panX + view.zoom * frame.right,
    view.panY + view.zoom * frame.bottom,
  ).shift(Offset(snapped.panX - canvas.panX, snapped.panY - canvas.panY));
}

/// Where [over] shows its cut's canvas, exactly, on the paper: the
/// camera's frame in its slot, and the canvas in it — what the pen takes
/// for the picture, and what no ink on the paper shows in a print that
/// needs no grid (the PDF).
List<Offset> pictureOutline(SheetPictureOverInk over) {
  final frame = over.picture.frame;
  return convexIntersection([
    frame.topLeft,
    frame.topRight,
    frame.bottomRight,
    frame.bottomLeft,
  ], over.canvas);
}

/// [picture]'s image — what its [SheetPicture.key] names — for a window
/// that draws it [shownHeight] device pixels tall: what the panel's picture
/// law is asked with. An export's pictures are rendered before it prints,
/// and ignore it.
typedef SheetPictureLookup =
    ui.Image? Function(SheetPicture picture, double shownHeight);

/// The images a Canvas printer finds by what a mark names.
class SheetMarkImages {
  const SheetMarkImages({
    this.pictureFor,
    this.imageFor,
    this.inkImageFor,
    this.liveInkKeys = const {},
  });

  final SheetPictureLookup? pictureFor;
  final ui.Image? Function(String assetPath)? imageFor;
  final ui.Image? Function(BrushFrameKey key)? inkImageFor;

  /// Keys a LIVE input window is already showing: skipped, so translucent
  /// ink never composites twice.
  final Set<BrushFrameKey> liveInkKeys;
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

/// The Canvas printer of [SheetMark]s — the screen's and the PNG's (the PDF
/// replays the same list).
///
/// Fills, rules and pictures are cut on the device grid ([SheetDeviceGrid]),
/// flat fills and rules without anti-aliasing; words, lines and ink are
/// drawn in paper space.
class SheetCanvasPrinter {
  const SheetCanvasPrinter({
    required this.style,
    this.layers,
    this.images = const SheetMarkImages(),
    this.picturesOverInk = const [],
  });

  /// The face the words print in.
  final SheetTextStyle style;

  /// The strata printed, or null for every one.
  final Set<SheetPaintLayer>? layers;

  final SheetMarkImages images;

  /// The pictures the paper's ink yields to: no ink shows where one shows
  /// its cut's canvas, up to the edge its print shows it by (F-216).
  final List<SheetPictureOverInk> picturesOverInk;

  /// Prints [marks] onto [canvas], in their order.
  void paint(
    Canvas canvas,
    Size size,
    ({CanvasViewport? viewport, double devicePixelRatio, Size paper}) sheet,
    Iterable<SheetMark> marks,
  ) {
    final page = _SheetCanvas(
      canvas,
      SheetDeviceGrid.of(size, sheet),
      sheet.viewport,
      this,
    );
    canvas.save();
    if (sheet.viewport != null) {
      canvas.clipRect(Offset.zero & size);
    }
    for (final mark in marks) {
      if (layers?.contains(mark.layer) ?? true) {
        page.printMark(mark);
      }
    }
    canvas.restore();
  }
}

/// One [SheetCanvasPrinter.paint]: the canvas, where its paper lands on the
/// device, and the printer's face and images.
class _SheetCanvas {
  _SheetCanvas(this.canvas, this.grid, this.view, this.printer);

  final Canvas canvas;
  final SheetDeviceGrid grid;

  /// The panel's view, as it is handed in — before the grid snaps it — or
  /// null for an export, which has none.
  final CanvasViewport? view;

  final SheetCanvasPrinter printer;

  void printMark(SheetMark mark) {
    final images = printer.images;
    switch (mark) {
      case SheetFill():
        _fill(mark);
      case SheetRule(:final argb):
        _flat(grid.snapRule(mark), argb);
      case SheetWords():
        _inPaperSpace(() => _words(mark));
      case SheetStroke():
        _inPaperSpace(() => _stroke(mark));
      case SheetPicture():
        _picture(mark);
      case SheetImage(:final assetPath, :final slot):
        final image = images.imageFor?.call(assetPath);
        if (image != null) {
          _inPaperSpace(
            () => paintSheetImageContained(
              canvas,
              image,
              slot,
              FilterQuality.high,
            ),
          );
        }
      case SheetInk(:final key, :final placement):
        final image = images.liveInkKeys.contains(key)
            ? null
            : images.inkImageFor?.call(key);
        if (image != null) {
          canvas.save();
          _yieldToPictures(placement.window);
          _inPaperSpace(
            () => paintSheetInkWindow(canvas, image, placement),
          );
          canvas.restore();
        }
    }
  }

  /// No ink of [window] shows where a picture over it shows its cut's
  /// canvas — cut at the edge the print shows that picture by, so the ink's
  /// ring past the edge (`sheetInkApron`) never lies over the picture. An
  /// export's: on screen the ink is printed as the live windows draw it,
  /// and yields where they do ([pictureShowsOnScreen], F-215).
  void _yieldToPictures(Rect window) {
    final over = [
      for (final picture in printer.picturesOverInk)
        if (picture.picture.slot.overlaps(window)) picture,
    ];
    if (over.isEmpty) {
      return;
    }
    var shows = Path()
      ..addRect(
        Rect.fromPoints(
          grid.onDevice(window.topLeft),
          grid.onDevice(window.bottomRight),
        ).inflate(1),
      );
    for (final (:picture, canvas: cut, canvasToPaper: _) in over) {
      shows = Path.combine(
        PathOperation.difference,
        shows,
        grid.pictureCanvas(grid.printedPicture(picture), cut),
      );
    }
    canvas.clipPath(shows);
  }

  /// A fill cut on the grid, one colour to the pixel.
  void _fill(SheetFill fill) => _flat(grid.snap(fill.rect), fill.argb);

  void _flat(Rect rect, int argb) {
    canvas.drawRect(
      rect,
      Paint()
        ..color = Color(argb)
        ..isAntiAlias = false,
    );
  }

  /// A picture cut on the grid its window is cut on: its frame filled to
  /// the device pixels the well under it fills ([_fill]).
  ///
  /// 🗣️F-197 (유저 2026-09-27): 「해당컷 채우기로 전면 검정색됫는데 …
  /// 줌하거나 팬할때 그림이랑 실루엣 경계에 흰 여백? 선이 생김」 · 「팬은
  /// 아니고 줌할때마다 생김」. The picture was drawn in paper space over a
  /// well cut on the grid: wherever a zoom put the window's edge inside a
  /// device pixel, the picture covered part of that pixel and the light well
  /// showed through the rest. A pan keeps each edge's place in its pixel
  /// (whole pixels, the snap's phase), so only a zoom ever moved it.
  ///
  /// On screen the print is laid again over that, where the live composite
  /// shows each of its pixels ([pictureLaidAsLive], F-215) and cut at the
  /// window's edge: the copy under it keeps the edge covered whichever way
  /// the composite's snap moves the picture.
  void _picture(SheetPicture picture) {
    final shot = grid.printedPicture(picture);
    final image = printer.images.pictureFor?.call(
      picture,
      shot.height * grid.devicePixelRatio,
    );
    if (image == null) {
      return;
    }
    paintSheetImageIn(
      canvas,
      image,
      shot,
      sheetPictureQuality(image, shot, grid.devicePixelRatio),
    );
    final laid = _laidAsLive(picture);
    if (laid == null) {
      return;
    }
    canvas.save();
    canvas.clipRect(shot);
    paintSheetImageIn(
      canvas,
      image,
      laid,
      sheetPictureQuality(image, laid, grid.devicePixelRatio),
    );
    canvas.restore();
  }

  /// Where [picture]'s live composite would lay it, on screen — null for an
  /// export, and for a picture no ink yields to (no map of its canvas).
  Rect? _laidAsLive(SheetPicture picture) {
    final shown = view;
    if (shown == null) {
      return null;
    }
    for (final over in printer.picturesOverInk) {
      if (over.picture == picture) {
        return pictureLaidAsLive(over, shown, grid.devicePixelRatio);
      }
    }
    return null;
  }

  /// A line, anti-aliased: a camera's frame may be turned, and no grid
  /// holds a turned edge.
  void _stroke(SheetStroke stroke) {
    if (stroke.points.length < 2) {
      return;
    }
    canvas.drawPath(
      Path()..addPolygon(stroke.points, stroke.closed),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.width
        ..strokeJoin = StrokeJoin.miter
        ..color = Color(stroke.argb),
    );
  }

  void _inPaperSpace(VoidCallback draw) {
    canvas.save();
    grid.enterPaperSpace(canvas);
    draw();
    canvas.restore();
  }

  /// Words wrapped to their slot's width, clipped to it, set where they are
  /// told. The layout is [TextPainter]'s — the conte's PDF prints the lines
  /// this very layout breaks (`conteWrappedLines`), and aligns EACH line the
  /// way [TextAlign] does here, so a wrapped title centres line by line on
  /// both.
  void _words(SheetWords words) {
    if (words.printsNothing) {
      return;
    }
    final slot = words.slot;
    final size = sheetWordsSize(words, printer.style);
    final painter = TextPainter(
      text: TextSpan(
        text: words.text,
        style: printer.style(size, bold: words.bold, color: Color(words.argb)),
      ),
      textAlign: switch (words.h) {
        SheetAlign.start => TextAlign.left,
        SheetAlign.center => TextAlign.center,
        SheetAlign.end => TextAlign.right,
      },
      textDirection: TextDirection.ltr,
    )..layout(
        maxWidth: words.fit == SheetWordsFit.wrap
            ? slot.width
            : double.infinity,
      );
    canvas.save();
    if (words.turn != 0) {
      canvas.translate(slot.left, slot.top);
      canvas.rotate(words.turn);
      canvas.translate(-slot.left, -slot.top);
    }
    canvas.clipRect(slot);
    painter.paint(
      canvas,
      Offset(
        words.h.place(slot.left, slot.width, painter.width),
        words.v.place(slot.top, slot.height, painter.height),
      ),
    );
    canvas.restore();
    painter.dispose();
  }
}
