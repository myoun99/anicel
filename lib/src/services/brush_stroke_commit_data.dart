import 'dart:typed_data';

import '../models/placed_tile.dart';
import '../models/bitmap_surface.dart';
import '../models/brush_blend_mode.dart';
import '../models/brush_dab.dart';
import '../models/dirty_region.dart';

/// A finished stroke handed from the interactive canvas to the commit route.
///
/// [sourceDabs] remain the durable source of truth. [strokePixels] /
/// [strokeBounds], when present, carry the stroke already rasterized
/// incrementally while drawing (`BrushLiveStrokeRasterizer`, straight-alpha
/// RGBA, BOUNDS-LOCAL: row-major with stride = the bounds width): the
/// commit then composites this buffer over the existing artwork in one
/// pass instead of re-running the per-dab loop, which both removes the
/// pen-up hiccup and guarantees the committed pixels are exactly the
/// pixels that were on screen while drawing.
///
/// [blendMode] (BB-1, R26 #9) is the stroke's BRUSH blend — carried here
/// so a history REDO reproduces the same pixels no matter what the tool
/// state says by then.
/// [promotedTiles] (promotion round) go one step further: the live
/// overlay already blended the stroke into FINISHED tiles — the exact
/// bytes the commit would compute — against [promotedBase]. When the cel
/// surface is still that same object, the commit is a tile PUT: no
/// re-blend, no re-decode, and the images the user watched hand over to
/// the new tiles. If the surface moved underneath (anything committed in
/// between), the commit falls back to the dab route and the promotion is
/// simply ignored — correctness never depends on the fast path.
class BrushStrokeCommitData {
  BrushStrokeCommitData({
    required List<BrushDab> sourceDabs,
    this.strokePixels,
    this.strokeBounds,
    this.blendMode = BrushBlendMode.color,
    this.strokeOpacity = 1,
    this.promotedBase,
    this.promotedTiles,
  }) : sourceDabs = List<BrushDab>.unmodifiable(sourceDabs);

  final List<BrushDab> sourceDabs;
  final Uint8List? strokePixels;
  final DirtyRegion? strokeBounds;
  final BrushBlendMode blendMode;

  /// F-12: the stroke's opacity CEILING — carried here for the same reason
  /// [blendMode] is, so a REDO reproduces the same pixels however the tool
  /// has been set since.
  ///
  /// ⚠️A stamp route (the bucket, a shape fill, a pasted piece) leaves this
  /// at 1 and keeps its opacity on its DAB: one stamp accumulates with
  /// nothing, so there is nothing for a ceiling to cap.
  final double strokeOpacity;

  /// The cel surface the promoted tiles were blended against.
  final BitmapSurface? promotedBase;

  /// Finished tiles ready to adopt (only the coordinates whose pixels
  /// actually differ from [promotedBase]).
  final List<PlacedTile>? promotedTiles;
}
