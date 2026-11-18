import 'dart:typed_data';

import 'package:anicel/src/services/canvas_selection_region.dart';

/// [CanvasSelectionRegion] saying how many pixels each read of its
/// coverage on the CPU asked for. ⛔ONE SPY: the edge's tests and the
/// lift's each held one, and the fill's mark came as a third (2026-11-14).
class SelectionReadsSpied extends CanvasSelectionRegion {
  SelectionReadsSpied(CanvasSelectionRegion region, this.asked)
    : super(region.steps);

  final List<int> asked;

  @override
  Uint8List maskFor({
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    asked.add(width * height);
    return super.maskFor(left: left, top: top, width: width, height: height);
  }
}
