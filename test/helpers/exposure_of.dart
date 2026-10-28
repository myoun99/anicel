import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';

/// What a cell of [layer] exposes, read off the layer the way the session
/// reads it (`ExposureVerbs.exposureStateForLayer`) — for a fixture that
/// hands a row its resolver.
///
/// A row walks its cells by where its layer's blocks change (I-22), so a
/// fixture states its blocks ON THE LAYER: a resolver that answers cells
/// the layer does not hold describes a row no host can build, and the row
/// paints it wrong.
///
/// ↩️It spelled the reading out a second time; it asks the one the
/// session asks (I-130, when the dot grew a second mark).
TimelineCellExposureState exposureOf(Layer layer, int frameIndex) =>
    timelineOwnCelsStateAt(layer, frameIndex);
