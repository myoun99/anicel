import 'dart:ffi' show Pointer, Uint8;
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/dirty_region.dart';
import '../models/tile_coord.dart';
import '../native/qa_native_engine.dart';

/// Stages one span per tile that [clip] touches into the engine's span
/// batch and returns the coordinates in span order — index `i` of the
/// changed flags a kernel writes back is `coords[i]`
/// ([changedTileCoords]).
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
  required DirtyRegion clip,
  required int tileSize,
  required Pointer<Uint8> Function(TileCoord coord) pointerFor,
}) => stageTileSpansCovering(
  native,
  clips: [clip],
  tileSize: tileSize,
  pointerFor: pointerFor,
);

/// [stageTileSpans] for a batch of regions (ABI 38 — the generic dabs of a
/// call, `qa_dab_blend_batch`): one span per tile ANY of [clips] touches,
/// the rect they make there together, each tile once. One region stages
/// exactly the spans it always did.
List<TileCoord> stageTileSpansCovering(
  QaNativeEngine native, {
  required List<DirtyRegion> clips,
  required int tileSize,
  required Pointer<Uint8> Function(TileCoord coord) pointerFor,
}) {
  final spans = <TileCoord, DirtyRegion>{};
  for (final clip in clips) {
    final (:firstX, :lastX, :firstY, :lastY) = clip.tileRange(
      tileSize: tileSize,
    );
    for (var tileY = firstY; tileY <= lastY; tileY += 1) {
      final tileTop = tileY * tileSize;
      for (var tileX = firstX; tileX <= lastX; tileX += 1) {
        final tileLeft = tileX * tileSize;
        final span = DirtyRegion(
          left: math.max(clip.left, tileLeft),
          top: math.max(clip.top, tileTop),
          rightExclusive: math.min(clip.rightExclusive, tileLeft + tileSize),
          bottomExclusive: math.min(clip.bottomExclusive, tileTop + tileSize),
        );
        final coord = TileCoord(x: tileX, y: tileY);
        final held = spans[coord];
        spans[coord] = held == null ? span : held.union(span);
      }
    }
  }
  final coords = spans.keys.toList()
    ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
  native.ensureTileSpanBatch(coords.length);
  for (var index = 0; index < coords.length; index += 1) {
    final coord = coords[index];
    final span = spans[coord]!;
    native.setTileSpan(
      index,
      tilePixels: pointerFor(coord),
      tileLeft: coord.x * tileSize,
      tileTop: coord.y * tileSize,
      spanLeft: span.left,
      spanRightExclusive: span.rightExclusive,
      spanTop: span.top,
      spanBottomExclusive: span.bottomExclusive,
    );
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
