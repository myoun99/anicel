import 'dart:collection' show SplayTreeMap;

import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/timeline_coverage.dart' show exposedFrameIdAt;
import '../../models/timeline_exposure.dart';
import '../../models/timeline_repeat.dart'
    show ghostFreeTimeline, rederiveRunBehaviors;
import '../../models/timeline_splice.dart' show splitTimelineAt;

/// [row]'s timeline showing [celAt]'s cel at each frame it names: each
/// block split where its picture changes and showing its pictures' cels
/// ([splitTimelineAt]: the head keeps the memo and the marks), its holds
/// and repeats derived again ([rederiveRunBehaviors]) over the
/// [drawnFrames] its cut draws — and, where one would show a cel another
/// picture belongs on, made of blocks of its own.
///
/// ⛔ONE way a bake parts a row's blocks: an fx RASTERIZE's (I-120) and a
/// reference's rasterized a position apiece (I-120-Q5) both lay theirs by
/// it.
Map<int, TimelineExposure> timelineShowing(
  Layer row,
  Map<int, FrameId> celAt,
  int drawnFrames,
) {
  Layer laid(Map<int, TimelineExposure> authored) => rederiveRunBehaviors(
    row.copyWith(timeline: _splitBy(authored, celAt)),
    drawnFrameCount: drawnFrames,
  );
  final derived = laid(ghostFreeTimeline(row));
  if (_shows(derived, celAt)) {
    return derived.timeline;
  }
  final authored = laid({
    for (final MapEntry(key: start, value: entry) in row.timeline.entries)
      start: entry.ghost
          ? TimelineExposure.drawing(
              entry.frameId!,
              length: entry.length!,
              breakdownMarks: entry.breakdownMarks,
            )
          : entry,
  });
  assert(_shows(authored, celAt), 'every frame is a block of its own');
  return authored.timeline;
}

/// [authored] with each block split where [celAt] changes, each part
/// showing the cel [celAt] names at its head — or its own, where none.
SplayTreeMap<int, TimelineExposure> _splitBy(
  Map<int, TimelineExposure> authored,
  Map<int, FrameId> celAt,
) {
  var next = SplayTreeMap<int, TimelineExposure>.from(authored);
  for (final MapEntry(key: start, value: entry) in authored.entries) {
    for (var frame = start + 1; frame < start + entry.length!; frame += 1) {
      if (celAt[frame] != celAt[frame - 1]) {
        next = splitTimelineAt(next, frame);
      }
    }
  }
  return SplayTreeMap.from({
    for (final MapEntry(key: start, value: entry) in next.entries)
      start: switch (celAt[start]) {
        final cel? => entry.copyWith(frameId: cel),
        null => entry,
      },
  });
}

/// Whether [row] shows [celAt]'s cel at every frame it names.
bool _shows(Layer row, Map<int, FrameId> celAt) => celAt.entries.every(
  (at) => exposedFrameIdAt(row.timeline, at.key) == at.value,
);
