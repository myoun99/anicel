import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';

/// What a cell of [layer] exposes, read off the layer the way the session
/// reads it (`ExposureVerbs.exposureStateForLayer`) — for a fixture that
/// hands a row its resolver.
///
/// A row walks its cells by where its layer's blocks change (I-22), so a
/// fixture states its blocks ON THE LAYER: a resolver that answers cells
/// the layer does not hold describes a row no host can build, and the row
/// paints it wrong.
TimelineCellExposureState exposureOf(Layer layer, int frameIndex) {
  if (frameIndex < 0) {
    return TimelineCellExposureState.uncovered;
  }
  if (layer.timeline[frameIndex]?.isDrawing ?? false) {
    return TimelineCellExposureState.drawingStart;
  }
  if (coveringDrawingBlockAt(layer.timeline, frameIndex) == null) {
    return TimelineCellExposureState.uncovered;
  }
  return hasBreakdownDotAt(layer.timeline, frameIndex)
      ? TimelineCellExposureState.markHeld
      : TimelineCellExposureState.held;
}
