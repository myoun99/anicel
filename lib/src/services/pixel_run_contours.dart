import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:gpu_engine/gpu_engine.dart' show contoursOfRuns;

import '../models/canvas_point.dart';

/// The closed contours of the pixels [rows] hold — row `r` is the canvas
/// row `top + r`, its `[start, end, …]` columns counted from [left], in a
/// box [width] pixels wide — on the pixel grid, in CANVAS space.
///
/// One walk for every outline drawn around pixels: a selection's committed
/// ants (`CanvasSelectionRegion.pixelOutline`) and the range a fill held
/// down will cover (I-160). ↩️It was the selection's own until the fill
/// needed the same outline of its flood.
///
/// The contours are CLOSED and walk consistently, so a dash phase runs
/// around a whole component (and around a hole), and a fill of them carves
/// the holes out under the default winding. ⛔A contour starts where the
/// scan first met it: the dashes stay put.
///
/// 🚨WALKED BY THE ENGINE (card pixel-ants-cost-a-frame-while-moving,
/// 2026-11-16): `rust/src/kernels/mask/contours.rs`, step for step the walk
/// this file held. ↩️It was walked here in Dart — 2.4 ms of the UI's frame
/// (5.2 at p90) for a 4K lasso a transform's drag maps anew every frame, on
/// the Surface in the profile app. ⛔Not off the frame: the box and the
/// pixels move in the frame the drag asks, and an outline answered a frame
/// later would stand where they no longer are (관제 11-16 ⓐ).
PixelContours pixelRunContours(
  List<List<int>> rows, {
  required int left,
  required int top,
  required int width,
}) {
  if (width <= 0 || rows.isEmpty) {
    return PixelContours.none;
  }
  final offsets = Uint32List(rows.length + 1);
  for (var row = 0; row < rows.length; row += 1) {
    offsets[row + 1] = offsets[row] + rows[row].length;
  }
  final ends = Uint32List(offsets[rows.length]);
  for (var row = 0; row < rows.length; row += 1) {
    ends.setAll(offsets[row], rows[row]);
  }
  final (:starts, :points) = contoursOfRuns(
    offsets: offsets,
    ends: ends,
    width: width,
  );
  for (var at = 0; at < points.length; at += 2) {
    points[at] += left;
    points[at + 1] += top;
  }
  return PixelContours._(starts, points);
}

/// The contours [pixelRunContours] walks, kept as the engine gave them:
/// contour `c`'s points are `points[2 * starts[c] .. 2 * starts[c + 1]]`, a
/// column and a line in turn, in CANVAS pixels.
///
/// 🚨NO OBJECT A POINT (card pixel-ants-cost-a-frame-while-moving,
/// 2026-11-16): a 4K lasso's outline is twenty thousand points, and a
/// transform's drag walks a new one every frame. Each made a [CanvasPoint]
/// and then an [ui.Offset] to lay the path was forty thousand objects made
/// and dropped a frame — 0.44 ms making the points alone (the Surface,
/// profile), the collections they call besides. The path is laid from the
/// ints, once ([path]); a reader that moves it to the screen transforms
/// that path (`Path.transform`) rather than mapping a point at a time.
final class PixelContours {
  PixelContours._(this._starts, this._points);

  /// No contour.
  static final none = PixelContours._(Uint32List(1), Int32List(0));

  final Uint32List _starts;
  final Int32List _points;

  /// How many points the contours hold, all told.
  int get pointCount => _points.length ~/ 2;

  /// Every contour as one closed path, in CANVAS space — laid once, on the
  /// first ask.
  ///
  /// The default winding, as the walk winds a hole against its component:
  /// a fill of it carves the holes out.
  late final ui.Path path = _laid();

  ui.Path _laid() {
    final path = ui.Path();
    for (var contour = 0; contour + 1 < _starts.length; contour += 1) {
      final end = _starts[contour + 1];
      var at = _starts[contour];
      if (at == end) {
        continue;
      }
      path.moveTo(_points[2 * at].toDouble(), _points[2 * at + 1].toDouble());
      for (at += 1; at < end; at += 1) {
        path.lineTo(
          _points[2 * at].toDouble(),
          _points[2 * at + 1].toDouble(),
        );
      }
      path.close();
    }
    return path;
  }

  /// The contours a point each — for the tests that pin which points the
  /// walk keeps; the straight-run merge shows only in the count.
  List<List<CanvasPoint>> get points => [
    for (var contour = 0; contour + 1 < _starts.length; contour += 1)
      [
        for (var at = _starts[contour]; at < _starts[contour + 1]; at += 1)
          CanvasPoint(
            x: _points[2 * at].toDouble(),
            y: _points[2 * at + 1].toDouble(),
          ),
      ],
  ];
}
