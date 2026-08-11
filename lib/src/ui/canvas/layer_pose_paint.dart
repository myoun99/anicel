import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/widgets.dart' show Matrix4;

import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/drawing_guide.dart';
import '../../models/transform_track.dart';
import '../../services/guide_geometry.dart';
import 'viewport_canvas_transform.dart';

/// A layer's resolved GEOMETRIC transform at one frame: the shared pose
/// (position/scale/rotation) plus the optional anchor point (null = the
/// canvas center, the historical default). Animated opacity rides
/// separately — it multiplies paint alpha, not geometry.
typedef LayerPoseSample = ({TransformPose pose, CanvasPoint? anchorPoint});

/// The matrix [applyLayerPoseTransform] applies — artwork space → posed
/// canvas space: the artwork's ANCHOR POINT (canvas center unless the
/// anchor-point lane keys one) lands on `pose.center`, scaled by
/// `pose.zoom` and rotated clockwise by `pose.rotationDegrees` about that
/// point. The identity pose maps to the identity matrix by construction.
/// [rasterScale] adapts the same canvas-space pose to a scaled raster
/// (playback quality tiers).
Matrix4 layerPoseMatrix(
  TransformPose pose,
  CanvasSize canvasSize, {
  CanvasPoint? anchorPoint,
  double rasterScale = 1,
}) {
  final anchorX = (anchorPoint?.x ?? canvasSize.width / 2) * rasterScale;
  final anchorY = (anchorPoint?.y ?? canvasSize.height / 2) * rasterScale;
  return Matrix4.translationValues(
      pose.center.x * rasterScale,
      pose.center.y * rasterScale,
      0,
    ).multiplied(Matrix4.rotationZ(pose.rotationDegrees * math.pi / 180))
    ..multiply(Matrix4.diagonal3Values(pose.zoom, pose.zoom, 1))
    ..multiply(Matrix4.translationValues(-anchorX, -anchorY, 0));
}

/// Applies a layer's transform pose to [canvas] before its image draws at
/// the origin — see [layerPoseMatrix] for the mapping.
///
/// EVERY composite route shares this one function — playback composites,
/// camera renders (export/thumbnails) and the editing canvas's layer
/// stack — so a transformed layer looks byte-identical everywhere
/// (three-route parity discipline).
void applyLayerPoseTransform(
  Canvas canvas,
  TransformPose pose,
  CanvasSize canvasSize, {
  CanvasPoint? anchorPoint,
  double rasterScale = 1,
}) {
  canvas.transform(
    layerPoseMatrix(
      pose,
      canvasSize,
      anchorPoint: anchorPoint,
      rasterScale: rasterScale,
    ).storage,
  );
}

/// The composition (outer ∘ inner) of two pose samples as ONE sample
/// anchored on the canvas center. Poses are similarities (translate ·
/// rotate · uniform scale), so the product is exactly representable:
/// zooms multiply, rotations add, and the composed center is wherever the
/// combined map sends the canvas center. Lets the CUT-level pose (the
/// storyboard V-row fx, R9-B) stack over a layer's own pose in the editing
/// canvas's SINGLE draw-through wrap — one Transform, one hit-test inverse.
LayerPoseSample composeLayerPoseSamples(
  LayerPoseSample outer,
  LayerPoseSample inner,
  CanvasSize canvasSize,
) {
  final matrix =
      layerPoseMatrix(
        outer.pose,
        canvasSize,
        anchorPoint: outer.anchorPoint,
      )..multiply(
        layerPoseMatrix(inner.pose, canvasSize, anchorPoint: inner.anchorPoint),
      );
  final s = matrix.storage;
  final cx = canvasSize.width / 2;
  final cy = canvasSize.height / 2;
  return (
    pose: TransformPose(
      center: CanvasPoint(
        x: s[0] * cx + s[4] * cy + s[12],
        y: s[1] * cx + s[5] * cy + s[13],
      ),
      zoom: outer.pose.zoom * inner.pose.zoom,
      rotationDegrees: outer.pose.rotationDegrees + inner.pose.rotationDegrees,
    ),
    anchorPoint: null,
  );
}

/// The SCREEN-space wrap matrix for a widget that already renders artwork
/// under [viewport]: `V · P · V⁻¹` — wrapping the interactive brush view in
/// `Transform(transform: ...)` with this matrix shows the active layer
/// POSED exactly like every composite route, while Flutter's hit testing
/// routes pointers through the inverse, so strokes record in original
/// artwork coordinates (draw-through: drawing on what you see lands where
/// the composite shows it).
Matrix4 layerPoseViewportWrapMatrix(
  TransformPose pose,
  CanvasSize canvasSize,
  CanvasViewport viewport, {
  CanvasPoint? anchorPoint,
}) {
  return viewportTransformMatrix(viewport).multiplied(
    layerPoseMatrix(pose, canvasSize, anchorPoint: anchorPoint),
  )..multiply(viewportInverseTransformMatrix(viewport));
}

/// [guides] moved out of CANVAS space and into the ARTWORK space of a layer
/// posed by [sample].
///
/// The counterpart of [layerPoseViewportWrapMatrix]: that one puts the
/// artwork on screen through the pose, and Flutter's hit testing brings
/// pointers back the other way, so a stroke on a posed layer records in the
/// layer's own coordinates. Guides live in canvas space, so they have to
/// make the same trip or the axis will sit where the pen is not.
///
/// Built from [layerPoseMatrix] rather than from the pose's numbers so
/// there is one piece of pose math in the app, not two that can drift.
/// Returns [guides] unchanged for a null or singular pose — a zero zoom
/// collapses the layer to nothing, and there is no artwork space to speak
/// of then.
CutGuides guidesInArtworkSpace(
  CutGuides guides,
  LayerPoseSample? sample,
  CanvasSize canvasSize,
) {
  if (sample == null || guides.isEmpty) return guides;
  final matrix = layerPoseMatrix(
    sample.pose,
    canvasSize,
    anchorPoint: sample.anchorPoint,
  );
  if (matrix.invert() == 0) return guides;
  final inverse = matrix.storage;
  return mapGuides(
    guides,
    GuideTransform(
      inverse[0],
      inverse[1],
      inverse[4],
      inverse[5],
      inverse[12],
      inverse[13],
    ),
  );
}
