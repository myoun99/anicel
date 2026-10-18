import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../core/turn_trig.dart';
import '../models/cel_text.dart';

/// THE FRAME A TEXT IS SET IN: its origin at the text's anchor, its x along
/// the lines and its y down them — LEANED, then MIRRORED, then TURNED as the
/// text is ([CelTextContent.skewDegrees] · [CelTextContent.flipped] ·
/// [CelTextContent.rotationDegrees]). A point of the frame stands on the
/// canvas at the anchor plus [onCanvas] of it.
///
/// ⛔THE ONE PLACE A TEXT'S FRAME IS WORKED OUT — what draws the text
/// ([applyTo] · [applyToMatrix]), what asks a press where on it it fell
/// ([toLocal]), and what reads a hand's travel along its own lines
/// ([inFrame]) all stand on it, so none of them can stand the text where
/// another does not.
class CelTextFrame {
  factory CelTextFrame.of(CelTextContent content) {
    final turn = PlaneTurn(content.rotationDegrees);
    final mirror = content.flipped ? -1.0 : 1.0;
    // As italic letters lean: a point stands further along the lines the
    // HIGHER it stands, and the frame's y runs down.
    final lean = content.skewDegrees == 0
        ? 0.0
        : -math.tan(content.skewDegrees * math.pi / 180);
    // The two steps leaned and mirrored, then turned as a point is
    // ([PlaneTurn]).
    final along = turn.apply(mirror, 0);
    final down = turn.apply(mirror * lean, 1);
    return CelTextFrame._(
      anchor: ui.Offset(content.anchor.x, content.anchor.y),
      xStep: ui.Offset(along.x, along.y),
      yStep: ui.Offset(down.x, down.y),
      radians: content.rotationDegrees * math.pi / 180,
      mirror: mirror,
      lean: lean,
    );
  }

  const CelTextFrame._({
    required this.anchor,
    required this.xStep,
    required this.yStep,
    required double radians,
    required double mirror,
    required double lean,
  }) : _radians = radians,
       _mirror = mirror,
       _lean = lean;

  /// The frame's origin on the canvas: the text's anchor.
  final ui.Offset anchor;

  /// One step along the frame's x — along the lines — on the canvas.
  final ui.Offset xStep;

  /// One step along the frame's y — down the lines — on the canvas.
  final ui.Offset yStep;

  final double _radians;

  /// -1 where the text is mirrored, and 1 where it is not: how much of the
  /// canvas a square of the frame covers — a lean and a turn keep its area
  /// — which is why [inFrame] divides by it and not by a determinant
  /// worked out of the steps, which a turn leaves a hair off one.
  final double _mirror;

  /// The lean as a run along the lines per step down them.
  final double _lean;

  /// [step], a displacement in the frame, on the canvas.
  ui.Offset onCanvas(ui.Offset step) => ui.Offset(
    xStep.dx * step.dx + yStep.dx * step.dy,
    xStep.dy * step.dx + yStep.dy * step.dy,
  );

  /// [travel], a displacement on the canvas, in the frame.
  ui.Offset inFrame(ui.Offset travel) => ui.Offset(
    (travel.dx * yStep.dy - yStep.dx * travel.dy) * _mirror,
    (xStep.dx * travel.dy - travel.dx * xStep.dy) * _mirror,
  );

  /// [local], a point of the frame, on the canvas.
  ui.Offset toCanvas(ui.Offset local) => anchor + onCanvas(local);

  /// [point], a point of the canvas, in the frame.
  ui.Offset toLocal(ui.Offset point) => inFrame(point - anchor);

  /// Sets [canvas] — which is in canvas space — up for drawing in the
  /// frame, in the canvas's own steps. The caller saves and restores
  /// around it.
  void applyTo(ui.Canvas canvas) {
    canvas.translate(anchor.dx, anchor.dy);
    if (_radians != 0) {
      canvas.rotate(_radians);
    }
    if (_mirror < 0) {
      canvas.scale(-1, 1);
    }
    if (_lean != 0) {
      canvas.skew(_lean, 0);
    }
  }

  /// Carries [matrix] — which is in canvas space — into the frame, by the
  /// same steps [applyTo] takes.
  void applyToMatrix(Matrix4 matrix) {
    matrix.translateByDouble(anchor.dx, anchor.dy, 0, 1);
    if (_radians != 0) {
      matrix.rotateZ(_radians);
    }
    if (_mirror < 0) {
      matrix.scaleByDouble(-1, 1, 1, 1);
    }
    if (_lean != 0) {
      matrix.multiply(Matrix4.identity()..setEntry(0, 1, _lean));
    }
  }
}
