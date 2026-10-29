import 'dart:ffi' show Pointer, StructPointer, Uint16, Uint8, nullptr;
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/floor_math.dart';
import '../models/bitmap_surface.dart';
import '../models/brush_dab.dart';
import '../models/dirty_region.dart';
import '../models/pasteboard_bounds.dart';
import '../models/tile_coord.dart';
import '../native/qa_blur_kernel.dart';
import '../native/qa_native_engine.dart';
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
/// - No channel ever passes its alpha, with nothing holding it there: a
///   rounded mean of premultiplied pixels keeps every channel at or under
///   its alpha, and a channel and its alpha moved by one share toward a
///   blur that keeps that order land — each rounded to nearest — in that
///   order still. A cap would be code that cannot run (I-75 뮤턴트 M9).
///
/// The tool's OPACITY and the SELECTION are not here: they cap how far the
/// finished picture may move from the cel ([resultTile]'s mask), exactly as
/// they cap a paint stroke's accumulated buffer.
///
/// With the engine loaded a dab and a finished tile are the C's
/// (`qa_blur_dab`, `qa_blur_result_tile`, ABI 58) — a blur dab costs far
/// more than a paint dab, and the brush lays at the finest step. The passes
/// below are the reference it matches byte for byte, and what runs without
/// the engine.
class BrushBlurPicture {
  BrushBlurPicture({required this.base, required this.wall})
    : tileSize = base.tileSize;

  /// The cel as the stroke found it — what every pixel the stroke has not
  /// rewritten still reads. ⚠️It also keeps its tiles alive while the C
  /// reads them through raw pointers ([BitmapTile.readPixels]).
  final BitmapSurface base;
  final PasteboardWall wall;
  final int tileSize;

  /// The engine and its blur kernels — null where the passes below run.
  final ({QaNativeEngine engine, QaBlurKernel kernel})? _native =
      _nativeRoute();

  static ({QaNativeEngine engine, QaBlurKernel kernel})? _nativeRoute() {
    final engine = QaNativeEngine.instance;
    final kernel = QaBlurKernel.instance;
    return engine == null || kernel == null
        ? null
        : (engine: engine, kernel: kernel);
  }

  /// The rewritten tiles: premultiplied RGBA at 16 bits (alpha × 257, a
  /// channel × alpha × 257 / 255), each complete — made from [base] whole
  /// for every tile a dab's rectangle meets. Native-backed under the
  /// engine, whose kernel writes them ([dispose] lets them go).
  final Map<TileCoord, _Rewritten> _tiles = {};

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

  /// The box radius of the dab being blurred ([blurRadiusOf]).
  int _radius = 1;

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
  /// Returns the rectangle it rewrote, or null where it lays nothing.
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
    _radius = blurRadiusOf(dab);
    _rewriteUnder(plan.clip);
    final native = _native;
    if (native == null) {
      _blurInDart(plan);
    } else {
      _blurInC(native, plan);
    }
    return plan.clip;
  }

  /// Makes the rewritten tile of every tile [clip] meets — what both
  /// routes write a dab into.
  void _rewriteUnder(DirtyRegion clip) {
    final right = floorDiv(clip.rightExclusive - 1, tileSize);
    final bottom = floorDiv(clip.bottomExclusive - 1, tileSize);
    for (var y = floorDiv(clip.top, tileSize); y <= bottom; y += 1) {
      for (var x = floorDiv(clip.left, tileSize); x <= right; x += 1) {
        _tileFor(TileCoord(x: x, y: y));
      }
    }
  }

  /// The C's dab: the picture over the window the blur reads, a tile table
  /// row by row.
  void _blurInC(
    ({QaNativeEngine engine, QaBlurKernel kernel}) native,
    BrushDabPlan plan,
  ) {
    final reach = _radius * 3;
    final x0 = floorDiv(plan.left - reach, tileSize);
    final y0 = floorDiv(plan.top - reach, tileSize);
    final x1 = floorDiv(plan.rightExclusive + reach - 1, tileSize);
    final y1 = floorDiv(plan.bottomExclusive + reach - 1, tileSize);
    final tilesWide = x1 - x0 + 1;
    final table = native.kernel.tiles(tilesWide * (y1 - y0 + 1));
    for (var y = y0; y <= y1; y += 1) {
      for (var x = x0; x <= x1; x += 1) {
        final coord = TileCoord(x: x, y: y);
        final entry = table[(y - y0) * tilesWide + (x - x0)];
        entry.own = _tiles[coord]?.buffer?.pointer.cast<Uint16>() ?? nullptr;
        entry.cel = _celPointer(coord);
      }
    }
    native.kernel.blurDab(
      stageDabAlone(native.engine, plan),
      tilesWide: tilesWide,
      tileX0: x0,
      tileY0: y0,
      tileSize: tileSize,
      rect: (
        left: plan.left,
        top: plan.top,
        rightExclusive: plan.rightExclusive,
        bottomExclusive: plan.bottomExclusive,
      ),
      radius: _radius,
    );
  }

  /// The cel's tile at [coord] for the C to read, or `nullptr` where it has
  /// none. The pointer outlives [BitmapTile.readPixels]: [base] holds the
  /// tile, so it stays reachable as long as this picture is.
  Pointer<Uint8> _celPointer(TileCoord coord) =>
      base.tileAt(coord)?.readPixels((pointer, _) => pointer) ?? nullptr;

  /// The passes in Dart — the reference the C matches.
  void _blurInDart(BrushDabPlan plan) {
    final laid = _measureLaid(plan);
    final reach = _radius * 3;
    final width = plan.rightExclusive - plan.left;
    final wide = width + reach * 2;
    final tall = plan.bottomExclusive - plan.top + reach * 2;
    _ensureRoom(width: width, wide: wide, tall: tall);

    // Along the rows: every row the blur reads, the dab's columns kept.
    final rowValues = width * 4;
    for (var row = 0; row < tall; row += 1) {
      _gatherRow(_lineA, plan.left - reach, plan.top - reach + row, wide);
      _blurLine((values: _lineA, from: 0, step: 4), wide);
      _across.setRange(
        row * rowValues,
        (row + 1) * rowValues,
        _lineB,
        reach * 4,
      );
    }

    // Along the columns, read where the rows left them, and the dab's
    // pixels moved toward what they leave.
    for (var column = 0; column < width; column += 1) {
      _blurLine((values: _across, from: column * 4, step: rowValues), tall);
      _moveColumn(plan, laid, column);
    }
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
          second: null,
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
      final own = _tiles[coord]?.values;
      if (own != null) {
        into.setRange(out, out + span * 4, own, from);
      } else {
        final tile = base.tileAt(coord);
        if (tile == null) {
          into.fillRange(out, out + span * 4, 0);
        } else {
          tile.readPixels(
            (_, view) => _premultiplyInto(
              Uint16List.sublistView(into, out, out + span * 4),
              Uint8List.sublistView(view, from, from + span * 4),
            ),
          );
        }
      }
      x = spanEnd;
    }
  }

  /// The straight 8-bit pixels of [source], premultiplied to 16 bits into
  /// [into].
  static void _premultiplyInto(Uint16List into, Uint8List source) {
    for (var i = 0; i < source.length; i += 4) {
      final alpha = source[i + 3];
      into[i] = _premultiplied(source[i], alpha);
      into[i + 1] = _premultiplied(source[i + 1], alpha);
      into[i + 2] = _premultiplied(source[i + 2], alpha);
      into[i + 3] = alpha * 257;
    }
  }

  /// round(channel × alpha × 257 / 255).
  static int _premultiplied(int channel, int alpha) =>
      (channel * alpha * 514 + 255) ~/ 510;

  /// The three box passes along [line], [length] pixels long: the blur of
  /// every pixel three radii in from either end, left in [_lineB].
  void _blurLine(_Line line, int length) {
    _box(line, _lineB, 1, length);
    _box((values: _lineB, from: 0, step: 4), _lineA, 2, length);
    _box((values: _lineA, from: 0, step: 4), _lineB, 3, length);
  }

  /// Box pass [pass] along [source], [length] pixels long: every pixel
  /// [pass] radii in from either end takes into [target] the mean of the
  /// [_radius] pixels either side of it and itself, rounded half up — what
  /// the pass before left whole one radius further out.
  void _box(_Line source, Uint16List target, int pass, int length) {
    final radius = _radius;
    final start = radius * pass;
    final end = length - start;
    final values = source.values;
    final from = source.from;
    final step = source.step;
    final count = radius * 2 + 1;
    final twice = count * 2;
    var r = 0;
    var g = 0;
    var b = 0;
    var a = 0;
    for (var at = start - radius; at <= start + radius; at += 1) {
      final i = from + at * step;
      r += values[i];
      g += values[i + 1];
      b += values[i + 2];
      a += values[i + 3];
    }
    for (var at = start; at < end; at += 1) {
      final o = at * 4;
      target[o] = (r * 2 + count) ~/ twice;
      target[o + 1] = (g * 2 + count) ~/ twice;
      target[o + 2] = (b * 2 + count) ~/ twice;
      target[o + 3] = (a * 2 + count) ~/ twice;
      if (at + 1 < end) {
        final enter = from + (at + radius + 1) * step;
        final leave = from + (at - radius) * step;
        r += values[enter] - values[leave];
        g += values[enter + 1] - values[leave + 1];
        b += values[enter + 2] - values[leave + 2];
        a += values[enter + 3] - values[leave + 3];
      }
    }
  }

  /// Moves [plan]'s pixels down its [column] toward the blur [_blurLine]
  /// left in [_lineB], by what the dab [laid] there. A pixel's move reads
  /// only itself and the finished blur, so writing column by column is the
  /// same as writing all at once.
  void _moveColumn(BrushDabPlan plan, Uint16List laid, int column) {
    final width = plan.rightExclusive - plan.left;
    final reach = _radius * 3;
    final x = plan.left + column;
    final tileX = floorDiv(x, tileSize);
    final localX = x - tileX * tileSize;
    final top = plan.top;
    final bottom = plan.bottomExclusive;
    var y = top;
    while (y < bottom) {
      final tileY = floorDiv(y, tileSize);
      final spanEnd = math.min(bottom, (tileY + 1) * tileSize);
      Uint16List? own;
      for (var at = y; at < spanEnd; at += 1) {
        final share = laid[(at - top) * width + column];
        if (share == 0) {
          continue;
        }
        own ??= _tileFor(TileCoord(x: tileX, y: tileY)).values;
        final o = ((at - tileY * tileSize) * tileSize + localX) * 4;
        final b = (reach + at - top) * 4;
        own[o] = _toward(own[o], _lineB[b], share);
        own[o + 1] = _toward(own[o + 1], _lineB[b + 1], share);
        own[o + 2] = _toward(own[o + 2], _lineB[b + 2], share);
        own[o + 3] = _toward(own[o + 3], _lineB[b + 3], share);
      }
      y = spanEnd;
    }
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

  /// The rewritten tile at [coord], made from the cel's the first time —
  /// in the engine's memory when its kernel is to write it.
  _Rewritten _tileFor(TileCoord coord) => _tiles.putIfAbsent(coord, () {
    final count = tileSize * tileSize * 4;
    final buffer = _native?.engine.acquireTileBuffer(count * 2, zeroed: false);
    final values = buffer == null
        ? Uint16List(count)
        : buffer.view.buffer.asUint16List(buffer.view.offsetInBytes, count);
    final cel = base.tileAt(coord);
    if (cel == null) {
      values.fillRange(0, count, 0);
    } else {
      cel.readPixels((_, view) => _premultiplyInto(values, view));
    }
    return (values: values, buffer: buffer);
  });

  /// Lets the engine's memory go — the rewritten tiles it holds. The
  /// stroke's end ([BrushLiveStrokeRasterizer.clear]).
  void dispose() {
    final native = _native;
    for (final tile in _tiles.values) {
      final buffer = tile.buffer;
      if (native != null && buffer != null) {
        native.engine.releaseTileBuffer(buffer);
      }
    }
    _tiles.clear();
    native?.kernel.releaseScratch();
  }

  /// The finished tile at [coord]: the cel moved toward the rewritten
  /// picture by [mask] (the selection folded with the tool's opacity, as a
  /// paint stroke's mask is; null = all the way), straight 8-bit like every
  /// cel tile — and whether any pixel differs from the cel's. Null where no
  /// dab has written.
  ///
  /// Where the picture is still the cel's the bytes ARE the cel's — kept,
  /// not made again: a colour behind no alpha would not come back from
  /// its premultiplied form, and making the rest again would cost what
  /// keeping it does not.
  ///
  /// Under the engine the C makes it, into [into] — the buffer the
  /// coordinate's last result held — or a fresh one; the caller owns the
  /// buffer it is handed back in.
  ({Uint8List bytes, bool changed, QaNativeTileBuffer? buffer})? resultTile(
    TileCoord coord, {
    ({Uint8List bytes, QaNativeTileBuffer? buffer})? mask,
    QaNativeTileBuffer? into,
  }) {
    final own = _tiles[coord];
    if (own == null) {
      return null;
    }
    final native = _native;
    final ownBuffer = own.buffer;
    final maskPointer = mask == null ? nullptr : mask.buffer?.pointer;
    if (native != null && ownBuffer != null && maskPointer != null) {
      final out =
          into ??
          native.engine.acquireTileBuffer(
            tileSize * tileSize * 4,
            zeroed: false,
          );
      final changed = native.kernel.resultTile(
        own: ownBuffer.pointer.cast<Uint16>(),
        cel: _celPointer(coord),
        mask: maskPointer,
        tileSize: tileSize,
        out: out.pointer,
      );
      return (bytes: out.view, changed: changed, buffer: out);
    }
    final made = _resultInDart(coord, own.values, mask?.bytes);
    return (bytes: made.bytes, changed: made.changed, buffer: null);
  }

  /// [resultTile] in Dart — the reference the C matches.
  ({Uint8List bytes, bool changed}) _resultInDart(
    TileCoord coord,
    Uint16List own,
    Uint8List? mask,
  ) {
    final pixelCount = tileSize * tileSize;
    final bytes = Uint8List(pixelCount * 4);
    base.tileAt(coord)?.copyPixelsInto(bytes);
    // A pixel's four bytes as one word: red is its low byte on the
    // little-endian machines the app runs on (as `cel_text_laying` reads
    // them).
    final pixels = bytes.buffer.asUint32List();
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
      if (alpha == celAlpha * 257 &&
          red == _premultiplied(bytes[i], celAlpha) &&
          green == _premultiplied(bytes[i + 1], celAlpha) &&
          blue == _premultiplied(bytes[i + 2], celAlpha)) {
        continue; // The picture is the cel's here: its bytes stand.
      }
      if (cover != 255) {
        final cel = celAlpha * 257;
        alpha = cel + _scaled(alpha - cel, cover, 255);
        red = _covered(bytes[i], celAlpha, red, cover);
        green = _covered(bytes[i + 1], celAlpha, green, cover);
        blue = _covered(bytes[i + 2], celAlpha, blue, cover);
      }
      final outAlpha = (alpha * 2 + 257) ~/ 514;
      final pixel =
          outAlpha << 24 |
          _straight(blue, alpha, outAlpha) << 16 |
          _straight(green, alpha, outAlpha) << 8 |
          _straight(red, alpha, outAlpha);
      if (pixel != pixels[p]) {
        pixels[p] = pixel;
        changed = true;
      }
    }
    return (bytes: bytes, changed: changed);
  }

  /// The cel's [channel] (straight, under [celAlpha]) moved toward the
  /// rewritten premultiplied [own] by [cover] / 255.
  static int _covered(int channel, int celAlpha, int own, int cover) {
    final cel = _premultiplied(channel, celAlpha);
    return cel + _scaled(own - cel, cover, 255);
  }

  /// A premultiplied 16-bit [channel] over [alpha], as a straight byte —
  /// none at all under an alpha that rounds to nothing ([outAlpha]).
  static int _straight(int channel, int alpha, int outAlpha) =>
      outAlpha == 0 ? 0 : (channel * 510 + alpha) ~/ (alpha * 2);
}

/// A line of RGBA pixels inside a plane: its first pixel at `from`, each
/// next one `step` values on — a line buffer's (step 4), or one column of
/// the rows' blur (step: a row's values).
typedef _Line = ({Uint16List values, int from, int step});

/// A rewritten tile: its values, and the engine's buffer they live in when
/// the C writes them.
typedef _Rewritten = ({Uint16List values, QaNativeTileBuffer? buffer});
