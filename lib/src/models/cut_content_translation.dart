import 'camera_pose.dart';
import 'canvas_point.dart';
import 'canvas_size.dart';
import 'cut.dart';
import 'cut_camera.dart';
import 'drawing_guide.dart';
import 'layer.dart';
import 'property_track.dart';
import 'transform_track.dart';

/// D5 (R7): translates a cut's CANVAS-COORDINATE model data for a canvas
/// resize — the model half of "the picture moves, so everything pinned
/// to it moves too". The raster half is the store's one-pass blit; this
/// file owns camera keyframes, guides, layer transform poses and text
/// cel anchors. Zoom/scale/rotation stay untouched: a resize is a
/// crop/extend, never a scale (R19) — whether the camera should also
/// re-fit its zoom is a user decision, not this file's.
///
/// Two offsets, because the render math has two kinds of pinning:
///
///  * [dx]/[dy] — the CONTENT offset (where the pixels moved, already
///    rounded to the raster's whole-pixel blit so model and picture
///    stay in lockstep). Camera centres, guides, text anchors and
///    EXPLICIT transform anchors/positions move by this.
///  * [centreDx]/[centreDy] — the CANVAS CENTRE's own movement. A NULL
///    transform anchor re-reads as the canvas centre at draw time, so a
///    null-anchored pose renders as `q + position − centre`: keeping it
///    pinned to its picture takes `position += Δcentre`, NOT the
///    content offset (the two agree only for the centre resize anchor).
///    Exact at zoom 1 / rotation 0 for every resize anchor, and exact
///    at any zoom for the centre anchor; a null-anchored pose that is
///    BOTH scaled-or-rotated AND resized off-centre has no key-level
///    compensation (the correction is frame-dependent) — that corner is
///    named here rather than silently wrong.
CanvasPoint _translated(CanvasPoint point, double dx, double dy) =>
    CanvasPoint(x: point.x + dx, y: point.y + dy);

PropertyTrack<CanvasPoint> _translatedPointTrack(
  PropertyTrack<CanvasPoint> track,
  double dx,
  double dy,
) {
  if (track.isEmpty || (dx == 0 && dy == 0)) {
    return track;
  }
  return PropertyTrack(
    keys: {
      for (final entry in track.keys.entries)
        entry.key: entry.value.copyWith(
          value: _translated(entry.value.value, dx, dy),
        ),
    },
  );
}

/// How a resize moves what stands on the canvas: the content by (dx, dy),
/// and the canvas centre — what an unkeyed pose reads — by (centreDx,
/// centreDy).
typedef ResizeWalk = ({double dx, double dy, double centreDx, double centreDy});

/// A POSITION lane moved by [walk]'s (dx, dy) for a resize. EMPTY, it reads
/// [centre] — the canvas centre of the size it stood on, which walks by
/// [walk]'s (centreDx, centreDy); where that is not the lane's own move,
/// it is keyed first where it stood, or its pose walks off its picture.
///
/// 🗣️F-362 (유저 2026-10-20): 「캔버스 크기 바꾸면 카메라도 이동해버림.
/// 소재는 기존 위치에 존재하는게 규칙 … 키를 찍어서라도 이동시켜두도록」 —
/// After Effects' Composition Settings anchor 「layers to a corner or edge
/// of the composition as it is resized」, the camera among them. ⛔No
/// tolerance: a centre resize by an odd size rounds the content half a
/// pixel off the centre, and the pose stays on the content there too.
PropertyTrack<CanvasPoint> _translatedPositionLane(
  PropertyTrack<CanvasPoint> lane, {
  required CanvasPoint centre,
  required ResizeWalk walk,
}) {
  final (:dx, :dy, :centreDx, :centreDy) = walk;
  final stood = lane.isEmpty && (dx != centreDx || dy != centreDy)
      ? pathLaneKeyed(lane, 0, centre)
      : lane;
  return _translatedPointTrack(stood, dx, dy);
}

/// Every camera keyframe centre moves with the content — THROUGH THE
/// LANES, never the pose facade: `CutCamera(keyframes:)` rebuilds all
/// lanes from resolved poses, which linearizes holds, erases key names
/// and synthesizes keys at the union frames (adversarial review). Only
/// the position lane (and an explicit anchor lane) is touched; scale,
/// rotation and opacity lanes pass through untouched. An UNKEYED position
/// reads [defaultCameraPoseFor] on [from] ([_translatedPositionLane]).
CutCamera translateCutCamera(
  CutCamera camera,
  ResizeWalk walk, {
  required CanvasSize from,
}) {
  final track = camera.track;
  final position = _translatedPositionLane(
    track.position,
    centre: defaultCameraPoseFor(from).center,
    walk: walk,
  );
  final anchorPoint = _translatedPointTrack(
    track.anchorPoint,
    walk.dx,
    walk.dy,
  );
  if (identical(position, track.position) &&
      identical(anchorPoint, track.anchorPoint)) {
    return camera;
  }
  return CutCamera.fromTrack(
    track.copyWith(position: position, anchorPoint: anchorPoint),
  );
}

GuideAxis _translatedAxis(GuideAxis axis, double dx, double dy) =>
    axis.copyWith(origin: _translated(axis.origin, dx, dy));

GuideLine _translatedLine(GuideLine line, double dx, double dy) =>
    line.copyWith(a: _translated(line.a, dx, dy), b: _translated(line.b, dx, dy));

VanishingPoint _translatedVanishingPoint(
  VanishingPoint point,
  double dx,
  double dy,
) => switch (point) {
  VanishingPointAt(:final point) => VanishingPointAt(
    _translated(point, dx, dy),
  ),
  // A direction is a vector, not a place — it does not move.
  VanishingPointTowards() => point,
  VanishingPointFromLines(:final first, :final second) =>
    VanishingPointFromLines(
      _translatedLine(first, dx, dy),
      _translatedLine(second, dx, dy),
    ),
};

GuideShape _translatedShape(GuideShape shape, double dx, double dy) =>
    switch (shape) {
      SymmetryShape() => shape.copyWith(
        axis: _translatedAxis(shape.axis, dx, dy),
      ),
      PerspectiveShape() => shape.copyWith(
        eyeLevel: _translatedAxis(shape.eyeLevel, dx, dy),
        vanishingPoints: [
          for (final point in shape.vanishingPoints)
            _translatedVanishingPoint(point, dx, dy),
        ],
      ),
    };

/// Every guide's canvas-coordinate geometry moves with the content — the
/// resize command's own doc names guides as the reason 겸용 siblings
/// resize together ("an axis stored in canvas coordinates means two
/// different places when the canvases disagree"), yet the old command
/// never moved them.
CutGuides translateCutGuides(CutGuides guides, double dx, double dy) {
  if (guides.isEmpty || (dx == 0 && dy == 0)) {
    return guides;
  }
  return guides.copyWith(
    guides: [
      for (final guide in guides.guides)
        guide.copyWith(shape: _translatedShape(guide.shape, dx, dy)),
    ],
  );
}

/// A layer's canvas-coordinate model data moves with its picture:
///
///  * EXPLICIT anchor keys and their position keys move by the content
///    offset — the pose subtracts the anchor, so translating both keeps
///    the render identical at every zoom.
///  * A NULL anchor re-reads as the canvas centre, so the position keys
///    move by Δcentre instead (see the file doc).
///  * An UNKEYED position under an explicit anchor reads
///    [layerIdentityPose] on [from] ([_translatedPositionLane]).
///  * The file a REFERENCE row shows stands where its reference fx puts its
///    centre on the canvas (I-68), and that moves by the content offset
///    like a camera's centre: the picture keeps its place among the
///    drawings, and a file swapped in or laid again afterwards stands there
///    too (유저 2026-10-10 「캔버스 크기 변경 … 가」 — 기준점대로).
///
/// 🪦A bullet before the reference's moved a TEXT cel's canvas-coordinate
/// anchor with its picture. The TEXT row went with F-154 and its payload
/// with the save format's floor (`anicelOldestReadFormatVersion`): nothing
/// holds one.
Layer translateLayerForResize(
  Layer layer, {
  required CanvasSize from,
  required double dx,
  required double dy,
  required double centreDx,
  required double centreDy,
}) {
  final track = layer.transformTrack;
  final hasExplicitAnchor = track.anchorPoint.isNotEmpty;
  final positionDx = hasExplicitAnchor ? dx : centreDx;
  final positionDy = hasExplicitAnchor ? dy : centreDy;
  final reference = layer.mediaReference;
  if (track.position.isEmpty &&
      track.anchorPoint.isEmpty &&
      reference == null) {
    return layer;
  }
  return layer.copyWith(
    transformTrack: track.copyWith(
      position: _translatedPositionLane(
        track.position,
        centre: layerIdentityPose(from).center,
        walk: (
          dx: positionDx,
          dy: positionDy,
          centreDx: centreDx,
          centreDy: centreDy,
        ),
      ),
      anchorPoint: _translatedPointTrack(track.anchorPoint, dx, dy),
    ),
    // Its keys and where its file is laid stand on the same canvas (F-374),
    // so they move with it — the cel's pixels move with the drawings.
    mediaReference: reference?.copyWith(
      pose: reference.pose.copyWith(
        center: _translated(reference.pose.center, dx, dy),
      ),
      fx: reference.fx.copyWith(
        position: _translatedPointTrack(reference.fx.position, dx, dy),
      ),
      laid: reference.laid.copyWith(
        center: _translated(reference.laid.center, dx, dy),
      ),
    ),
  );
}

/// The whole cut's model follow for a resize: camera, guides and every
/// layer's canvas coordinates, in one immutable copy. The canvas size
/// itself is the caller's write (it differs per call site).
Cut translateCutContentModel(
  Cut cut, {
  required double dx,
  required double dy,
  required double centreDx,
  required double centreDy,
}) {
  if (dx == 0 && dy == 0 && centreDx == 0 && centreDy == 0) {
    return cut;
  }
  return cut.copyWith(
    camera: translateCutCamera(
      cut.camera,
      (dx: dx, dy: dy, centreDx: centreDx, centreDy: centreDy),
      from: cut.canvasSize,
    ),
    guides: translateCutGuides(cut.guides, dx, dy),
    layers: [
      for (final layer in cut.layers)
        translateLayerForResize(
          layer,
          from: cut.canvasSize,
          dx: dx,
          dy: dy,
          centreDx: centreDx,
          centreDy: centreDy,
        ),
    ],
  );
}
