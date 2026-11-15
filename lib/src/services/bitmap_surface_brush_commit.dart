import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart';

import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_blend_mode.dart';
import '../models/brush_dab.dart';
import '../models/brush_dab_sequence.dart';
import '../models/brush_stamp_image.dart';
import '../models/dirty_region.dart';
import '../models/dirty_tile_set.dart';
import '../models/placed_tile.dart';
import '../models/tile_coord.dart';
import '../native/app_gpu_engine.dart';
import '../native/engine_stamp_pictures.dart';
import '../native/engine_tile_ledger.dart';
import 'brush_stroke_landing.dart';
import 'brush_stroke_blend.dart';
import 'selection_clip.dart';

class BrushSurfaceMaterialization {
  const BrushSurfaceMaterialization({
    required this.surface,
    required this.dirtyTiles,
  });

  final BitmapSurface surface;
  final DirtyTileSet dirtyTiles;

  bool get hasChanges => dirtyTiles.isNotEmpty;
}

/// Rasterizes [sequence] onto [surface] and returns the updated surface plus
/// the tiles it changed: the engine lays it ([_materializedOnEngine]), and
/// a surface off its grid is refused ([drawnByTheEngineAlone]).
///
/// ⛔A worker has no engine to ask, and what would come back are tiles of a
/// pool no other isolate reads: a vector layer an import draws plans its
/// strokes on a worker and lays them on the isolate that has the engine
/// (`clipVectorTiles`). ↩️Till 2026-11-12 it drew them on the worker, as
/// the small grids were drawn — the last road that way had in the app.
///
/// 🚨★★★A STAMP IN A SELECTION LANDS UNDER THE SELECTION'S MASK (2026-11-14,
/// board `a-selection-mask-is-built-on-the-cpu-at-every-move`): [selection]
/// cuts each stamp of [sequence] where it lands — the stamp's own picture
/// laid under [SelectionClip.maskOnEngine], the mask a stroke under the
/// same clip lands under. ↩️Every road cut its stamps on the CPU before
/// they came here — a mask and a copy of the picture at each.
///
/// ⛔Stamps only: a stroke of brush dabs under a selection lands by its
/// stroke ([strokeLandedOn]) or as one buffer
/// ([compositeStrokePixelsOntoBitmapSurface]), and nothing hands one here.
BrushSurfaceMaterialization materializeBrushDabSequenceOnBitmapSurface({
  required BitmapSurface surface,
  required BrushDabSequence sequence,
  SelectionClip? selection,
}) {
  if (selection != null && sequence.dabs.any((dab) => dab.stamp == null)) {
    throw ArgumentError.value(
      selection,
      'selection',
      'cuts stamps; a brush dab lands under a selection by its stroke',
    );
  }
  drawnByTheEngineAlone(surface.tileSize);
  return _materializedOnEngine(surface, sequence, selection);
}

/// [sequence] laid on [surface] by the engine (flip lane ⓒ), in its order:
/// a run of brush dabs piled and laid as one stroke, each stamp by itself —
/// a lift's landing means what it says only dab by dab —, under
/// [selection]'s mask where there is one. What each lands on is what the
/// one before it left. A tile a landing emptied is DROPPED rather than
/// stored — see [BitmapSurface.putMaterializedTiles].
///
/// ⚠️[DirtyTileSet] still names a dropped coordinate, and has to: its one
/// consumer is [CacheInvalidationPlan.fromDirtyTiles], and a coordinate
/// whose tile just went away is exactly one whose cached picture must go
/// with it.
BrushSurfaceMaterialization _materializedOnEngine(
  BitmapSurface surface,
  BrushDabSequence sequence,
  SelectionClip? selection,
) {
  var landed = surface;
  final changed = <TileCoord>{};
  void put(List<PlacedTile> tiles) {
    if (tiles.isNotEmpty) {
      landed = landed.putMaterializedTiles(tiles);
      changed.addAll(tiles.map((tile) => tile.coord));
    }
  }

  final dabs = sequence.dabs;
  var at = 0;
  while (at < dabs.length) {
    final first = dabs[at];
    final stamp = first.stamp;
    if (stamp != null) {
      at += 1;
      put(_stampDabOnEngine(landed, first, stamp, selection));
      continue;
    }
    var end = at + 1;
    while (end < dabs.length &&
        dabs[end].stamp == null &&
        dabs[end].erase == first.erase) {
      end += 1;
    }
    put(strokeLandedOn(landed, BrushDabSequence(dabs.getRange(at, end))));
    at = end;
  }
  final coords = changed.toList()..sort(TileCoord.compareRowMajor);
  return BrushSurfaceMaterialization(
    surface: landed,
    dirtyTiles: coords.isEmpty ? DirtyTileSet.empty() : DirtyTileSet(coords),
  );
}

/// [dab]'s [stamp] laid on [surface] by the engine, under [selection]'s
/// mask where there is one: a picture, or a mask under its paint
/// ([EngineStampPictures.madeOfMask]).
List<PlacedTile> _stampDabOnEngine(
  BitmapSurface surface,
  BrushDab dab,
  BrushStampImage stamp,
  SelectionClip? selection,
) {
  final landing = stamp.landingRect(dab.center);
  final opacity = (dab.opacity * 65535).round();
  final mode = engineBlendModeOf(BrushBlendMode.color, erase: dab.erase);
  final ofMask = EngineStampPictures.madeOfMask(stamp);
  return _stampOnEngine(
    surface,
    landing,
    selection,
    (clip, mask) => ofMask == null
        ? _picture(
            EngineStampPictures.of(stamp),
            landing,
            clip,
            opacity: opacity,
            mode: mode,
            mask: mask,
          )
        : _ofMask(
            ofMask,
            opacity: opacity,
            mode: mode,
            mask: mask,
          ),
  );
}

/// A stamp over [landing], what the pasteboard's wall leaves of it — a
/// selection dropped past the stage's edge keeps its pixels there —, laid
/// on [surface] as [lays] says for that `clip`, under [within]'s mask where
/// there is one: the tiles it changes, a blank one where none is left.
/// [lays] is asked only where something of the stamp can land.
List<PlacedTile> _stampOnEngine(
  BitmapSurface surface,
  DirtyRegion landing,
  SelectionClip? within,
  LandedBy Function(DirtyRegion clip, GpuMask? mask) lays,
) {
  final clip = landing.intersection(surface.pasteboard.region);
  if (clip == null || !(within?.mayCover(clip) ?? true)) {
    return const [];
  }
  final tileSize = surface.tileSize;
  final (:firstX, :lastX, :firstY, :lastY) = clip.tileRange(tileSize: tileSize);
  final coords = [
    for (var y = firstY; y <= lastY; y += 1)
      for (var x = firstX; x <= lastX; x += 1) TileCoord(x: x, y: y),
  ];
  final landed = EngineTileLedger.instance.land(
    EngineTileLedger.landedCel,
    [
      for (final coord in coords)
        (column: coord.x, row: coord.y, under: surface.tileAt(coord)),
    ],
    by: lays(clip, within?.maskOnEngine()),
    compared: true,
  );
  return [
    for (var at = 0; at < landed.length; at += 1)
      if (landed[at].change != GpuChange.same)
        (
          coord: coords[at],
          tile: landed[at].tile ?? BitmapTile.blank(size: tileSize),
        ),
  ];
}

/// [picture], its top-left pixel at [landing]'s, what of it lies within
/// [clip], as the engine lays it at [opacity] (65535 whole) in [mode],
/// under [mask] if any.
LandedBy _picture(
  GpuStampPicture picture,
  DirtyRegion landing,
  DirtyRegion clip, {
  required int opacity,
  required int mode,
  required GpuMask? mask,
}) => (pool, cel, asked) => appGpuStampLanding.land(
  appGpuComposite,
  pool,
  cel,
  picture,
  left: landing.left,
  top: landing.top,
  within: (clip.left, clip.top, clip.rightExclusive, clip.bottomExclusive),
  asks: asked,
  opacity: opacity,
  mode: mode,
  mask: mask,
);

/// A stamp [made] of a mask ([EngineStampPictures.ofMask]) — its box made
/// to the wall — as the engine lays it under its paint at [opacity] (65535
/// whole) in [mode], under [mask] if any.
LandedBy _ofMask(
  StampOfMask made, {
  required int opacity,
  required int mode,
  required GpuMask? mask,
}) {
  final coverage = made.coverage();
  return (pool, cel, asked) => appGpuStampLanding.landMask(
    appGpuComposite,
    pool,
    cel,
    coverage,
    paint: made.paint,
    whole: made.whole,
    asks: asked,
    opacity: opacity,
    mode: mode,
    mask: mask,
  );
}

/// [stamp], its top-left pixel at ([left], [top]), laid at full strength
/// on [unders] — tiles of [grid]'s cel at their coordinates, null where it
/// has none — as a picture stamped there lands
/// ([compositeStrokePixelsOntoBitmapSurface]): what each becomes, the very
/// tile where no byte of it changed, null where nothing is left.
///
/// ⚠️Only [unders]' coordinates are laid, however many more [stamp]
/// reaches: a caller that already knows what the others become (the texts'
/// pairs of tiles, cel_text_laying.dart) would otherwise have them laid a
/// second time over what they became.
Map<TileCoord, BitmapTile?> stampLaidOver(
  BitmapSurface grid,
  BrushStampImage stamp, {
  required int left,
  required int top,
  required Map<TileCoord, BitmapTile?> unders,
}) {
  final landing = DirtyRegion(
    left: left,
    top: top,
    rightExclusive: left + stamp.width,
    bottomExclusive: top + stamp.height,
  );
  drawnByTheEngineAlone(grid.tileSize);
  final clip = landing.intersection(grid.pasteboard.region);
  if (clip == null) {
    return {...unders};
  }
  final coords = unders.keys.toList();
  final landed = EngineTileLedger.instance.land(
    EngineTileLedger.landedCel,
    [
      for (final coord in coords)
        (column: coord.x, row: coord.y, under: unders[coord]),
    ],
    by: _picture(
      EngineStampPictures.of(stamp),
      landing,
      clip,
      opacity: 65535,
      mode: engineBlendModeOf(BrushBlendMode.color, erase: false),
      mask: null,
    ),
    compared: true,
  );
  return {
    for (final (at, coord) in coords.indexed)
      coord: landed[at].change == GpuChange.same
          ? unders[coord]
          : landed[at].tile,
  };
}

/// Composites a pre-rasterized straight-alpha stroke buffer onto [surface]
/// within [bounds].
///
/// [strokePixels] is BOUNDS-LOCAL: row-major with stride = the bounds
/// width, exactly what `BrushLiveStrokeRasterizer.strokePixelsWithinBounds`
/// materializes — its size scales with the stroke, never the canvas.
///
/// This is the pen-up fast path: the interactive view piles the stroke up
/// on its own buffer while the pointer moves (`BrushLiveStrokeRasterizer`,
/// the dab kernels [materializeBrushDabSequenceOnBitmapSurface] runs), so
/// commit is one source-over pass of the finished stroke over the existing
/// artwork — removing the commit hiccup for long dense strokes. The
/// composited pixels are exactly the stroke the user watched being drawn.
///
/// ⚠️It is also the ONLY way a stroke of brush dabs lands: one re-derived
/// from its dabs is piled up on an empty surface first and comes through
/// here (`brushCommitResultForBrushDabSequenceOnBitmapSurface`). The same
/// dabs laid on the artwork one by one reach the same sum but round after
/// every dab, a level away over paint.
///
/// ↩️R21: off the engine's grid it was one synthetic stamp dab through the
/// materializer, a brush blend computed here first (BB-1); that grid is
/// refused now ([drawnByTheEngineAlone]).
///
/// [selection] cuts it as [materializeBrushDabSequenceOnBitmapSurface] cuts
/// a stamp: under the clip's mask.
BrushSurfaceMaterialization compositeStrokePixelsOntoBitmapSurface({
  required BitmapSurface surface,
  required Uint8List strokePixels,
  required DirtyRegion bounds,
  bool erase = false,
  BrushBlendMode blendMode = BrushBlendMode.color,
  SelectionClip? selection,
}) {
  final width = bounds.rightExclusive - bounds.left;
  final height = bounds.bottomExclusive - bounds.top;
  if (width <= 0 || height <= 0) {
    return BrushSurfaceMaterialization(
      surface: surface,
      dirtyTiles: DirtyTileSet.empty(),
    );
  }
  drawnByTheEngineAlone(surface.tileSize);
  // One landing whatever the blend: the engine lays the stroke's picture
  // in its mode.
  final tiles = _stampOnEngine(
    surface,
    bounds,
    selection,
    (clip, mask) => _picture(
      GpuStampPicture(appGpuEngine, strokePixels, width, height),
      bounds,
      clip,
      opacity: 65535,
      mode: engineBlendModeOf(blendMode, erase: erase),
      mask: mask,
    ),
  );
  final coords = [for (final tile in tiles) tile.coord]
    ..sort(TileCoord.compareRowMajor);
  return BrushSurfaceMaterialization(
    surface: coords.isEmpty ? surface : surface.putMaterializedTiles(tiles),
    dirtyTiles: coords.isEmpty ? DirtyTileSet.empty() : DirtyTileSet(coords),
  );
}
