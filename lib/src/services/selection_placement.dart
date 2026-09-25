import '../models/brush_dab.dart';
import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import 'canvas_selection.dart' show transformStampDab;
import 'layer_pose_matrix.dart' show LayerPoseSample;
import 'selection_affine.dart';

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
/// crosses by moving the stamp's centre ([transformStampDab]'s free path),
/// so its bytes come back exactly as they went; only a turned or scaled row
/// pays a resample each way.
///
/// ⛔Not the transform carried into the artwork instead (P⁻¹·A·P): that is
/// exact for a move, but a MESH warp's grid is laid over the box on the
/// canvas and has no image in the artwork to be carried to.
///
/// [placement] null — an unplaced row, nearly every row — hands the stamp
/// back untouched.
BrushDab stampOnCanvas(
  BrushDab stamp,
  LayerPoseSample? placement,
  CanvasSize canvasSize,
) => placement == null
    ? stamp
    : transformStampDab(stamp, _artworkToCanvas(placement, canvasSize));

/// [stampOnCanvas] run backwards: a stamp the canvas holds, put back into
/// the row's own artwork where the row's placement shows it.
BrushDab stampInArtwork(
  BrushDab stamp,
  LayerPoseSample? placement,
  CanvasSize canvasSize,
) => placement == null
    ? stamp
    : transformStampDab(stamp, _canvasToArtwork(placement, canvasSize));

/// The placement as the box's own affine: the anchor (the canvas centre
/// unless a lane keys one) lands on `pose.center`, scaled by `pose.zoom`
/// and turned by `pose.rotationDegrees` about it — `layerPoseMatrix`'s
/// plane part, which [SelectionAffine] spells as a scale about [pivot]
/// followed by a shift.
SelectionAffine _artworkToCanvas(
  LayerPoseSample placement,
  CanvasSize canvasSize,
) {
  final anchor = _anchorOf(placement, canvasSize);
  final pose = placement.pose;
  return SelectionAffine(
    pivot: anchor,
    sx: pose.zoom,
    sy: pose.zoom,
    rotationDegrees: pose.rotationDegrees,
    tx: pose.center.x - anchor.x,
    ty: pose.center.y - anchor.y,
  );
}

SelectionAffine _canvasToArtwork(
  LayerPoseSample placement,
  CanvasSize canvasSize,
) {
  final anchor = _anchorOf(placement, canvasSize);
  final pose = placement.pose;
  return SelectionAffine(
    pivot: pose.center,
    sx: 1 / pose.zoom,
    sy: 1 / pose.zoom,
    rotationDegrees: -pose.rotationDegrees,
    tx: anchor.x - pose.center.x,
    ty: anchor.y - pose.center.y,
  );
}

CanvasPoint _anchorOf(LayerPoseSample placement, CanvasSize canvasSize) =>
    placement.anchorPoint ??
    CanvasPoint(x: canvasSize.width / 2, y: canvasSize.height / 2);
