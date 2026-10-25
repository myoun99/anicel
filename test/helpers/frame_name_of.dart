import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/timeline_coverage.dart';

/// The name a cell of [layer] shows, read off the layer the way the session
/// reads it (`FrameVerbs.frameNameForLayer`, a row that mirrors nothing):
/// the cel the block at [frameIndex] exposes — for a fixture that hands a
/// row its resolver, as `exposureOf` is for its cells' exposure.
String? frameNameOf(Layer layer, int frameIndex) {
  final cel = exposedFrameIdAt(layer.timeline, frameIndex);
  return cel == null ? null : layer.frameById(cel)?.name;
}
