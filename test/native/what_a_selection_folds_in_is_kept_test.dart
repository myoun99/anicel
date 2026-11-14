import 'package:anicel/src/native/drawing_engines.dart';
import 'package:anicel/src/native/engine_selection_masks.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bit planes a selection is folded in on the engine are kept for the
/// next fold (board `a-selection-mask-is-built-on-the-cpu-at-every-move`,
/// L2e) — so they are memory the app holds: counted where the census reads
/// it, and let go of when the OS says memory is tight, as the blur
/// kernels' scratch is.
void main() {
  test('what a selection is folded in is counted, and let go of when memory '
      'is tight', () {
    final region = CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(left: 0, top: 0, right: 40, bottom: 10),
    );
    region.pixelRunsFor(left: 0, top: 0, width: 40, height: 10);
    expect(EngineSelectionMasks.idleBytes, greaterThan(0));
    DrawingEngines.respondToMemoryPressure();
    expect(EngineSelectionMasks.idleBytes, 0);
  });
}
