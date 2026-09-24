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

  /// Rounded-rect ops (T2, the cell BLOCK chrome): every geometry field
  /// is 24.8 fixed point (pixels * 256 — [q8]) so fractional-zoom cell
  /// rects ride sub-pixel; corner mask bit0=TL, bit1=TR, bit2=BL,
  /// bit3=BR (unset corners square). AA from the rounded-box SDF.
  static const int rrectFill = 5;
  static const int rrectStroke = 6;

  static const int cornerTopLeft = 1;
  static const int cornerTopRight = 2;
  static const int cornerBottomLeft = 4;
  static const int cornerBottomRight = 8;
}

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
    final halfW = w * 0.5;
    final halfH = h * 0.5;
    final centerX = left + halfW;
    final centerY = top + halfH;
    // The field's own pixel window.
    final firstColumn = (left - 1.0).toInt();
    final firstRow = (top - 1.0).toInt();
    final pastColumn = (left + w + 2.0).toInt();
    final pastRow = (top + h + 2.0).toInt();
    int alphaAt(int column, int row) {
      final d = _rrectDistance(
        column + 0.5,
        row + 0.5,
        centerX,
        centerY,
        halfW,
        halfH,
        0,
        0,
        0,
        0,
      );
      final coverage = 0.5 - d;
      if (coverage <= 0.0) {
        return 0;
      }
      return ((coverage > 1.0 ? 1.0 : coverage) * colorA + 0.5).toInt();
    }

    bool inBand(int row) {
      final ry = row + 0.5 - centerY;
      return (ry < 0.0 ? -ry : ry) - halfH <= -0.5;
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

  /// A stroked rounded rect, [thickness] centered on the boundary.
  void rrectStroke(
    double x,
    double y,
    double width,
    double height,
    double radius,
    int cornerMask,
    double thickness,
    int rgba,
  ) {
    _words
      ..add(TimelineGridTileOp.rrectStroke)
      ..add(timelineGridQ8(x))
      ..add(timelineGridQ8(y))
      ..add(timelineGridQ8(width))
      ..add(timelineGridQ8(height))
      ..add(timelineGridQ8(radius))
      ..add(cornerMask)
      ..add(timelineGridQ8(thickness))
      ..add(rgba);
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

void _blendRRect(
  Uint8List pixels,
  int tileWidth,
  int tileHeight, {
  required double x,
  required double y,
  required double w,
  required double h,
  required double radius,
  required int cornerMask,
  required double strokeThickness, // <= 0 = fill
  required int rgba,
}) {
  final colorA = (rgba >> 24) & 0xFF;
  if (colorA == 0 || w <= 0.0 || h <= 0.0) {
    return;
  }
  final halfW = w * 0.5;
  final halfH = h * 0.5;
  final maxRadius = halfW < halfH ? halfW : halfH;
  if (radius > maxRadius) {
    radius = maxRadius;
  }
  final radiusTl = (cornerMask & 1) != 0 ? radius : 0.0;
  final radiusTr = (cornerMask & 2) != 0 ? radius : 0.0;
  final radiusBl = (cornerMask & 4) != 0 ? radius : 0.0;
  final radiusBr = (cornerMask & 8) != 0 ? radius : 0.0;
  final centerX = x + halfW;
  final centerY = y + halfH;
  final reach = strokeThickness > 0.0 ? strokeThickness * 0.5 : 0.0;

  var left = (x - reach - 1.0).toInt();
  var top = (y - reach - 1.0).toInt();
  var right = (x + w + reach + 2.0).toInt();
  var bottom = (y + h + reach + 2.0).toInt();
  if (left < 0) {
    left = 0;
  }
  if (top < 0) {
    top = 0;
  }
  if (right > tileWidth) {
    right = tileWidth;
  }
  if (bottom > tileHeight) {
    bottom = tileHeight;
  }

  final r = rgba & 0xFF;
  final g = (rgba >> 8) & 0xFF;
  final b = (rgba >> 16) & 0xFF;
  for (var py = top; py < bottom; py += 1) {
    for (var px = left; px < right; px += 1) {
      final d = _rrectDistance(
        px + 0.5,
        py + 0.5,
        centerX,
        centerY,
        halfW,
        halfH,
        radiusTl,
        radiusTr,
        radiusBl,
        radiusBr,
      );
      double coverage;
      if (strokeThickness > 0.0) {
        final ad = d < 0.0 ? -d : d;
        coverage = 0.5 - (ad - reach);
      } else {
        coverage = 0.5 - d;
      }
      if (coverage > 0.0) {
        if (coverage > 1.0) {
          coverage = 1.0;
        }
        final a = (coverage * colorA + 0.5).toInt();
        _blendSpan(pixels, (py * tileWidth + px) * 4, 1, r, g, b, a);
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
        _blendRRect(
          pixels,
          tileWidth,
          tileHeight,
          x: ops[cursor + 1] / 256.0,
          y: ops[cursor + 2] / 256.0,
          w: ops[cursor + 3] / 256.0,
          h: ops[cursor + 4] / 256.0,
          radius: ops[cursor + 5] / 256.0,
          cornerMask: ops[cursor + 6],
          strokeThickness: 0.0,
          rgba: ops[cursor + 7],
        );
        cursor += 8;
      case TimelineGridTileOp.rrectStroke:
        if (cursor + 9 > ops.length) {
          return -2;
        }
        _blendRRect(
          pixels,
          tileWidth,
          tileHeight,
          x: ops[cursor + 1] / 256.0,
          y: ops[cursor + 2] / 256.0,
          w: ops[cursor + 3] / 256.0,
          h: ops[cursor + 4] / 256.0,
          radius: ops[cursor + 5] / 256.0,
          cornerMask: ops[cursor + 6],
          strokeThickness: ops[cursor + 7] / 256.0,
          rgba: ops[cursor + 8],
        );
        cursor += 9;
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
