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

import 'dart:ui' show Rect;

import 'brush_frame_key.dart';
import 'sheet_paint_layer.dart';

/// One printed mark, in the stratum it belongs to ([SheetPaintLayer]) — the
/// panel bakes the form and the values apart, and a focused test or an
/// export can ask for any subset.
sealed class SheetMark {
  const SheetMark(this.layer);

  final SheetPaintLayer layer;
}

/// A filled rectangle: the paper, a picture's frame, a window's tone.
///
/// Its edges are cut on the device grid (F-179): a sheet never rotates, so
/// every fill is axis-aligned, and an edge cut on the grid is wholly one
/// colour or the other — the paper's own rule, for everything a sheet
/// fills.
///
/// [cornerRadius] rounds its four corners the app's way — a superellipse
/// corner on flat sides (`AppShapes`), the radius one of the app's own
/// (`AppCornerRadii`). Zero is square.
final class SheetFill extends SheetMark {
  const SheetFill(
    super.layer, {
    required this.rect,
    required this.argb,
    this.cornerRadius = 0,
  });

  final Rect rect;
  final int argb;
  final double cornerRadius;
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

  /// Nothing to set, or nowhere to set it: every printer skips these words.
  bool get printsNothing =>
      text.isEmpty || slot.width <= 0 || slot.height <= 0;
}

/// A cell's picture, contained in [slot]. The printer finds the image by
/// ([cutId], [pictureFrame]) — the panel in its thumbnail store, the PDF
/// among the pictures its export rendered.
///
/// Clipped to the slot's corners ([cornerRadius], the window it sits in):
/// a square picture in a rounded window would cover the window's corners.
final class SheetPicture extends SheetMark {
  const SheetPicture(
    super.layer, {
    required this.cutId,
    required this.pictureFrame,
    required this.slot,
    this.cornerRadius = 0,
  });

  final String cutId;
  final int pictureFrame;
  final Rect slot;
  final double cornerRadius;
}

/// A media image — the company logo — contained in [slot].
final class SheetImage extends SheetMark {
  const SheetImage(super.layer, {required this.assetPath, required this.slot});

  final String assetPath;
  final Rect slot;
}

/// Saved handwriting over [rect], from the ink's own raster.
final class SheetInk extends SheetMark {
  const SheetInk(super.layer, {required this.key, required this.rect});

  final BrushFrameKey key;
  final Rect rect;
}

/// Where an ink raster [width]×[height] lands over its [window]: at the
/// ink's own [scale] from the window's corner, the window clipping it — the
/// one placement every sheet printer lays handwriting by.
///
/// ⛔Not stretched to the window: a window may show only part of its
/// surface — a conte cell's surface is the whole body's (a cell that grows
/// over more rows reveals more of the same ink), and its band shows the top
/// of it. Stretched whole into a one-row band, the PDF printed the
/// handwriting five times squeezed.
Rect sheetInkRasterRect(
  Rect window, {
  required int width,
  required int height,
  required double scale,
}) => Rect.fromLTWH(window.left, window.top, width / scale, height / scale);
