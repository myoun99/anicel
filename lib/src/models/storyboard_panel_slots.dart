// THE TRACK AS PANELS — one flat run of blocks, so a storyboard front edge
// is the SAME motion the frame axis and the cut axis already make.
//
// 🗣️유저 2026-09-12 (I-21, hands-on ②): 「스토리보드패널의 컷블록 내
// 콘티블록이 다르게 작동함 … 앞 컷이 그냥 컷블록이면 컷이 1코마될때까지
// 미는거지. 프레임블록이랑 똑같은 하나의 법으로. 근데 그 컷 블록에
// 콘티블록있으면 그 블록의 헤드까지. 이것도 똑같은 법인거지.」
//
// ★THE TRICK IS THE UNIT, NOT THE RULE. A cut with a conte row is several
// panels; a cut without one is a single panel that happens to be the whole
// cut. Flatten the track that way and 「앞 컷의 마지막 콘티 블록」 and 「앞
// 컷 자체」 stop being two cases — they are both just "the slot in front".
// [planBlockRunLeadEdge] then answers, and [cutsFromPanelLayout] reads the
// answer back as cut durations, cut gaps and conte-row keys.
library;

import 'dart:collection';

import 'block_run_move.dart';
import 'cut_id.dart';
import 'timeline_exposure.dart';

/// One panel of the flattened track: which cut it belongs to, its ordinal
/// inside that cut, and the slot the shared rule reads.
typedef StoryboardPanelSlot = ({CutId cutId, int panelIndex, BlockMoveSlot slot});

/// What one cut contributes: its leading gap, its duration, and its conte
/// row's division keys (cut-local, ascending, first key at 0 — empty when
/// the cut has no conte row, which makes it ONE panel).
typedef StoryboardCutInput = ({
  CutId id,
  int leadingGapFrames,
  int duration,
  List<int> divisionKeys,
});

/// The track flattened to panels, in order.
///
/// A cut's FIRST panel carries the cut's leading gap; the rest carry none,
/// because panels inside a cut tile it without gaps. A cut whose conte row
/// has no keys contributes exactly one panel of the cut's whole duration.
List<StoryboardPanelSlot> panelSlotsOfCuts(List<StoryboardCutInput> cuts) {
  final slots = <StoryboardPanelSlot>[];
  for (final cut in cuts) {
    final keys = cut.divisionKeys.isEmpty ? const [0] : cut.divisionKeys;
    for (var index = 0; index < keys.length; index += 1) {
      final start = index == 0 ? 0 : keys[index];
      final end = index + 1 < keys.length ? keys[index + 1] : cut.duration;
      slots.add((
        cutId: cut.id,
        panelIndex: index,
        slot: (
          leadingGap: index == 0 ? cut.leadingGapFrames : 0,
          length: end - start,
        ),
      ));
    }
  }
  return slots;
}

/// What a panel layout means for the cuts: each cut's duration is the sum
/// of its panels, and its leading gap is the gap its first panel kept.
///
/// Sparse on purpose, like every other plan on this axis: only what
/// actually changed, so a caller can tell "nothing moved" from "moved by
/// zero".
({Map<CutId, int> durations, Map<CutId, int> gaps}) cutsFromPanelLayout({
  required List<StoryboardPanelSlot> panels,
  required List<int> leadingGaps,
  required List<int> lengths,
  required List<StoryboardCutInput> before,
}) {
  final durations = <CutId, int>{};
  final gaps = <CutId, int>{};
  for (var i = 0; i < panels.length; i += 1) {
    final cutId = panels[i].cutId;
    durations[cutId] = (durations[cutId] ?? 0) + lengths[i];
    if (panels[i].panelIndex == 0) {
      gaps[cutId] = leadingGaps[i];
    }
  }
  for (final cut in before) {
    if (durations[cut.id] == cut.duration) {
      durations.remove(cut.id);
    }
    if (gaps[cut.id] == cut.leadingGapFrames) {
      gaps.remove(cut.id);
    }
  }
  return (durations: durations, gaps: gaps);
}

/// [timeline] with its division keys moved to where the panel layout put
/// them — the conte row's half of the same answer.
///
/// The keys are cut-local, so they are read straight off the panel lengths
/// of that cut; every block keeps its entry (and its breakdown dots) and
/// only its key moves. Null when nothing moved.
SplayTreeMap<int, TimelineExposure>? conteTimelineFromPanels({
  required SplayTreeMap<int, TimelineExposure>? timeline,
  required List<int> panelLengths,
}) {
  if (timeline == null || panelLengths.isEmpty) {
    return null;
  }
  final entries = timeline.entries.toList();
  if (entries.length != panelLengths.length) {
    return null;
  }
  final next = SplayTreeMap<int, TimelineExposure>();
  var cursor = 0;
  var moved = false;
  for (var i = 0; i < entries.length; i += 1) {
    if (entries[i].key != cursor) {
      moved = true;
    }
    next[cursor] = entries[i].value.copyWith(length: panelLengths[i]);
    cursor += panelLengths[i];
  }
  return moved || !_sameLengths(entries, panelLengths) ? next : null;
}

bool _sameLengths(
  List<MapEntry<int, TimelineExposure>> entries,
  List<int> lengths,
) {
  for (var i = 0; i < entries.length; i += 1) {
    if (entries[i].value.length != lengths[i]) {
      return false;
    }
  }
  return true;
}
