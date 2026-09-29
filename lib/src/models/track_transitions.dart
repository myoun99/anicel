/// A track's transitions read off the PROJECT — the spans its transition row
/// carries, and what they cost each cut in のりしろ.
///
/// The session reads the same spans through the row a drag in flight shows;
/// this is the committed project's answer, for the places that hold a
/// project and no session: the repository's write, the timeline controller.
library;

import 'camera_instruction.dart';
import 'cut.dart';
import 'cut_id.dart';
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
