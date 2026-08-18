import 'canvas_point.dart';
import 'cut.dart';
import 'cut_camera.dart';
import 'drawing_guide.dart';
import 'layer.dart';
import 'property_track.dart';

/// D5 (R7): translates a cut's CANVAS-COORDINATE model data by a resize
/// anchor's content offset — the model half of "the picture moves, so
/// everything pinned to it moves too". The raster half is the store's
/// one-pass blit; this file owns camera keyframes, guides and layer
/// transform poses. Zoom/scale/rotation stay untouched: a resize is a
/// crop/extend, never a scale (R19) — whether the camera should also
/// re-fit its zoom is a user decision, not this file's.
///
/// ⚠️Null anchor points (= canvas centre) are deliberately NOT
/// materialized: they re-read as the NEW canvas centre, which lands
/// exactly right for the default CENTER-anchored resize (old centre +
/// offset == new centre) and only drifts the scale/rotation pivot of a
/// null-anchored, scaled-or-rotated pose under a non-centre resize
/// anchor — a corner named in the round's review rather than silently
/// rewritten into explicit anchors (that would change what the anchor
/// lane displays).
CanvasPoint _translated(CanvasPoint point, double dx, double dy) =>
    CanvasPoint(x: point.x + dx, y: point.y + dy);

/// Every camera keyframe's centre moves with the content. An empty track
/// needs nothing: the default pose recomputes the canvas centre itself.
CutCamera translateCutCamera(CutCamera camera, double dx, double dy) {
  if (camera.isEmpty || (dx == 0 && dy == 0)) {
    return camera;
  }
  return CutCamera(
    keyframes: {
      for (final entry in camera.keyframes.entries)
        entry.key: entry.value.copyWith(
          center: _translated(entry.value.center, dx, dy),
        ),
    },
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

PropertyTrack<CanvasPoint> _translatedPointTrack(
  PropertyTrack<CanvasPoint> track,
  double dx,
  double dy,
) {
  if (track.isEmpty) {
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

/// A layer's transform POSITION keys and explicit ANCHOR keys move with
/// the content (see the file doc for why null anchors stay null).
Layer translateLayerTransform(Layer layer, double dx, double dy) {
  final track = layer.transformTrack;
  if ((track.position.isEmpty && track.anchorPoint.isEmpty) ||
      (dx == 0 && dy == 0)) {
    return layer;
  }
  return layer.copyWith(
    transformTrack: track.copyWith(
      position: _translatedPointTrack(track.position, dx, dy),
      anchorPoint: _translatedPointTrack(track.anchorPoint, dx, dy),
    ),
  );
}

/// The whole cut's model follow for a resize: camera, guides and every
/// layer's transform coordinates, in one immutable copy. The canvas size
/// itself is the caller's write (it differs per call site).
Cut translateCutContentModel(Cut cut, double dx, double dy) {
  if (dx == 0 && dy == 0) {
    return cut;
  }
  return cut.copyWith(
    camera: translateCutCamera(cut.camera, dx, dy),
    guides: translateCutGuides(cut.guides, dx, dy),
    layers: [
      for (final layer in cut.layers) translateLayerTransform(layer, dx, dy),
    ],
  );
}
