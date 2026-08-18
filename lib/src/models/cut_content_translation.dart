import 'dart:ui' show Offset;

import 'canvas_point.dart';
import 'cut.dart';
import 'cut_camera.dart';
import 'drawing_guide.dart';
import 'frame.dart';
import 'layer.dart';
import 'property_track.dart';

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
        entry.key: PropertyKey(
          _translated(entry.value.value, dx, dy),
          interpolation: entry.value.interpolation,
          name: entry.value.name,
        ),
    },
  );
}

/// Every camera keyframe centre moves with the content — THROUGH THE
/// LANES, never the pose facade: `CutCamera(keyframes:)` rebuilds all
/// lanes from resolved poses, which linearizes holds, erases key names
/// and synthesizes keys at the union frames (adversarial review). Only
/// the position lane (and an explicit anchor lane) is touched; scale,
/// rotation and opacity lanes pass through untouched. An empty track
/// needs nothing: the default pose recomputes the canvas centre itself.
CutCamera translateCutCamera(CutCamera camera, double dx, double dy) {
  if (camera.isEmpty || (dx == 0 && dy == 0)) {
    return camera;
  }
  return CutCamera.fromTrack(
    camera.track.copyWith(
      position: _translatedPointTrack(camera.track.position, dx, dy),
      anchorPoint: _translatedPointTrack(camera.track.anchorPoint, dx, dy),
    ),
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
///  * TEXT cel anchors ([Frame.textContent]'s canvas-coordinate
///    position) move by the content offset — the baked raster is a
///    projection of them, and the next re-bake (which the resize itself
///    triggers) would otherwise snap the text back to the pre-resize
///    spot (adversarial review).
Layer translateLayerForResize(
  Layer layer, {
  required double dx,
  required double dy,
  required double centreDx,
  required double centreDy,
}) {
  final track = layer.transformTrack;
  final hasExplicitAnchor = track.anchorPoint.isNotEmpty;
  final positionDx = hasExplicitAnchor ? dx : centreDx;
  final positionDy = hasExplicitAnchor ? dy : centreDy;
  final nextTrack =
      track.position.isEmpty && track.anchorPoint.isEmpty
      ? track
      : track.copyWith(
          position: _translatedPointTrack(
            track.position,
            positionDx,
            positionDy,
          ),
          anchorPoint: _translatedPointTrack(track.anchorPoint, dx, dy),
        );

  var framesChanged = false;
  final nextFrames = <Frame>[];
  for (final frame in layer.frames) {
    final content = frame.textContent;
    final position = content?.position;
    if (content == null || position == null || (dx == 0 && dy == 0)) {
      nextFrames.add(frame);
      continue;
    }
    framesChanged = true;
    nextFrames.add(
      frame.copyWith(
        textContent: content.copyWith(
          position: Offset(position.dx + dx, position.dy + dy),
        ),
      ),
    );
  }

  if (identical(nextTrack, layer.transformTrack) && !framesChanged) {
    return layer;
  }
  return layer.copyWith(
    transformTrack: nextTrack,
    frames: framesChanged ? nextFrames : layer.frames,
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
    camera: translateCutCamera(cut.camera, dx, dy),
    guides: translateCutGuides(cut.guides, dx, dy),
    layers: [
      for (final layer in cut.layers)
        translateLayerForResize(
          layer,
          dx: dx,
          dy: dy,
          centreDx: centreDx,
          centreDy: centreDy,
        ),
    ],
  );
}
