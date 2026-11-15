import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart' show contoursOfRuns;

import '../models/canvas_point.dart';

/// The closed contours of the pixels [rows] hold — row `r` is the canvas
/// row `top + r`, its `[start, end, …]` columns counted from [left], in a
/// box [width] pixels wide — on the pixel grid, in CANVAS space.
///
/// One walk for every outline drawn around pixels: a selection's committed
/// ants (`CanvasSelectionRegion.pixelOutlineIn`) and the range a fill held
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
List<List<CanvasPoint>> pixelRunContours(
  List<List<int>> rows, {
  required int left,
  required int top,
  required int width,
}) {
  if (width <= 0 || rows.isEmpty) {
    return <List<CanvasPoint>>[];
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
  return [
    for (var contour = 0; contour + 1 < starts.length; contour += 1)
      [
        for (var at = starts[contour]; at < starts[contour + 1]; at += 1)
          CanvasPoint(
            x: (left + points[2 * at]).toDouble(),
            y: (top + points[2 * at + 1]).toDouble(),
          ),
      ],
  ];
}
