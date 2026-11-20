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

/// [materializeBrushDabSequenceOnBitmapSurface] of one stamp, [dab]'s, with
/// no wait for the GPU: asked now, over [surface]'s tiles as the engine
/// holds them now, and answered once the GPU has said what each tile
/// became ([EngineTileLedger.landOnceTold]). [unput] is called where the
/// tiles it answered with were not put after all: the surface is
/// forgotten there.
///
/// 🗣️opening-a-transform-box-holds-the-ui-over-half-a-second (브러시/렌더링
/// 2026-11-20): a box at rest cuts its cels ahead of the press — a cel's
/// hole, its float — and each waited for the GPU on the UI's thread, 🔬4
/// to 18 ms a turn and 31 to 63 with the GPU's queue full (공통, S5_BA cut
/// 352, 메인 PC 테스트 VM). What is made ahead waits for nothing.
///
/// ⚠️NOT A SECOND WAY TO THE PIXELS: the stamp is asked as the waited road
/// asks it ([_stampAsks]), laid as it lays it ([_layingOf]) and by the
/// kernel it is laid by, and what lands is made of as it makes of it
/// ([_placedOf]). The engine's door alone differs — `GpuStampLanding.
/// finished` for `land` —, and that the two say the same of every tile is
/// held there (rust/src/kernels/dab/finished_tests.rs) and here
/// (a_stamp_laid_once_told_is_the_stamp_laid_waited_test.dart).
Future<BrushSurfaceMaterialization> materializeStampOnceTold({
  required BitmapSurface surface,
  required BrushDab dab,
  SelectionClip? selection,
  required void Function() unput,
}) async {
  final stamp = dab.stamp;
  if (stamp == null) {
    throw ArgumentError.value(dab, 'dab', 'is no stamp');
  }
  drawnByTheEngineAlone(surface.tileSize);
  final (:landing, :lays) = _layingOf(dab, stamp);
  final asked = _stampAsks(surface, landing, selection);
  if (asked == null) {
    return _materialized(surface, const []);
  }
  final landed = await EngineTileLedger.instance.landOnceTold(
    asked.asks,
    by: lays(asked.clip, selection?.maskOnEngine()).told,
    unput: unput,
  );
  return _materialized(
    surface,
    _placedOf(asked.coords, landed, surface.tileSize),
  );
}

/// [surface] with [tiles] put on it, and the tiles they change: what one
/// landing leaves of a surface.
BrushSurfaceMaterialization _materialized(
  BitmapSurface surface,
  List<PlacedTile> tiles,
) {
  final coords = [for (final tile in tiles) tile.coord]
    ..sort(TileCoord.compareRowMajor);
  return BrushSurfaceMaterialization(
    surface: coords.isEmpty ? surface : surface.putMaterializedTiles(tiles),
    dirtyTiles: coords.isEmpty ? DirtyTileSet.empty() : DirtyTileSet(coords),
  );
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
  final (:landing, :lays) = _layingOf(dab, stamp);
  return _stampOnEngine(surface, landing, selection, lays);
}

/// Where [dab]'s [stamp] lands, and how the engine lays it over the
/// `clip` of that it is handed, under the `mask` it is handed if any: a
/// picture, or a mask under its paint.
({DirtyRegion landing, _Lays Function(DirtyRegion clip, GpuMask? mask) lays})
_layingOf(BrushDab dab, BrushStampImage stamp) {
  final landing = stamp.landingRect(dab.center);
  final opacity = (dab.opacity * 65535).round();
  final mode = engineBlendModeOf(BrushBlendMode.color, erase: dab.erase);
  final ofMask = EngineStampPictures.madeOfMask(stamp);
  return (
    landing: landing,
    lays: (clip, mask) => ofMask == null
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

/// How the engine lays a stamp on the tiles asked, by either of its
/// doors: [waited] for, each tile's answer read in the call
/// ([EngineTileLedger.land]), or finished with no wait and [told]
/// ([EngineTileLedger.landOnceTold]).
typedef _Lays = ({LandedBy waited, FinishedBy told});

/// A stamp over [landing], what the pasteboard's wall leaves of it — a
/// selection dropped past the stage's edge keeps its pixels there —, laid
/// on [surface] as [lays] says for that `clip`, under [within]'s mask where
/// there is one: the tiles it changes, a blank one where none is left.
/// [lays] is asked only where something of the stamp can land.
List<PlacedTile> _stampOnEngine(
  BitmapSurface surface,
  DirtyRegion landing,
  SelectionClip? within,
  _Lays Function(DirtyRegion clip, GpuMask? mask) lays,
) {
  final asked = _stampAsks(surface, landing, within);
  if (asked == null) {
    return const [];
  }
  final landed = EngineTileLedger.instance.land(
    asked.asks,
    by: lays(asked.clip, within?.maskOnEngine()).waited,
    ofTheHand: true,
    compared: true,
  );
  return _placedOf(asked.coords, landed, surface.tileSize);
}

/// What a stamp over [landing] asks of [surface]: the `clip` of it the
/// pasteboard's wall leaves, and every tile that reaches — its `coords`,
/// and each as a landing asks for it (`asks`), over [surface]'s tile
/// there. Null where nothing of the stamp can land: past the wall, or
/// where [within] covers none of it.
({DirtyRegion clip, List<TileCoord> coords, List<TileAsk> asks})? _stampAsks(
  BitmapSurface surface,
  DirtyRegion landing,
  SelectionClip? within,
) {
  final clip = landing.intersection(surface.pasteboard.region);
  if (clip == null || !(within?.mayCover(clip) ?? true)) {
    return null;
  }
  final (:firstX, :lastX, :firstY, :lastY) = clip.tileRange(
    tileSize: surface.tileSize,
  );
  final coords = [
    for (var y = firstY; y <= lastY; y += 1)
      for (var x = firstX; x <= lastX; x += 1) TileCoord(x: x, y: y),
  ];
  return (
    clip: clip,
    coords: coords,
    asks: [
      for (final coord in coords)
        (column: coord.x, row: coord.y, under: surface.tileAt(coord)),
    ],
  );
}

/// The tiles a compared landing changed, each at its place among
/// [coords]: the one that [landed], a blank one where none is left.
List<PlacedTile> _placedOf(
  List<TileCoord> coords,
  List<LandedTile> landed,
  int tileSize,
) => [
  for (var at = 0; at < landed.length; at += 1)
    if (landed[at].change != GpuChange.same)
      (
        coord: coords[at],
        tile: landed[at].tile ?? BitmapTile.blank(size: tileSize),
      ),
];

/// [picture], its top-left pixel at [landing]'s, what of it lies within
/// [clip], as the engine lays it at [opacity] (65535 whole) in [mode],
/// under [mask] if any.
_Lays _picture(
  GpuStampPicture picture,
  DirtyRegion landing,
  DirtyRegion clip, {
  required int opacity,
  required int mode,
  required GpuMask? mask,
}) {
  final within = (
    clip.left,
    clip.top,
    clip.rightExclusive,
    clip.bottomExclusive,
  );
  return (
    waited: (pool, cel, asked) => appGpuStampLanding.land(
      appGpuComposite,
      pool,
      cel,
      picture,
      left: landing.left,
      top: landing.top,
      within: within,
      asks: asked,
      opacity: opacity,
      mode: mode,
      mask: mask,
    ),
    told: (pool, asked) => appGpuStampLanding.finished(
      appGpuComposite,
      pool,
      picture,
      left: landing.left,
      top: landing.top,
      within: within,
      asks: asked,
      opacity: opacity,
      mode: mode,
      mask: mask,
    ),
  );
}

/// A stamp [made] of a mask ([EngineStampPictures.ofMask]) — its box made
/// to the wall — as the engine lays it under its paint at [opacity] (65535
/// whole) in [mode], under [mask] if any.
_Lays _ofMask(
  StampOfMask made, {
  required int opacity,
  required int mode,
  required GpuMask? mask,
}) {
  final coverage = made.coverage();
  return (
    waited: (pool, cel, asked) => appGpuStampLanding.landMask(
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
    ),
    told: (pool, asked) => appGpuStampLanding.finishedMask(
      appGpuComposite,
      pool,
      coverage,
      paint: made.paint,
      whole: made.whole,
      asks: asked,
      opacity: opacity,
      mode: mode,
      mask: mask,
    ),
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
    ).waited,
    // A cel's texts laid: a picture made as its frame is, no hand's.
    ofTheHand: false,
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
  return _materialized(surface, tiles);
}
