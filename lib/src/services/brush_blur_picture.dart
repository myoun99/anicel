import 'dart:math' as math;
import 'dart:typed_data';

import '../core/floor_math.dart';
import '../models/bitmap_surface.dart';
import '../models/brush_dab.dart';
import '../models/dirty_region.dart';
import '../models/pasteboard_bounds.dart';
import '../models/tile_coord.dart';
import 'brush_dab_kernel.dart';

/// 🗣️I-75 흐리기 — THE CEL A BLUR STROKE WORKS ON, and the one law every
/// route that lays a blur stroke runs: the live display, the pen-up landing
/// and the stroke re-derived from its dabs (the commit after the cel moved,
/// 확정 on another cel) all reach it through the one
/// `BrushLiveStrokeRasterizer` that holds it.
///
/// ⛔NOT THE PAINT LAW. A painting stroke piles its dabs on an EMPTY buffer
/// and composites it once (`brushCommitResultForBrushDabSequenceOnBitmapSurface`).
/// A blur has nothing to pile: 유저 Q4 「문지를수록 더 흐려짐」 asks every dab to
/// read the picture the dabs before it left. So the stroke holds a COPY of
/// the cel where it has been, and each dab rewrites it in place:
///
///     picture ← picture + (blurred(picture) − picture) × laid
///
/// - `laid` is what the dab would have laid as paint onto nothing — its
///   flow, pressure, hardness, texture and spacing share — MEASURED by
///   running the dab kernel ([blendDabTilesDart]) on an empty scratch, so a
///   blur brush answers every brush setting the way a paint brush does with
///   no second copy of the coverage law (Q3: no slider of its own).
/// - `blurred` is the picture smoothed at a radius the brush's size sets
///   (Q3, [blurRadiusOf]) — three box passes along each axis, the usual
///   stand-in for a Gaussian, so one tap leaves a round mark rather than a
///   square one. All three along the rows first, then all three along the
///   columns: that order is part of the law (each pass rounds).
/// - PREMULTIPLIED, so a transparent pixel carries no colour into its
///   neighbours: a line blurred over nothing fades, it does not darken.
/// - Integers throughout (16-bit planes, means rounded half up, moves
///   rounded half away from zero), so a C transcription can match it byte
///   for byte (I-75 round ⓑ).
///
/// The tool's OPACITY and the SELECTION are not here: they cap how far the
/// finished picture may move from the cel ([resultTile]'s mask), exactly as
/// they cap a paint stroke's accumulated buffer.
class BrushBlurPicture {
  BrushBlurPicture({required this.base, required this.wall})
    : tileSize = base.tileSize;

  /// The cel as the stroke found it — what every pixel the stroke has not
  /// rewritten still reads.
  final BitmapSurface base;
  final PasteboardWall wall;
  final int tileSize;

  /// The rewritten tiles: premultiplied RGBA at 16 bits (alpha × 257, a
  /// channel × alpha × 257 / 255), each complete — made from [base] whole
  /// the first time a dab writes into it.
  final Map<TileCoord, Uint16List> _tiles = {};

  /// The empty planes a dab's paint coverage is measured on, cleared after
  /// every dab.
  final Map<(int, int), BrushDabTileBuffers> _scratch = {};

  /// What a dab's blur passes through. ⚠️Their size is what a blur dab
  /// costs in memory beyond the picture itself: the rows' passes keep the
  /// dab's columns over every row the blur reads ([_across]: the dab's width
  /// × twice its size, 8 bytes a pixel — 16 × size² bytes, 64MB at the
  /// 2000px ceiling, 160KB at 100px); the rest is a row and a column.
  /// Grown, never shrunk, for the stroke.
  Uint16List _across = Uint16List(0);
  Uint16List _lineA = Uint16List(0);
  Uint16List _lineB = Uint16List(0);

  /// The scratch's own tile edge — smaller than the cel's, so measuring a
  /// dab's coverage holds little more than the dab.
  static const int _scratchTileSize = 64;

  /// Past this many scratch tiles the scratch is let go whole: a long
  /// stroke visits ever new tiles, and an empty one costs only its zeroing.
  static const int _scratchTileLimit = 64;

  /// The radius of each box pass for [dab]: a sixth of its size, so the
  /// blur's reach (3r) is the dab's own radius and its spread
  /// (σ ≈ √(r(r+1))) a third of it — the brush's own size sets how far it
  /// smears (I-75 설계: 「흐림 반경 = 붓 반지름」), and a dab smears what lies
  /// under it rather than pulling colour in from beyond its edge.
  static int blurRadiusOf(BrushDab dab) => math.max(1, (dab.size / 6).round());

  /// Blurs the picture under [dab] by what it would have laid as paint.
  /// Returns the rectangle it rewrote, or null when no pixel moved.
  DirtyRegion? blurDab(BrushDab dab) {
    final plan = BrushDabPlan.of(
      // The colour is not this dab's to lay; opaque, so what it measures is
      // its coverage alone.
      dab.copyWith(color: 0xFFFFFFFF, erase: false),
      wall: wall,
      tileSize: _scratchTileSize,
      erase: false,
    );
    if (plan == null) {
      return null;
    }
    final laid = _measureLaid(plan);
    final left = plan.left;
    final top = plan.top;
    final width = plan.rightExclusive - left;
    final height = plan.bottomExclusive - top;
    final radius = blurRadiusOf(dab);
    final reach = radius * 3;
    final wide = width + reach * 2;
    final tall = height + reach * 2;
    _ensureRoom(width: width, wide: wide, tall: tall);

    // Along the rows: every row the blur reads, three passes, the dab's
    // columns kept.
    final rowValues = width * 4;
    for (var row = 0; row < tall; row += 1) {
      _gatherRow(_lineA, left - reach, top - reach + row, wide);
      _box(_lineA, _lineB, radius, wide - radius, radius);
      _box(_lineB, _lineA, radius * 2, wide - radius * 2, radius);
      _box(_lineA, _lineB, reach, wide - reach, radius);
      _across.setRange(
        row * rowValues,
        (row + 1) * rowValues,
        _lineB,
        reach * 4,
      );
    }

    // Along the columns: three passes over each of the dab's columns, and
    // its pixels moved toward what they leave.
    var moved = false;
    for (var column = 0; column < width; column += 1) {
      for (var row = 0; row < tall; row += 1) {
        final from = row * rowValues + column * 4;
        final to = row * 4;
        _lineA[to] = _across[from];
        _lineA[to + 1] = _across[from + 1];
        _lineA[to + 2] = _across[from + 2];
        _lineA[to + 3] = _across[from + 3];
      }
      _box(_lineA, _lineB, radius, tall - radius, radius);
      _box(_lineB, _lineA, radius * 2, tall - radius * 2, radius);
      _box(_lineA, _lineB, reach, tall - reach, radius);
      if (_moveColumn(
        blurred: _lineB,
        blurredStart: reach,
        laid: laid,
        laidStride: width,
        column: column,
        x: left + column,
        top: top,
        height: height,
      )) {
        moved = true;
      }
    }
    return moved
        ? DirtyRegion(
            left: left,
            top: top,
            rightExclusive: plan.rightExclusive,
            bottomExclusive: plan.bottomExclusive,
          )
        : null;
  }

  void _ensureRoom({required int width, required int wide, required int tall}) {
    final across = width * tall * 4;
    if (_across.length < across) {
      _across = Uint16List(across);
    }
    final line = math.max(wide, tall) * 4;
    if (_lineA.length < line) {
      _lineA = Uint16List(line);
      _lineB = Uint16List(line);
    }
  }

  /// What the dab of [plan] lays onto nothing, per pixel of its rectangle,
  /// as alpha × 65535 — read off the kernel's own 16-bit plane.
  Uint16List _measureLaid(BrushDabPlan plan) {
    if (_scratch.length > _scratchTileLimit) {
      _scratch.clear();
    }
    blendDabTilesDart(
      plan,
      tileSize: _scratchTileSize,
      bufferFor: (tileX, tileY) => _scratch.putIfAbsent(
        (tileX, tileY),
        () => (
          bytes: Uint8List(_scratchTileSize * _scratchTileSize * 4),
          wide: Uint16List(_scratchTileSize * _scratchTileSize * 4),
        ),
      ),
    );
    final left = plan.left;
    final width = plan.rightExclusive - left;
    final laid = Uint16List(width * (plan.bottomExclusive - plan.top));
    for (var y = plan.top; y < plan.bottomExclusive; y += 1) {
      final tileY = floorDiv(y, _scratchTileSize);
      final rowOffset = (y - tileY * _scratchTileSize) * _scratchTileSize;
      final laidRow = (y - plan.top) * width;
      for (var tileX = plan.tileXStart; tileX <= plan.tileXEnd; tileX += 1) {
        final planes = _scratch[(tileX, tileY)];
        if (planes == null) {
          continue; // The kernel never came here: nothing laid.
        }
        final tileLeft = tileX * _scratchTileSize;
        final spanStart = math.max(left, tileLeft);
        final spanEnd = math.min(
          plan.rightExclusive,
          tileLeft + _scratchTileSize,
        );
        final wide = planes.wide;
        for (var x = spanStart; x < spanEnd; x += 1) {
          laid[laidRow + x - left] = wide[(rowOffset + x - tileLeft) * 4 + 3];
        }
        final from = (rowOffset + spanStart - tileLeft) * 4;
        final to = (rowOffset + spanEnd - tileLeft) * 4;
        wide.fillRange(from, to, 0);
        planes.bytes.fillRange(from, to, 0);
      }
    }
    return laid;
  }

  /// The picture as it stands along row [y] from [x0], [count] pixels,
  /// premultiplied 16-bit: a rewritten tile's own values, the cel's
  /// elsewhere, nothing where the cel has no tile.
  void _gatherRow(Uint16List into, int x0, int y, int count) {
    final tileY = floorDiv(y, tileSize);
    final rowOffset = (y - tileY * tileSize) * tileSize;
    final xEnd = x0 + count;
    var x = x0;
    while (x < xEnd) {
      final tileX = floorDiv(x, tileSize);
      final tileLeft = tileX * tileSize;
      final spanEnd = math.min(xEnd, tileLeft + tileSize);
      final out = (x - x0) * 4;
      final span = spanEnd - x;
      final from = (rowOffset + x - tileLeft) * 4;
      final coord = TileCoord(x: tileX, y: tileY);
      final own = _tiles[coord];
      if (own != null) {
        into.setRange(out, out + span * 4, own, from);
      } else {
        final tile = base.tileAt(coord);
        if (tile == null) {
          into.fillRange(out, out + span * 4, 0);
        } else {
          tile.readPixels(
            (_, view) => _premultiplyInto(into, out, view, from, span),
          );
        }
      }
      x = spanEnd;
    }
  }

  /// [count] straight 8-bit pixels of [source] from [from], premultiplied
  /// to 16 bits into [into] at [out].
  static void _premultiplyInto(
    Uint16List into,
    int out,
    Uint8List source,
    int from,
    int count,
  ) {
    for (var i = 0; i < count * 4; i += 4) {
      final alpha = source[from + i + 3];
      into[out + i] = _premultiplied(source[from + i], alpha);
      into[out + i + 1] = _premultiplied(source[from + i + 1], alpha);
      into[out + i + 2] = _premultiplied(source[from + i + 2], alpha);
      into[out + i + 3] = alpha * 257;
    }
  }

  /// round(channel × alpha × 257 / 255).
  static int _premultiplied(int channel, int alpha) =>
      (channel * alpha * 514 + 255) ~/ 510;

  /// One box pass along a line of RGBA pixels: every pixel in [start, end)
  /// of [target] takes the mean of the [radius] pixels of [source] either
  /// side of it and itself, rounded half up. [source] must hold
  /// [start] − [radius] to [end] + [radius].
  static void _box(
    Uint16List source,
    Uint16List target,
    int start,
    int end,
    int radius,
  ) {
    final count = radius * 2 + 1;
    final twice = count * 2;
    var r = 0;
    var g = 0;
    var b = 0;
    var a = 0;
    for (var i = (start - radius) * 4; i <= (start + radius) * 4; i += 4) {
      r += source[i];
      g += source[i + 1];
      b += source[i + 2];
      a += source[i + 3];
    }
    for (var at = start; at < end; at += 1) {
      final o = at * 4;
      target[o] = (r * 2 + count) ~/ twice;
      target[o + 1] = (g * 2 + count) ~/ twice;
      target[o + 2] = (b * 2 + count) ~/ twice;
      target[o + 3] = (a * 2 + count) ~/ twice;
      if (at + 1 < end) {
        final enter = (at + radius + 1) * 4;
        final leave = (at - radius) * 4;
        r += source[enter] - source[leave];
        g += source[enter + 1] - source[leave + 1];
        b += source[enter + 2] - source[leave + 2];
        a += source[enter + 3] - source[leave + 3];
      }
    }
  }

  /// Moves the dab's pixels down column [x] toward [blurred] (from
  /// [blurredStart]) by what the dab laid there. A pixel's move reads only
  /// itself and the finished blur, so writing column by column is the same
  /// as writing all at once. Returns whether any value moved.
  bool _moveColumn({
    required Uint16List blurred,
    required int blurredStart,
    required Uint16List laid,
    required int laidStride,
    required int column,
    required int x,
    required int top,
    required int height,
  }) {
    final tileX = floorDiv(x, tileSize);
    final localX = x - tileX * tileSize;
    final bottom = top + height;
    var moved = false;
    var y = top;
    while (y < bottom) {
      final tileY = floorDiv(y, tileSize);
      final spanEnd = math.min(bottom, (tileY + 1) * tileSize);
      Uint16List? own;
      for (var at = y; at < spanEnd; at += 1) {
        final row = at - top;
        final share = laid[row * laidStride + column];
        if (share == 0) {
          continue;
        }
        own ??= _tileFor(TileCoord(x: tileX, y: tileY));
        final o = ((at - tileY * tileSize) * tileSize + localX) * 4;
        final b = (blurredStart + row) * 4;
        final alpha = _toward(own[o + 3], blurred[b + 3], share);
        // Rounding apart, a mean of premultiplied pixels keeps every
        // channel under its alpha; this keeps the rounding from breaking it.
        final red = math.min(alpha, _toward(own[o], blurred[b], share));
        final green = math.min(
          alpha,
          _toward(own[o + 1], blurred[b + 1], share),
        );
        final blue = math.min(
          alpha,
          _toward(own[o + 2], blurred[b + 2], share),
        );
        if (red != own[o] ||
            green != own[o + 1] ||
            blue != own[o + 2] ||
            alpha != own[o + 3]) {
          own[o] = red;
          own[o + 1] = green;
          own[o + 2] = blue;
          own[o + 3] = alpha;
          moved = true;
        }
      }
      y = spanEnd;
    }
    return moved;
  }

  /// [from] moved toward [to] by [share] / 65535, rounded half away from
  /// zero.
  static int _toward(int from, int to, int share) =>
      from + _scaled(to - from, share, 65535);

  /// round([difference] × [factor] / [whole]), half away from zero.
  static int _scaled(int difference, int factor, int whole) =>
      difference >= 0
      ? (difference * factor * 2 + whole) ~/ (whole * 2)
      : -((-difference * factor * 2 + whole) ~/ (whole * 2));

  /// The rewritten tile at [coord], made from the cel's the first time.
  Uint16List _tileFor(TileCoord coord) => _tiles.putIfAbsent(coord, () {
    final values = Uint16List(tileSize * tileSize * 4);
    base
        .tileAt(coord)
        ?.readPixels(
          (_, view) =>
              _premultiplyInto(values, 0, view, 0, tileSize * tileSize),
        );
    return values;
  });

  /// The finished tile at [coord]: the cel moved toward the rewritten
  /// picture by [mask] (the selection folded with the tool's opacity, as a
  /// paint stroke's mask is; null = all the way), straight 8-bit like every
  /// cel tile — and whether any pixel differs from the cel's. Null where no
  /// dab has written.
  ///
  /// Where nothing moved the bytes ARE the cel's: premultiplying a byte to
  /// 16 bits and back returns it exactly (the rounding error stays under
  /// half a level at every alpha).
  ({Uint8List bytes, bool changed})? resultTile(
    TileCoord coord, {
    Uint8List? mask,
  }) {
    final own = _tiles[coord];
    if (own == null) {
      return null;
    }
    final pixelCount = tileSize * tileSize;
    final bytes = Uint8List(pixelCount * 4);
    base.tileAt(coord)?.copyPixelsInto(bytes);
    var changed = false;
    for (var p = 0; p < pixelCount; p += 1) {
      final cover = mask == null ? 255 : mask[p];
      if (cover == 0) {
        continue;
      }
      final i = p * 4;
      final celAlpha = bytes[i + 3];
      var alpha = own[i + 3];
      var red = own[i];
      var green = own[i + 1];
      var blue = own[i + 2];
      if (cover != 255) {
        final cel = celAlpha * 257;
        alpha = cel + _scaled(alpha - cel, cover, 255);
        red = _covered(bytes[i], celAlpha, red, cover, alpha);
        green = _covered(bytes[i + 1], celAlpha, green, cover, alpha);
        blue = _covered(bytes[i + 2], celAlpha, blue, cover, alpha);
      }
      final outAlpha = (alpha * 2 + 257) ~/ 514;
      final outRed = _straight(red, alpha, outAlpha);
      final outGreen = _straight(green, alpha, outAlpha);
      final outBlue = _straight(blue, alpha, outAlpha);
      if (outRed != bytes[i] ||
          outGreen != bytes[i + 1] ||
          outBlue != bytes[i + 2] ||
          outAlpha != celAlpha) {
        bytes[i] = outRed;
        bytes[i + 1] = outGreen;
        bytes[i + 2] = outBlue;
        bytes[i + 3] = outAlpha;
        changed = true;
      }
    }
    return (bytes: bytes, changed: changed);
  }

  /// The cel's [channel] (straight, under [celAlpha]) moved toward the
  /// rewritten premultiplied [own] by [cover] / 255, kept under [alpha].
  static int _covered(int channel, int celAlpha, int own, int cover, int alpha) {
    final cel = _premultiplied(channel, celAlpha);
    return math.min(alpha, cel + _scaled(own - cel, cover, 255));
  }

  /// A premultiplied 16-bit [channel] over [alpha], as a straight byte —
  /// none at all under an alpha that rounds to nothing ([outAlpha]).
  static int _straight(int channel, int alpha, int outAlpha) => outAlpha == 0
      ? 0
      : math.min(255, (channel * 510 + alpha) ~/ (alpha * 2));
}
