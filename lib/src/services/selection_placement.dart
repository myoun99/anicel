import '../models/brush_dab.dart';
import 'canvas_selection.dart' show carryStampDab;
import 'layer_pose_matrix.dart' show LayerPlacement, canvasToArtwork;

/// A posed row's pixels carried onto the canvas, and back.
///
/// 🚨a-marquee-on-a-posed-row (found 2026-09-25, measured): a selection is
/// drawn on the CANVAS, and so is everything the transform box does to it,
/// but a row's pixels are its own ARTWORK, which the row's placement — the
/// one the stack paints it with (`layerPlacementAt`) — lays on the canvas.
/// With the row moved right by 100, a marquee around the picture the user
/// SAW lifted the empty artwork under the marquee instead, and nothing
/// moved.
///
/// ★So a lift crosses into the canvas once and a landing crosses back once,
/// and the box between them — move, scale, rotate, perspective, mesh — runs
/// in the one space it was written for. A row placed by a translation alone
/// crosses by moving the stamp's centre ([carryStampDab]'s free path), so
/// its bytes come back exactly as they went; only a turned or scaled row
/// pays a resample each way.
///
/// ⛔Not the transform carried into the artwork instead (P⁻¹·A·P): that is
/// exact for a move, but a MESH warp's grid is laid over the box on the
/// canvas and has no image in the artwork to be carried to.
///
/// ↩️The crossing was the transform box's own affine, built from the pose's
/// numbers — its scale, its turn, its centre. A placement has none of
/// those to give ([LayerPlacement]): it crosses as the affine it is.
///
/// [placement] null — an unplaced row, nearly every row — hands the stamp
/// back untouched.
BrushDab stampOnCanvas(BrushDab stamp, LayerPlacement? placement) =>
    _carried(stamp, placement, ontoCanvas: true);

/// [stampOnCanvas] run backwards: a stamp the canvas holds, put back into
/// the row's own artwork where the row's placement shows it.
BrushDab stampInArtwork(BrushDab stamp, LayerPlacement? placement) =>
    _carried(stamp, placement, ontoCanvas: false);

BrushDab _carried(
  BrushDab stamp,
  LayerPlacement? placement, {
  required bool ontoCanvas,
}) {
  if (placement == null) {
    return stamp;
  }
  // A collapsed row shows nothing to carry — the backstop every reader of a
  // placement keeps ([canvasToArtwork]).
  final back = canvasToArtwork(placement);
  if (back == null) {
    return stamp;
  }
  return ontoCanvas
      ? carryStampDab(stamp, to: placement, from: back)
      : carryStampDab(stamp, to: back, from: placement);
}
