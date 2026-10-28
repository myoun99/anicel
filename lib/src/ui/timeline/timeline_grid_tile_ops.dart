import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import '../../core/argb_channels.dart';

/// The grid-tile op stream (UI-R18 O7 / R18-T T1): the timeline frame
/// grids describe a tile's contents as a flat int32 word list — flat
/// rect fills, hairlines and A8-atlas glyph blits, which is the WHOLE
/// post-O1 cell visual language — and the native `qa_grid_raster_tile`
/// rasterizes it off the UI thread. [timelineGridRasterTileReference]
/// is the Dart source of truth for the semantics (the engine's
/// load-fallback discipline): byte parity between the two is pinned by
/// tests, so the native path can never silently diverge.
///
/// OP colors pack as memory-order RGBA words (r | g<<8 | b<<16 | a<<24),
/// STRAIGHT alpha; rasterization is byte-rounded integer source-over
/// (the fill-compose arithmetic). The background word is written
/// VERBATIM — pass 0 for a fully transparent tile: accumulating
/// source-over from transparent black produces PREMULTIPLIED bytes,
/// which is the raw-image upload's contract (the fill overlay's
/// premultiply precedent), so tiles composite pixel-true over any panel
/// background.
abstract final class TimelineGridTileOp {
  static const int fillRect = 1;
  static const int hline = 2;
  static const int vline = 3;
  static const int glyph = 4;

  /// The rounded-rect fill (T2, the cell BLOCK chrome): every geometry field
  /// is 24.8 fixed point (pixels * 256 — [q8]) so fractional-zoom cell
  /// rects ride sub-pixel; corner mask bit0=TL, bit1=TR, bit2=BL,
  /// bit3=BR (unset corners square). AA from the rounded-box SDF.
  static const int rrectFill = 5;

  /// The rounded-rect RING (I-129, 2026-10-25: an EMPTY block's outline —
  /// the export Cels tab's hollow block, on the timeline's blocks): the
  /// [rrectFill] coverage of the box less that of the box a line width in
  /// from each side, its corners that much tighter. Its open mask names
  /// the sides it leaves OPEN ([sideLeft]…): a block a tile's span cuts
  /// runs on into the next tile, which must not see a seam there.
  ///
  /// ↩️6 was the per-cell block border's STROKE once: D32/D38 (2026-08-18)
  /// made that border transparent for good, and the op left the writer,
  /// the reference and the engine together with the substrate rewrite of
  /// 2026-09-24.
  static const int rrectRing = 6;

  static const int cornerTopLeft = 1;
  static const int cornerTopRight = 2;
  static const int cornerBottomLeft = 4;
  static const int cornerBottomRight = 8;

  static const int sideLeft = 1;
  static const int sideTop = 2;
  static const int sideRight = 4;
  static const int sideBottom = 8;
}

/// A rounded rect in PIXELS as the op stream states it: [cornerMask] picks
/// which corners take [radius] (bit0=TL, bit1=TR, bit2=BL, bit3=BR).
typedef TimelineGridRRect = ({
  double x,
  double y,
  double width,
  double height,
  double radius,
  int cornerMask,
});

/// Pixels → the op stream's 24.8 fixed-point word.
int timelineGridQ8(double pixels) => (pixels * 256).round();

/// Packs a straight-alpha color into the op stream's RGBA word.
int timelineGridPackRgba(Color color) {
  final argb = color.toARGB32();
  return argbRed(argb) |
      (argbGreen(argb) << 8) |
      (argbBlue(argb) << 16) |
      (argbAlpha(argb) << 24);
}

/// Grow-only builder for one tile's op stream.
class TimelineGridTileOpWriter {
  final List<int> _words = <int>[];

  int get wordCount => _words.length;

  void fillRect(int x, int y, int width, int height, int rgba) {
    _words
      ..add(TimelineGridTileOp.fillRect)
      ..add(x)
      ..add(y)
      ..add(width)
      ..add(height)
      ..add(rgba);
  }

  /// A horizontal line [length] long, [thickness] tall.
  void hline(int x, int y, int length, int thickness, int rgba) {
    _words
      ..add(TimelineGridTileOp.hline)
      ..add(x)
      ..add(y)
      ..add(length)
      ..add(thickness)
      ..add(rgba);
  }

  /// A vertical line [length] tall, [thickness] wide.
  void vline(int x, int y, int length, int thickness, int rgba) {
    _words
      ..add(TimelineGridTileOp.vline)
      ..add(x)
      ..add(y)
      ..add(length)
      ..add(thickness)
      ..add(rgba);
  }

  /// A filled rounded rect; geometry in PIXELS (converted to q8 here),
  /// [cornerMask] picks which corners round.
  void rrectFill(
    double x,
    double y,
    double width,
    double height,
    double radius,
    int cornerMask,
    int rgba,
  ) {
    _words
      ..add(TimelineGridTileOp.rrectFill)
      ..add(timelineGridQ8(x))
      ..add(timelineGridQ8(y))
      ..add(timelineGridQ8(width))
      ..add(timelineGridQ8(height))
      ..add(timelineGridQ8(radius))
      ..add(cornerMask)
      ..add(rgba);
  }

  /// [box]'s ring [lineWidth] wide inside it (converted to q8 here),
  /// leaving open the sides [openMask] names
  /// ([TimelineGridTileOp.rrectRing]).
  void rrectRing(
    TimelineGridRRect box, {
    required double lineWidth,
    required int openMask,
    required int rgba,
  }) {
    _words
      ..add(TimelineGridTileOp.rrectRing)
      ..add(timelineGridQ8(box.x))
      ..add(timelineGridQ8(box.y))
      ..add(timelineGridQ8(box.width))
      ..add(timelineGridQ8(box.height))
      ..add(timelineGridQ8(box.radius))
      ..add(box.cornerMask)
      ..add(timelineGridQ8(lineWidth))
      ..add(openMask)
      ..add(rgba);
  }

  /// An axis-aligned box, antialiased EXACTLY as [rrectFill] with no radius
  /// would draw it — byte for byte — but written as plain rect fills.
  ///
  /// ⚡[rrectFill] evaluates its distance field, square root and all, at
  /// every pixel of the box and a margin round it. A box's field has a
  /// shape to spend: every row whose centre lies half a pixel or more
  /// inside the box sees the same coverage in each column, so the band of
  /// those rows is one fill per run of equal columns, and only the rows at
  /// the two edges are asked pixel by pixel. The coverage itself is the
  /// field's own ([_rrectDistance]), so the bytes cannot drift from it.
  void boxFill(double x, double y, double width, double height, int rgba) {
    final colorA = (rgba >> 24) & 0xFF;
    // Quantized exactly as [rrectFill] quantizes.
    final left = timelineGridQ8(x) / 256.0;
    final top = timelineGridQ8(y) / 256.0;
    final w = timelineGridQ8(width) / 256.0;
    final h = timelineGridQ8(height) / 256.0;
    if (colorA == 0 || w <= 0.0 || h <= 0.0) {
      return;
    }
    final field = _rrectFieldOf((
      x: left,
      y: top,
      width: w,
      height: h,
      radius: 0,
      cornerMask: 0,
    ));
    // The field's own pixel window.
    final firstColumn = (left - 1.0).toInt();
    final firstRow = (top - 1.0).toInt();
    final pastColumn = (left + w + 2.0).toInt();
    final pastRow = (top + h + 2.0).toInt();
    int alphaAt(int column, int row) {
      final coverage = _coverageOf(field, column + 0.5, row + 0.5);
      return coverage > 0.0 ? (coverage * colorA + 0.5).toInt() : 0;
    }

    bool inBand(int row) {
      final ry = row + 0.5 - field.centerY;
      return (ry < 0.0 ? -ry : ry) - field.halfH <= -0.5;
    }

    // One fill per run of equal columns in [row] (a band of [rows] rows).
    void runsOf(int row, int rows) {
      var column = firstColumn;
      while (column < pastColumn) {
        final alpha = alphaAt(column, row);
        var end = column + 1;
        while (end < pastColumn && alphaAt(end, row) == alpha) {
          end += 1;
        }
        if (alpha > 0) {
          fillRect(
            column,
            row,
            end - column,
            rows,
            (rgba & 0x00FFFFFF) | (alpha << 24),
          );
        }
        column = end;
      }
    }

    var row = firstRow;
    while (row < pastRow) {
      if (!inBand(row)) {
        runsOf(row, 1);
        row += 1;
        continue;
      }
      var end = row + 1;
      while (end < pastRow && inBand(end)) {
        end += 1;
      }
      runsOf(row, end - row);
      row = end;
    }
  }

  /// A filled rounded rect whose corners sit at the two ENDS of a run — a
  /// block's paper, its ends along x ([alongX]) or along y — drawn exactly
  /// as [rrectFill] draws it, byte for byte, with the field paid for where
  /// a corner can reach and nowhere else.
  ///
  /// ⚡Each end is an [rrectFill] cut at the first whole pixel two radii
  /// in; the stretch between is a [boxFill]. Why that is the SAME picture:
  /// the field picks a pixel's corner by the quadrant of the box it lies
  /// in, and a corner's arc reaches one radius in from its end — so an end
  /// piece two radii long holds the whole arc inside its own end half,
  /// where it computes the arc exactly as the whole box does (every value
  /// is a 24.8 word, so the arithmetic is exact). Everywhere else both see
  /// a square box, and a whole-pixel cut leaves each column wholly inside
  /// one piece. Too short to hold both ends and a pixel between, it is one
  /// [rrectFill].
  void runFill(
    double x,
    double y,
    double width,
    double height,
    double radius,
    int cornerMask,
    int rgba, {
    required bool alongX,
  }) {
    if (timelineGridQ8(radius) <= 0 || cornerMask == 0) {
      boxFill(x, y, width, height, rgba);
      return;
    }
    final startCorners = alongX
        ? TimelineGridTileOp.cornerTopLeft | TimelineGridTileOp.cornerBottomLeft
        : TimelineGridTileOp.cornerTopLeft | TimelineGridTileOp.cornerTopRight;
    final endCorners =
        (TimelineGridTileOp.cornerTopLeft |
            TimelineGridTileOp.cornerTopRight |
            TimelineGridTileOp.cornerBottomLeft |
            TimelineGridTileOp.cornerBottomRight) &
        ~startCorners;
    // In the stream's own 24.8 words, so the pieces' edges are the whole
    // box's edges exactly and each cut is a whole pixel.
    final start = timelineGridQ8(alongX ? x : y);
    final end = start + timelineGridQ8(alongX ? width : height);
    final reach = 2 * timelineGridQ8(radius);
    final middleStart = (cornerMask & startCorners) == 0
        ? start
        : -((-(start + reach) >> 8) << 8);
    final middleEnd = (cornerMask & endCorners) == 0
        ? end
        : ((end - reach) >> 8) << 8;
    if (middleEnd - middleStart < 256) {
      rrectFill(x, y, width, height, radius, cornerMask, rgba);
      return;
    }
    void piece(int from, int to, int corners, {required bool box}) {
      final along = from / 256.0;
      final length = (to - from) / 256.0;
      final px = alongX ? along : x;
      final py = alongX ? y : along;
      final pw = alongX ? length : width;
      final ph = alongX ? height : length;
      if (box) {
        boxFill(px, py, pw, ph, rgba);
      } else {
        rrectFill(px, py, pw, ph, radius, corners, rgba);
      }
    }

    if (middleStart > start) {
      piece(start, middleStart, cornerMask & startCorners, box: false);
    }
    piece(middleStart, middleEnd, 0, box: true);
    if (middleEnd < end) {
      piece(middleEnd, end, cornerMask & endCorners, box: false);
    }
  }

  /// Blits a [width]x[height] window of the A8 atlas at (atlasX, atlasY)
  /// to (destX, destY), tinted by [rgba] (atlas coverage scales its
  /// alpha).
  void glyph(
    int destX,
    int destY,
    int atlasX,
    int atlasY,
    int width,
    int height,
    int rgba,
  ) {
    _words
      ..add(TimelineGridTileOp.glyph)
      ..add(destX)
      ..add(destY)
      ..add(atlasX)
      ..add(atlasY)
      ..add(width)
      ..add(height)
      ..add(rgba);
  }

  /// The ops another writer built, written on after these.
  void append(Int32List ops) => _words.addAll(ops);

  Int32List build() => Int32List.fromList(_words);
}

void _blendSpan(
  Uint8List pixels,
  int offset,
  int count,
  int r,
  int g,
  int b,
  int a,
) {
  if (a >= 255) {
    for (var i = 0; i < count; i += 1) {
      final base = offset + i * 4;
      pixels[base] = r;
      pixels[base + 1] = g;
      pixels[base + 2] = b;
      pixels[base + 3] = 255;
    }
    return;
  }
  final inv = 255 - a;
  for (var i = 0; i < count; i += 1) {
    final base = offset + i * 4;
    pixels[base] = (r * a + pixels[base] * inv + 127) ~/ 255;
    pixels[base + 1] = (g * a + pixels[base + 1] * inv + 127) ~/ 255;
    pixels[base + 2] = (b * a + pixels[base + 2] * inv + 127) ~/ 255;
    pixels[base + 3] = 255 - ((255 - pixels[base + 3]) * inv + 127) ~/ 255;
  }
}

/// The rounded-box SDF with per-corner radii — the C
/// `qa_grid_rrect_distance` verbatim (double math on both sides keeps
/// the bytes identical; +,-,*,/,sqrt are IEEE correctly rounded).
double _rrectDistance(
  double cx,
  double cy,
  double centerX,
  double centerY,
  double halfW,
  double halfH,
  double radiusTl,
  double radiusTr,
  double radiusBl,
  double radiusBr,
) {
  final rx = cx - centerX;
  final ry = cy - centerY;
  final double r;
  if (rx < 0.0) {
    r = ry < 0.0 ? radiusTl : radiusBl;
  } else {
    r = ry < 0.0 ? radiusTr : radiusBr;
  }
  final ax = (rx < 0.0 ? -rx : rx) - (halfW - r);
  final ay = (ry < 0.0 ? -ry : ry) - (halfH - r);
  final mx = ax > 0.0 ? ax : 0.0;
  final my = ay > 0.0 ? ay : 0.0;
  final outside = math.sqrt(mx * mx + my * my);
  final insideAxis = ax > ay ? ax : ay;
  final inside = insideAxis < 0.0 ? insideAxis : 0.0;
  return outside + inside - r;
}

/// A rounded box's coverage field — the C `qa_grid_rrect_field`: the box,
/// its centre and halves, and each corner's radius (0 = square).
typedef _RRectField = ({
  double left,
  double top,
  double width,
  double height,
  double centerX,
  double centerY,
  double halfW,
  double halfH,
  double radiusTl,
  double radiusTr,
  double radiusBl,
  double radiusBr,
});

/// [box]'s field, its radius held to what the box can hold — the C
/// `qa_grid_rrect_field_of`.
_RRectField _rrectFieldOf(TimelineGridRRect box) {
  final halfW = box.width * 0.5;
  final halfH = box.height * 0.5;
  final maxRadius = halfW < halfH ? halfW : halfH;
  final radius = box.radius > maxRadius ? maxRadius : box.radius;
  final mask = box.cornerMask;
  return (
    left: box.x,
    top: box.y,
    width: box.width,
    height: box.height,
    centerX: box.x + halfW,
    centerY: box.y + halfH,
    halfW: halfW,
    halfH: halfH,
    radiusTl: (mask & 1) != 0 ? radius : 0.0,
    radiusTr: (mask & 2) != 0 ? radius : 0.0,
    radiusBl: (mask & 4) != 0 ? radius : 0.0,
    radiusBr: (mask & 8) != 0 ? radius : 0.0,
  );
}

/// The box an [TimelineGridTileOp.rrectFill] or
/// [TimelineGridTileOp.rrectRing] op at [at] states — the C
/// `qa_grid_rrect_field_at`.
TimelineGridRRect _rrectAt(Int32List ops, int at) => (
  x: ops[at + 1] / 256.0,
  y: ops[at + 2] / 256.0,
  width: ops[at + 3] / 256.0,
  height: ops[at + 4] / 256.0,
  radius: ops[at + 5] / 256.0,
  cornerMask: ops[at + 6],
);

/// A ring's inner corner: its outer corner [line] tighter, never below
/// square nor past what the inner box can hold — the C
/// `qa_grid_ring_inner_radius`.
double _ringInnerRadius(double outer, double line, double maxRadius) {
  var radius = outer - line;
  if (radius < 0.0) {
    radius = 0.0;
  }
  return radius > maxRadius ? maxRadius : radius;
}

/// The box a ring of [box] leaves unpainted: [line] in from each side it
/// strokes and [line] + 2 past each side [openMask] leaves open, its
/// corners [line] tighter — the C `qa_grid_ring_inner_field`.
_RRectField _ringHoleOf(_RRectField box, double line, int openMask) {
  final past = line + 2.0;
  final left = box.left + ((openMask & 1) != 0 ? -past : line);
  final top = box.top + ((openMask & 2) != 0 ? -past : line);
  final right = box.left + box.width - ((openMask & 4) != 0 ? -past : line);
  final bottom = box.top + box.height - ((openMask & 8) != 0 ? -past : line);
  final width = right - left;
  final height = bottom - top;
  final halfW = width * 0.5;
  final halfH = height * 0.5;
  final maxRadius = halfW < halfH ? halfW : halfH;
  return (
    left: left,
    top: top,
    width: width,
    height: height,
    centerX: left + halfW,
    centerY: top + halfH,
    halfW: halfW,
    halfH: halfH,
    radiusTl: _ringInnerRadius(box.radiusTl, line, maxRadius),
    radiusTr: _ringInnerRadius(box.radiusTr, line, maxRadius),
    radiusBl: _ringInnerRadius(box.radiusBl, line, maxRadius),
    radiusBr: _ringInnerRadius(box.radiusBr, line, maxRadius),
  );
}

/// How much of the pixel centred at ([cx], [cy]) [field] covers:
/// analytic-AA 0.5 - d from the rounded-box SDF, held to [0, 1] — the C
/// `qa_grid_rrect_coverage`.
double _coverageOf(_RRectField field, double cx, double cy) {
  final coverage =
      0.5 -
      _rrectDistance(
        cx,
        cy,
        field.centerX,
        field.centerY,
        field.halfW,
        field.halfH,
        field.radiusTl,
        field.radiusTr,
        field.radiusBl,
        field.radiusBr,
      );
  return coverage <= 0.0
      ? 0.0
      : coverage > 1.0
      ? 1.0
      : coverage;
}

/// The tile the reference rasters into.
typedef _Tile = ({Uint8List pixels, int width, int height});

/// The [TimelineGridTileOp.rrectFill] and [TimelineGridTileOp.rrectRing]
/// raster loop — the C `qa_grid_blend_rrect_band`: [box]'s coverage less
/// [hole]'s (null for none), blended source-over per pixel.
void _blendRRectBand(
  _Tile tile,
  _RRectField box, {
  _RRectField? hole,
  required int rgba,
}) {
  final colorA = (rgba >> 24) & 0xFF;
  if (colorA == 0 || box.width <= 0.0 || box.height <= 0.0) {
    return;
  }
  final inner = hole != null && hole.halfW > 0.0 && hole.halfH > 0.0
      ? hole
      : null;
  final left = math.max((box.left - 1.0).toInt(), 0);
  final top = math.max((box.top - 1.0).toInt(), 0);
  final right = math.min((box.left + box.width + 2.0).toInt(), tile.width);
  final bottom = math.min((box.top + box.height + 2.0).toInt(), tile.height);

  final r = rgba & 0xFF;
  final g = (rgba >> 8) & 0xFF;
  final b = (rgba >> 16) & 0xFF;
  for (var py = top; py < bottom; py += 1) {
    for (var px = left; px < right; px += 1) {
      var coverage = _coverageOf(box, px + 0.5, py + 0.5);
      if (coverage > 0.0 && inner != null) {
        coverage -= _coverageOf(inner, px + 0.5, py + 0.5);
      }
      if (coverage > 0.0) {
        final a = (coverage * colorA + 0.5).toInt();
        _blendSpan(tile.pixels, (py * tile.width + px) * 4, 1, r, g, b, a);
      }
    }
  }
}

void _blendRect(
  Uint8List pixels,
  int tileWidth,
  int tileHeight,
  int x,
  int y,
  int w,
  int h,
  int rgba,
) {
  final a = (rgba >> 24) & 0xFF;
  if (a == 0 || w <= 0 || h <= 0) {
    return;
  }
  final left = x < 0 ? 0 : x;
  final top = y < 0 ? 0 : y;
  var right = x + w;
  var bottom = y + h;
  if (right > tileWidth) {
    right = tileWidth;
  }
  if (bottom > tileHeight) {
    bottom = tileHeight;
  }
  if (left >= right || top >= bottom) {
    return;
  }
  final r = rgba & 0xFF;
  final g = (rgba >> 8) & 0xFF;
  final b = (rgba >> 16) & 0xFF;
  for (var row = top; row < bottom; row += 1) {
    _blendSpan(pixels, (row * tileWidth + left) * 4, right - left, r, g, b, a);
  }
}

/// The Dart REFERENCE of `qa_grid_raster_tile` — the source of truth for
/// the semantics, byte-identical to the native rasterizer (pinned by the
/// parity suite). Returns 0 on success, negative on a malformed stream
/// (the native error contract).
int timelineGridRasterTileReference({
  required Uint8List pixels,
  required int tileWidth,
  required int tileHeight,
  required int backgroundRgba,
  Int32List? ops,
  Uint8List? atlas,
  int atlasWidth = 0,
  int atlasHeight = 0,
}) {
  if (tileWidth <= 0 || tileHeight <= 0) {
    return -1;
  }
  // Background fill VERBATIM (T2: 0 = fully transparent — source-over
  // accumulation from transparent black yields PREMULTIPLIED bytes, the
  // image upload's contract).
  final bgR = backgroundRgba & 0xFF;
  final bgG = (backgroundRgba >> 8) & 0xFF;
  final bgB = (backgroundRgba >> 16) & 0xFF;
  final bgA = (backgroundRgba >> 24) & 0xFF;
  for (var i = 0; i < tileWidth * tileHeight; i += 1) {
    final base = i * 4;
    pixels[base] = bgR;
    pixels[base + 1] = bgG;
    pixels[base + 2] = bgB;
    pixels[base + 3] = bgA;
  }
  if (ops == null || ops.isEmpty) {
    return 0;
  }

  final tile = (pixels: pixels, width: tileWidth, height: tileHeight);
  var cursor = 0;
  while (cursor < ops.length) {
    switch (ops[cursor]) {
      case TimelineGridTileOp.fillRect:
      case TimelineGridTileOp.hline:
        if (cursor + 6 > ops.length) {
          return -2;
        }
        _blendRect(
          pixels,
          tileWidth,
          tileHeight,
          ops[cursor + 1],
          ops[cursor + 2],
          ops[cursor + 3],
          ops[cursor + 4],
          ops[cursor + 5],
        );
        cursor += 6;
      case TimelineGridTileOp.vline:
        if (cursor + 6 > ops.length) {
          return -2;
        }
        // length runs down, thickness across.
        _blendRect(
          pixels,
          tileWidth,
          tileHeight,
          ops[cursor + 1],
          ops[cursor + 2],
          ops[cursor + 4],
          ops[cursor + 3],
          ops[cursor + 5],
        );
        cursor += 6;
      case TimelineGridTileOp.rrectFill:
        if (cursor + 8 > ops.length) {
          return -2;
        }
        _blendRRectBand(
          tile,
          _rrectFieldOf(_rrectAt(ops, cursor)),
          rgba: ops[cursor + 7],
        );
        cursor += 8;
      case TimelineGridTileOp.rrectRing:
        if (cursor + 10 > ops.length) {
          return -2;
        }
        final line = ops[cursor + 7] / 256.0;
        if (line > 0.0) {
          final box = _rrectFieldOf(_rrectAt(ops, cursor));
          _blendRRectBand(
            tile,
            box,
            hole: _ringHoleOf(box, line, ops[cursor + 8]),
            rgba: ops[cursor + 9],
          );
        }
        cursor += 10;
      case TimelineGridTileOp.glyph:
        if (cursor + 8 > ops.length) {
          return -2;
        }
        if (atlas == null) {
          return -3;
        }
        final destX = ops[cursor + 1];
        final destY = ops[cursor + 2];
        final atlasX = ops[cursor + 3];
        final atlasY = ops[cursor + 4];
        final w = ops[cursor + 5];
        final h = ops[cursor + 6];
        final rgba = ops[cursor + 7];
        final colorA = (rgba >> 24) & 0xFF;
        final r = rgba & 0xFF;
        final g = (rgba >> 8) & 0xFF;
        final b = (rgba >> 16) & 0xFF;
        for (var row = 0; row < h; row += 1) {
          final ty = destY + row;
          final ay = atlasY + row;
          if (ty < 0 || ty >= tileHeight || ay < 0 || ay >= atlasHeight) {
            continue;
          }
          for (var col = 0; col < w; col += 1) {
            final tx = destX + col;
            final ax = atlasX + col;
            if (tx < 0 || tx >= tileWidth || ax < 0 || ax >= atlasWidth) {
              continue;
            }
            final coverage = atlas[ay * atlasWidth + ax];
            if (coverage == 0 || colorA == 0) {
              continue;
            }
            final a = (colorA * coverage + 127) ~/ 255;
            _blendSpan(pixels, (ty * tileWidth + tx) * 4, 1, r, g, b, a);
          }
        }
        cursor += 8;
      default:
        return -4;
    }
  }
  return 0;
}
