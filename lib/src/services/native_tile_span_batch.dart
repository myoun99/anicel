import 'dart:ffi' show Pointer, Uint8;
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/tile_coord.dart';
import '../native/qa_native_engine.dart';

/// Stages one span per tile that [left]..[rightExclusive) ×
/// [top]..[bottomExclusive) touches into the engine's span batch and
/// returns the coordinates in span order — index `i` of the changed
/// flags a kernel writes back is `coords[i]` ([changedTileCoords]).
///
/// 🚨ONE staging walk for the generic dab, the stamp and the stroke
/// blend (round 8 of the audit, 2026-09-06) — three hand-written copies
/// of the same loop before.
///
/// One BATCH call per dab (R18 A-3a): the spans fan out across the C
/// worker pool — tiles are disjoint, so the result is byte-identical to
/// the sequential per-tile loop.
///
/// [pointerFor] returns the tile's native scratch pointer, CREATING the
/// buffer if this is the first span to touch the tile. It is called
/// exactly once per span, in span order (tile row outer, column inner).
List<TileCoord> stageTileSpans(
  QaNativeEngine native, {
  required int left,
  required int top,
  required int rightExclusive,
  required int bottomExclusive,
  required int tileSize,
  required Pointer<Uint8> Function(TileCoord coord) pointerFor,
}) {
  final (:firstX, :lastX, :firstY, :lastY) = tileRangeOf(
    left: left,
    top: top,
    rightExclusive: rightExclusive,
    bottomExclusive: bottomExclusive,
    tileSize: tileSize,
  );
  final coords = <TileCoord>[];
  native.ensureTileSpanBatch((lastY - firstY + 1) * (lastX - firstX + 1));
  for (var tileY = firstY; tileY <= lastY; tileY += 1) {
    final tileTop = tileY * tileSize;
    final spanTop = math.max(top, tileTop);
    final spanBottomExclusive = math.min(bottomExclusive, tileTop + tileSize);
    for (var tileX = firstX; tileX <= lastX; tileX += 1) {
      final coord = TileCoord(x: tileX, y: tileY);
      final tileLeft = tileX * tileSize;
      native.setTileSpan(
        coords.length,
        tilePixels: pointerFor(coord),
        tileLeft: tileLeft,
        tileTop: tileTop,
        spanLeft: math.max(left, tileLeft),
        spanRightExclusive: math.min(rightExclusive, tileLeft + tileSize),
        spanTop: spanTop,
        spanBottomExclusive: spanBottomExclusive,
      );
      coords.add(coord);
    }
  }
  return coords;
}

/// The coordinates a kernel reported changed: `coords[i]` for every
/// `changed[i] != 0`, in batch order.
List<TileCoord> changedTileCoords(Uint8List changed, List<TileCoord> coords) =>
    [
      for (var i = 0; i < coords.length; i += 1)
        if (changed[i] != 0) coords[i],
    ];
