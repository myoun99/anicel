import 'dart:math' as math;
import 'dart:typed_data';

/// How a CLIP STUDIO picture stands on the canvas — a dropped picture's
/// `ResizableImageInfo`, and a 2D camera folder's
/// `Camera2DResizableImageInfo`, which is the same 184 bytes, big-endian
/// (memory `csp-clip-format-notes` §4): the scale x · y at @40 · @48 (1 =
/// its own size), the turn in degrees at @56, the point the picture is
/// placed at ([x], [y]) at @64 · @72, and the point of the picture that
/// goes there — its pivot — at @80 · @88.
typedef ClipPlacement = ({
  double scaleX,
  double scaleY,
  double degrees,
  double x,
  double y,
  double pivotX,
  double pivotY,
});

/// [info]'s placement — null for none, or one too short to hold it.
ClipPlacement? clipPlacementOf(Uint8List? info) {
  if (info == null || info.length < 96) {
    return null;
  }
  final data = ByteData.sublistView(info);
  return (
    scaleX: data.getFloat64(40),
    scaleY: data.getFloat64(48),
    degrees: data.getFloat64(56),
    x: data.getFloat64(64),
    y: data.getFloat64(72),
    pivotX: data.getFloat64(80),
    pivotY: data.getFloat64(88),
  );
}

/// Where the picture's own point ([u], [v]) lands on the canvas under
/// [placement]: `(a·u + c·v + e, b·u + d·v + f)` with `a = cos·sx, b =
/// sin·sx, c = −sin·sy, d = cos·sy`, and `e`, `f` what puts the pivot on
/// the placed point. The canvas's y runs down, so a positive turn is
/// clockwise. MoArt holds this matrix to the four corners the info ends
/// with; the samples' 2D camera meets its corners by it (scale and move
/// only — none of them turns).
({double x, double y}) clipPlaced(ClipPlacement placement, double u, double v) {
  final (:a, :b, :c, :d) = _matrixOf(placement);
  final du = u - placement.pivotX;
  final dv = v - placement.pivotY;
  return (
    x: placement.x + a * du + c * dv,
    y: placement.y + b * du + d * dv,
  );
}

/// Whether [placement] only moves its picture — no scale, no turn.
bool clipPlacementOnlyMoves(ClipPlacement placement) {
  const exact = 1e-6;
  final (:a, :b, :c, :d) = _matrixOf(placement);
  return (a - 1).abs() < exact &&
      b.abs() < exact &&
      c.abs() < exact &&
      (d - 1).abs() < exact;
}

({double a, double b, double c, double d}) _matrixOf(ClipPlacement p) {
  final turn = p.degrees * math.pi / 180;
  return (
    a: math.cos(turn) * p.scaleX,
    b: math.sin(turn) * p.scaleX,
    c: -math.sin(turn) * p.scaleY,
    d: math.cos(turn) * p.scaleY,
  );
}
