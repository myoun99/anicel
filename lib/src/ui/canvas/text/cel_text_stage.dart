import 'dart:ui' show Offset;

import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../../../models/canvas_point.dart';
import '../../../models/canvas_size.dart';
import '../../../models/canvas_viewport.dart';
import '../../../models/pasteboard_bounds.dart';
import '../../../services/layer_pose_matrix.dart';
import '../../../services/viewport_transform_matrix.dart';
import '../canvas_viewport_offset.dart';

/// WHERE A CEL'S TEXTS MEET THE SCREEN (R9-rest): the panel's view of the
/// canvas, and the pose the row is shown in.
///
/// A text's numbers are the cel's own — its ARTWORK, the pixels as they are
/// stored — and a row can be shown posed (a transform lane), so a press on
/// the panel is taken back through the view AND the pose before it is asked
/// of a text, and a text's box comes out through both before it is drawn
/// (the law every tool that reaches a posed row's pixels keeps —
/// a-marquee-on-a-posed-row, 2026-09-25).
class CelTextStage {
  const CelTextStage({
    required this.viewport,
    required this.canvasSize,
    required this.pose,
  });

  final CanvasViewport viewport;
  final CanvasSize canvasSize;

  /// How the row is shown; null for a row shown as it is drawn.
  final LayerPoseSample? pose;

  /// [local], a point of the panel, on the row's artwork — null where the
  /// pose cannot be undone (a backstop: no pose the model holds collapses a
  /// row).
  Offset? artworkAt(Offset local) {
    final canvas = viewport.viewportOffsetToCanvas(local);
    final pose = this.pose;
    final artwork = pose == null
        ? canvas
        : canvasToArtwork(pose, canvasSize)?.apply(canvas);
    return artwork == null ? null : Offset(artwork.x, artwork.y);
  }

  /// [artwork], a point of the row's artwork, on the panel.
  Offset onPanel(Offset artwork) {
    final point = CanvasPoint(x: artwork.dx, y: artwork.dy);
    final pose = this.pose;
    return viewport.canvasToViewportOffset(
      pose == null ? point : artworkToCanvas(pose, canvasSize).apply(point),
    );
  }

  /// The artwork's own frame on the panel — for what is laid out or drawn
  /// in artwork pixels.
  Matrix4 get artworkOnPanel {
    final view = viewportTransformMatrix(viewport);
    final pose = this.pose;
    return pose == null
        ? view
        : view.multiplied(
            layerPoseMatrix(
              pose.pose,
              canvasSize,
              anchorPoint: pose.anchorPoint,
            ),
          );
  }

  /// Whether [local], a point of the panel, is on the pasteboard — off it a
  /// press is nobody's (F-222-box-Q6).
  bool onStage(Offset local) {
    final canvas = viewport.viewportOffsetToCanvas(local);
    return canvasSize.containsPasteboardPoint(x: canvas.x, y: canvas.y);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelTextStage &&
          other.viewport == viewport &&
          other.canvasSize == canvasSize &&
          other.pose == pose;

  @override
  int get hashCode => Object.hash(viewport, canvasSize, pose);
}
