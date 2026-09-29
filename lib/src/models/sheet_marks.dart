/// What a sheet page PRINTS, as one list every printer reads.
///
/// ⛔THE CONTE WAS PRINTED TWICE. The panel's (and the PNG's) Canvas painter
/// and the PDF writer each walked the same layout and drew every rule,
/// frame, label and value for themselves — the PDF's half was headed
/// 「painter mirrors」. Two walks of one page are two chances to print it
/// differently, and a form whose header must meet its body on one line
/// (유저 2026-09-25: 「헤더의 사각형 실루엣 선이랑 아래쪽 본문이랑 라인이
/// 미묘하게 어긋나있거나 하는데 절대 어긋나지않도록」) cannot be kept that
/// way in two places. The page is decided ONCE, as marks; a printer only
/// replays them.
///
/// Units are the sheet's own paper units (points for the conte). Nothing
/// here knows a canvas, a PDF or a widget.
library;

import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart' show listEquals;

import 'brush_frame_key.dart';
import 'sheet_paint_layer.dart';

/// One printed mark, in the stratum it belongs to ([SheetPaintLayer]) — the
/// panel bakes the form and the values apart, and a focused test or an
/// export can ask for any subset.
sealed class SheetMark {
  const SheetMark(this.layer);

  final SheetPaintLayer layer;

  /// Everything this mark prints besides its [layer], as one value: two
  /// marks that print alike are equal, so a baked stratum can tell whether
  /// what it prints changed without printing it ([SheetStratum]).
  Object get _prints;

  @override
  bool operator ==(Object other) =>
      other is SheetMark &&
      other.runtimeType == runtimeType &&
      other.layer == layer &&
      other._prints == _prints;

  @override
  int get hashCode => Object.hash(runtimeType, layer, _prints);
}

/// A filled rectangle: the paper, a picture's frame, a window's tone.
///
/// Its edges are cut on the device grid (F-179): a sheet never rotates, so
/// every fill is axis-aligned, and an edge cut on the grid is wholly one
/// colour or the other — the paper's own rule, for everything a sheet
/// fills.
final class SheetFill extends SheetMark {
  const SheetFill(super.layer, {required this.rect, required this.argb});

  final Rect rect;
  final int argb;

  @override
  Object get _prints => (rect, argb);
}

/// Which long edge of a rule holds its place when the rule is widened to
/// one device pixel — the edge it shares with the page's other marks.
///
/// A rule thinner than a pixel on screen is widened rather than dropped (a
/// table without its lines cannot be read), and widened about its middle the
/// header's picture-column side stood a pixel OUTSIDE the silhouette it
/// continues (measured at zoom 0.37: its edge on 130, the black's on 129).
enum SheetRuleHold {
  /// The left edge of an upright rule, the top edge of a lying one.
  near,

  /// Neither: the rule takes the pixel its middle falls in.
  middle,

  /// The right edge of an upright rule, the bottom edge of a lying one.
  far,
}

/// A straight rule, as the RECTANGLE it covers.
///
/// ⛔Not a centre line and a width. An edge that must meet another mark's
/// edge is NAMED here — the header's right side ends at the very number the
/// silhouette ends at. Worked out as `(x - w/2) + w/2` it is not always x in
/// floating point, and a rounding that sits on half a pixel turns that last
/// bit into a whole one. Corners close because the rectangles overlap there.
final class SheetRule extends SheetMark {
  const SheetRule(
    super.layer, {
    required this.rect,
    required this.argb,
    this.hold = SheetRuleHold.middle,
  });

  final Rect rect;
  final int argb;
  final SheetRuleHold hold;

  @override
  Object get _prints => (rect, argb, hold);

  /// Upright — thinner across than along.
  bool get isUpright => rect.width < rect.height;
}

/// Where words sit in their slot, on one axis.
enum SheetAlign {
  start,
  center,
  end;

  /// Where a run [extent] long starts in the span [span] long from [from] —
  /// the one placement every printer sets words by, on either axis.
  double place(double from, double span, double extent) => switch (this) {
    start => from,
    center => from + (span - extent) / 2,
    end => from + span - extent,
  };
}

/// How words meet a slot narrower than they are.
enum SheetWordsFit {
  /// Broken into lines at the slot's width — a column's prose.
  wrap,

  /// ONE line, never broken — a number is one word, and 「3+1」 over 「2」
  /// reads as two numbers. What outruns the slot is clipped at its edge.
  oneLine,

  /// One line at [SheetWords.size], or smaller — as large as fits the
  /// slot's width (유저 2026-09-25, the cover's title: 「길어져서 다
  /// 안들어가면 크기 작게하는방향, 기본적으로 그렇게」).
  shrink,
}

/// Words laid into [slot], clipped to it.
final class SheetWords extends SheetMark {
  const SheetWords(
    super.layer, {
    required this.text,
    required this.slot,
    required this.size,
    required this.argb,
    this.bold = false,
    this.h = SheetAlign.start,
    this.v = SheetAlign.start,
    this.fit = SheetWordsFit.wrap,
    this.turn = 0,
  });

  final String text;
  final Rect slot;

  /// The size the words are set at — for [SheetWordsFit.shrink], the
  /// largest they may be.
  final double size;
  final int argb;
  final bool bold;
  final SheetAlign h;
  final SheetAlign v;
  final SheetWordsFit fit;

  /// How far the words are turned — radians, clockwise on the page — about
  /// the slot's top-left corner, slot and all: a camera key's name written
  /// along its turned frame (유저 2026-09-29: 「기운 틀의 모서리. 각도
  /// 그대로따라감」).
  final double turn;

  @override
  Object get _prints => (text, slot, size, argb, bold, h, v, fit, turn);

  /// Nothing to set, or nowhere to set it: every printer skips these words.
  bool get printsNothing =>
      text.isEmpty || slot.width <= 0 || slot.height <= 0;
}

/// A line through [points], [width] wide — open, or [closed] into an
/// outline: a camera key's frame on a picture, the trail each of its
/// corners draws. A frame the camera turned is no rectangle, so it is no
/// fill.
final class SheetStroke extends SheetMark {
  const SheetStroke(
    super.layer, {
    required this.points,
    required this.argb,
    required this.width,
    this.closed = false,
  });

  final List<Offset> points;
  final int argb;
  final double width;
  final bool closed;

  @override
  Object get _prints => (_Points(points), argb, width, closed);
}

/// Points compared by what they hold — a list is equal only to itself, and
/// a mark's [SheetMark._prints] must say whether it prints alike.
final class _Points {
  const _Points(this.points);

  final List<Offset> points;

  @override
  bool operator ==(Object other) =>
      other is _Points && listEquals(other.points, points);

  @override
  int get hashCode => Object.hashAll(points);
}

/// What a picture's image is found by: its cut at its frame, through the
/// camera or over [SheetPicture.canvasRegion] — the panel's picture store
/// and an export's rendered pictures both key by it.
typedef SheetPictureKey = ({
  String cutId,
  int pictureFrame,
  Rect? canvasRegion,
});

/// A cell's picture: the camera's [frame], in its [slot]. The printer finds
/// the image by its [key] — the panel in its thumbnail store, the PDF among
/// the pictures its export rendered.
final class SheetPicture extends SheetMark {
  const SheetPicture(
    super.layer, {
    required this.cutId,
    required this.pictureFrame,
    required this.slot,
    required this.frame,
    this.canvasRegion,
  });

  final String cutId;
  final int pictureFrame;
  final Rect slot;

  /// Where the camera's frame lies in [slot] — the whole slot when the slot
  /// has the camera's shape. Every printer fills it with the image, and the
  /// pen draws through it.
  ///
  /// ⛔Not worked out from the image: a picture rendered N pixels wide is
  /// the camera's shape only to the nearest pixel of its height, and a
  /// contain on those pixels left a sliver of the window uncovered — the
  /// page, the PDF and the pen each answered where the picture was (F-197).
  /// Over a [canvasRegion], it is where that region lies.
  final Rect frame;

  /// The canvas the picture shows, square to it, where its cell's camera
  /// moves — the region that camera sweeps (`ConteCameraWork.field`); null
  /// for what the camera shows at [pictureFrame].
  final Rect? canvasRegion;

  SheetPictureKey get key => (
    cutId: cutId,
    pictureFrame: pictureFrame,
    canvasRegion: canvasRegion,
  );

  @override
  Object get _prints => (cutId, pictureFrame, slot, frame, canvasRegion);
}

/// A media image — the company logo — contained in [slot].
final class SheetImage extends SheetMark {
  const SheetImage(super.layer, {required this.assetPath, required this.slot});

  final String assetPath;
  final Rect slot;

  @override
  Object get _prints => (assetPath, slot);
}

/// Saved handwriting, from the ink's own raster, where its window shows it
/// ([placement]).
final class SheetInk extends SheetMark {
  const SheetInk(super.layer, {required this.key, required this.placement});

  final BrushFrameKey key;
  final SheetInkPlacement placement;

  @override
  Object get _prints => (key, placement);
}

/// Where a window shows its ink surface: the [window] on the paper, the
/// surface's pixels per paper unit ([scale]), and the surface pixel at the
/// window's corner ([origin]) — the ONE mapping between ink pixels and the
/// paper, read by the brush that writes through the window and by every
/// printer that lays the ink back.
///
/// [origin] is zero where a window has a surface of its own (the conte's,
/// the envelope's); the timesheet's two half windows share one band's
/// surface and slice it.
///
/// ⛔One mapping. The input window worked it out for the brush and each
/// printer for itself, and the PDF stretched a cell's whole surface into
/// its band — the handwriting printed five times squeezed while the screen
/// showed it right.
class SheetInkPlacement {
  const SheetInkPlacement({
    required this.window,
    required this.scale,
    this.origin = Offset.zero,
    this.stretch = 1,
  });

  final Rect window;
  final double scale;
  final Offset origin;

  /// How much wider than its surface's own shape the window shows it: 1,
  /// but for a column of the 3-second timesheet, whose columns print wider
  /// than the 6-second sheet's the writing is kept on — the writing stays
  /// on its cells, as wide as they print (유저 2026-09-27,
  /// timesheet-sheet-kind-ink-Q1: 「프레임을 따라 옮겨 붙인다」 · 「g셀만큼
  /// 그린게 3초시트로 늘리면 g셀까지만 보이게」).
  final double stretch;

  /// Where surface pixel [pixel] lands on the paper.
  Offset paperOf(Offset pixel) =>
      window.topLeft +
      Offset(
        (pixel.dx - origin.dx) / scale * stretch,
        (pixel.dy - origin.dy) / scale,
      );

  /// The surface pixel under paper point [paper] — [paperOf] run backwards.
  Offset pixelOf(Offset paper) => Offset(
    (paper.dx - window.left) * scale / stretch + origin.dx,
    (paper.dy - window.top) * scale + origin.dy,
  );

  /// This window at its surface's own shape — as narrow as its surface
  /// slice at the ink's scale, from the same corner: what a brush writing
  /// through it sees before the stretch ([stretch]) is laid on.
  SheetInkPlacement get unstretched => SheetInkPlacement(
    window: Rect.fromLTWH(
      window.left,
      window.top,
      window.width / stretch,
      window.height,
    ),
    scale: scale,
    origin: origin,
  );

  /// Where a raster [width]×[height] of the surface lands on the paper —
  /// at the ink's own scale, the window clipping it; never stretched to
  /// the window, which may show only part of its surface (a conte cell's
  /// band shows the top of a surface the size of the whole body).
  Rect rasterRect(int width, int height) => Rect.fromPoints(
    paperOf(Offset.zero),
    paperOf(Offset(width.toDouble(), height.toDouble())),
  );

  /// The window's slice of its surface, in surface pixels.
  Rect get surfaceRect =>
      origin & Size(window.width * scale / stretch, window.height * scale);

  /// The same window on a page that lies [by] further on — a page in a
  /// stack of pages. The surface and its slice do not move: every mapping
  /// here is measured from the window's corner.
  SheetInkPlacement shiftedBy(Offset by) => SheetInkPlacement(
    window: window.shift(by),
    scale: scale,
    origin: origin,
    stretch: stretch,
  );

  @override
  bool operator ==(Object other) =>
      other is SheetInkPlacement &&
      other.window == window &&
      other.scale == scale &&
      other.origin == origin &&
      other.stretch == stretch;

  @override
  int get hashCode => Object.hash(window, scale, origin, stretch);
}
