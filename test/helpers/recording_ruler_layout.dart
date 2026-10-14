import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart';

/// A strip's layout that writes as [layout] writes and notes every frame it
/// is asked to lay out, and whether for the playhead's pair — what a test
/// reads to count the layouts a paint or a playback tick paid for.
({TimelineRulerGlyphLayout layout, List<({int frame, bool current})> asked})
recordingRulerLayout([
  TimelineRulerGlyphLayout layout = TimelineFrameRulerPainter.glyphsAt,
]) {
  final asked = <({int frame, bool current})>[];
  List<TimelineGlyphPlacement> recording(
    TimelineRulerScale scale,
    int frameIndex, {
    required bool current,
  }) {
    asked.add((frame: frameIndex, current: current));
    return layout(scale, frameIndex, current: current);
  }

  return (layout: recording, asked: asked);
}
