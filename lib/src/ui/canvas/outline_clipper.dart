import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

/// An outline on screen, as its corners in order — a conte picture's shot,
/// the canvas in it, a camera's frame a run is seen through: turned when
/// the view or the camera is.
///
/// ⛔Never a rect clipper, even for a square shot: a `CustomClipper<Rect>`
/// is the ink window's clip, and there is one (`one_sheet_ink_layer_test`).
class OutlineClipper extends CustomClipper<Path> {
  const OutlineClipper(this.corners);

  final List<Offset> corners;

  @override
  Path getClip(Size size) => Path()..addPolygon(corners, true);

  @override
  bool shouldReclip(OutlineClipper oldClipper) =>
      !listEquals(oldClipper.corners, corners);
}
