import 'dart:math' as math;

import 'cut.dart';
import 'timeline_coverage.dart';

/// THE frame count warming, budget protection and the readiness bar all
/// reason over — one law, three readers (B1).
///
/// A cut's pictures reach `max(duration, authored extent)`: the timeline's
/// runway past the end line takes drawings like any other frame (⑯), so
/// the warm bakes out to them, the budget must not evict what the warm
/// just baked, and the bar answers over the same width. Two of those
/// three derived this independently once — warming baked the runway while
/// protection stopped at the end line, so every runway composite the warm
/// produced was evictable the moment it landed.
///
/// This is NOT the playback length (`Cut.duration` — what a playlist
/// entry plays, and what the PLAYING branch of protection correctly
/// covers), and not the sheet's drawn width (duration plus のりしろ
/// margins, which need nothing here until someone draws on them — an
/// undrawn frame composes to nothing and is ready by definition).
int cutWarmFrameCount(Cut cut) {
  var extent = 0;
  for (final layer in cut.layers) {
    final layerExtent = authoredTimelineExtent(layer.timeline);
    if (layerExtent > extent) {
      extent = layerExtent;
    }
  }
  return math.max(1, math.max(cut.duration, extent));
}
