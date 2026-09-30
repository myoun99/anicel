/// A track's transitions read off the PROJECT — the spans its transition row
/// carries, what they cost each cut in のりしろ, and where they go when the
/// cuts under them move.
///
/// The session reads the same spans through the row a drag in flight shows;
/// this is the committed project's answer, for the places that hold a
/// project and no session: the repository's write, the timeline controller.
library;

import 'camera_instruction.dart';
import 'cut.dart';
import 'cut_id.dart';
import 'layer.dart';
import 'project.dart';
import 'storyboard_timeline_layout.dart' show cutSpansOf;
import 'track.dart';
import 'transition_geometry.dart';

/// One transition event as a geometry span, WITH its term's mark as
/// [vocabulary] defines it.
///
/// 🚨The mark is what tells O.L from F.O downstream. Dropping it made
/// `cutOpacityAt` treat every span as a symmetric cross-dissolve, so an F.O
/// faded the next cut IN and behaved as an O.L (user 2026-08-11). An id the
/// vocabulary no longer holds falls back to the bowtie ([transitionMarkOf]).
TransitionSpan transitionSpanOfEvent(
  MapEntry<int, InstructionEvent> entry,
  CameraInstructionSet vocabulary,
) => (
  start: entry.key,
  length: entry.value.length,
  mark: transitionMarkOf(vocabulary.defById(entry.value.instructionId)),
);

/// [track]'s transition spans on its global axis.
List<TransitionSpan> trackTransitionSpans(
  Track track,
  CameraInstructionSet vocabulary,
) => [
  for (final entry in track.transitionLayer.instructions.entries)
    transitionSpanOfEvent(entry, vocabulary),
];

/// How many frames [cut] is DRAWN for given the のりしろ [handles] it owes:
/// its conte 尺 plus both sides. Its conte 尺 whenever nothing crosses —
/// never less than one frame, the floor the sheet and the image row already
/// read a cut's length with.
///
/// ★The ruler's blue line and the fill of every hold read this one number,
/// so a hold cannot end short of the line it is drawn to (F-227).
int drawnFrameCountOf(Cut cut, CutTransitionHandles handles) =>
    handles.drawnFrames(cut.duration < 1 ? 1 : cut.duration);

/// [drawnFrameCountOf] for [cut] standing at [cutStart] among [spans].
int drawnFramesOfCutAt({
  required Cut cut,
  required int cutStart,
  required Iterable<TransitionSpan> spans,
}) => drawnFrameCountOf(
  cut,
  cutTransitionHandles(
    cutStart: cutStart,
    cutEnd: cutStart + cut.duration,
    spans: spans,
  ),
);

/// Every cut of [project] with the のりしろ its own track's transitions ask
/// of it — before its conte (an O.L arriving) and after it (an O.L leaving).
Map<CutId, CutTransitionHandles> transitionHandlesByCut(Project project) {
  final handles = <CutId, CutTransitionHandles>{};
  for (final track in project.tracks) {
    final spans = trackTransitionSpans(track, project.cameraInstructions);
    for (final placed in cutSpansOf(track)) {
      handles[placed.cut.id] = cutTransitionHandles(
        cutStart: placed.startFrame,
        cutEnd: placed.endFrame,
        spans: spans,
      );
    }
  }
  return handles;
}

/// Every cut of [project] with how many frames it is drawn for
/// ([drawnFrameCountOf]), each measured on its own track.
Map<CutId, int> drawnFrameCountsOf(Project project) {
  final handles = transitionHandlesByCut(project);
  return {
    for (final track in project.tracks)
      for (final cut in track.cuts)
        cut.id: drawnFrameCountOf(cut, handles[cut.id]!),
  };
}

/// [drawnFrameCountOf] for the one cut [cutId] of [project], or null when
/// no track holds it.
int? cutDrawnFrameCount(Project project, CutId cutId) {
  final found = _handlesOfOne(project, cutId);
  return found == null ? null : drawnFrameCountOf(found.cut, found.handles);
}

/// 🗣️유저 2026-08-10 (메모리 `cut-ol-design.md`): 「그냥 글로벌로 두고 행동은
/// 해당 범위의 양 컷을 ol시키는거. 움직일때만 앵커로서 앞 컷에 앵커. 앞 컷이
/// 없으면 현재 컷에 앵커.」
///
/// [after]'s transition row carried to where the cuts under it went since
/// [before]. The anchor is not stored: it is found in [before], the layout
/// the edit started from — the FRONT cut, the one a span's first frame lies
/// in, else (a span that starts in a gap) the first cut it reaches — and the
/// span moves by as much as that cut's start did. A front cut the edit
/// removed hands the span to the next cut it reaches (the 08-09 table: 「앞
/// 컷 삭제 → 새 앞 컷과 맺어진다」); a span that reaches no surviving cut
/// stays. A span carried before the track's first frame keeps its end and
/// starts at 0.
///
/// ⚠️A cut's own END moving does not move its spans — the rule anchors to
/// the cut, and the cut did not move. Whether the boundary should carry them
/// instead is F-227-ol-trim-Q1.
///
/// [after]'s own row comes back when nothing moves.
Layer transitionRowFollowingItsCuts({
  required Track before,
  required Track after,
}) {
  final was = cutSpansOf(before).toList();
  final now = {
    for (final placed in cutSpansOf(after)) placed.cut.id: placed.startFrame,
  };
  final row = after.transitionLayer;
  final carried = <int, InstructionEvent>{};
  var changed = false;
  for (final MapEntry(key: start, value: event) in row.instructions.entries) {
    final end = start + event.length;
    final anchor = was
        .where(
          (placed) =>
              placed.endFrame > start &&
              placed.startFrame < end &&
              now.containsKey(placed.cut.id),
        )
        .firstOrNull;
    final delta = anchor == null
        ? 0
        : now[anchor.cut.id]! - anchor.startFrame;
    if (delta == 0) {
      carried[start] = event;
      continue;
    }
    changed = true;
    final movedStart = start + delta;
    carried[movedStart < 0 ? 0 : movedStart] = movedStart < 0
        ? event.copyWith(length: end + delta)
        : event;
  }
  return changed ? row.copyWith(instructions: carried) : row;
}

/// The のりしろ the one cut [cutId] of [project] owes, or
/// [CutTransitionHandles.none] when no track holds it.
CutTransitionHandles cutTransitionHandlesIn(Project project, CutId cutId) =>
    _handlesOfOne(project, cutId)?.handles ?? CutTransitionHandles.none;

({Cut cut, CutTransitionHandles handles})? _handlesOfOne(
  Project project,
  CutId cutId,
) {
  for (final track in project.tracks) {
    for (final placed in cutSpansOf(track)) {
      if (placed.cut.id == cutId) {
        return (
          cut: placed.cut,
          handles: cutTransitionHandles(
            cutStart: placed.startFrame,
            cutEnd: placed.endFrame,
            spans: trackTransitionSpans(track, project.cameraInstructions),
          ),
        );
      }
    }
  }
  return null;
}
