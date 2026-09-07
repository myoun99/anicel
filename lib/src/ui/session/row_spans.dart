import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_frame_range.dart' show exposureBlockAt;
import '../../models/range_snap.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track_frame_axis.dart';
import '../../models/track_id.dart';
import '../timeline/instruction_span_editing.dart';
import 'folder_bands.dart';
import 'session_roles.dart';
import 'track_se_display.dart';
import 'transitions.dart';

/// WHAT A ROW SPANS — where a row's material starts and ends, and what a
/// range drag over it may snap to.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP
/// cut, round 8's G3, 2026-09-07). The four reads were scattered down the
/// host between the drags that ask them, and they are one subject: given a
/// row, what does it cover? The cut row answers in cuts, the track-owned
/// rows in their authored blocks, a folder row in its members' merged runs,
/// and every row offers the snap lane its own material makes.
///
/// ⛔It selects NOTHING. The verb that turns a span into a selection is
/// [RangeSelections.selectRowSpanForCurrentRow] — which holds one of these
/// — because a selection is the range object's to make.
class RowSpans {
  RowSpans({
    required ProjectAccess project,
    required TimelineAccess timeline,
    required FolderBands folderBands,
    required TrackSeDisplay trackSe,
    required Transitions transitions,
  }) : _project = project,
       _timeline = timeline,
       _folderBands = folderBands,
       _trackSe = trackSe,
       _transitions = transitions;

  final ProjectAccess _project;
  final TimelineAccess _timeline;
  final FolderBands _folderBands;
  final TrackSeDisplay _trackSe;
  final Transitions _transitions;

  /// D40, the cut row: [trackId]'s whole cut span — the first cut's start
  /// through the last cut's end — or null when the track has no cuts.
  ({int startFrame, int endFrameExclusive})? trackCutSpan(TrackId trackId) {
    final entries = _timeline.axisForTrack(trackId).entries;
    if (entries.isEmpty) {
      return null;
    }
    return (
      startFrame: entries.first.startFrame,
      endFrameExclusive: entries.last.endFrame,
    );
  }

  /// D40, the track-owned rows: [layerId]'s authored span on the global
  /// axis — an S row's first block start through its last block end, or
  /// the transition row's first span start through its last span end.
  /// Null for empty rows (and for ids that are no track row at all).
  ({int startFrame, int endFrameExclusive})? trackRowAuthoredSpan(
    LayerId layerId,
  ) {
    final transitionTrack = _transitions.trackTransitionOwner(layerId);
    if (transitionTrack != null) {
      final events = transitionTrack.transitionLayer.instructions;
      if (events.isEmpty) {
        return null;
      }
      int? first;
      var lastExclusive = 0;
      for (final entry in events.entries) {
        if (first == null || entry.key < first) {
          first = entry.key;
        }
        final end = entry.key + entry.value.length;
        if (end > lastExclusive) {
          lastExclusive = end;
        }
      }
      return (startFrame: first!, endFrameExclusive: lastExclusive);
    }
    final layer = _trackSe.trackSeAnywhere(layerId)?.layer;
    if (layer == null) {
      return null;
    }
    int? first;
    var lastExclusive = 0;
    for (final entry in layer.timeline.entries) {
      if (entry.value.ghost) {
        continue;
      }
      first ??= entry.key;
      lastExclusive = entry.key + entry.value.length!;
    }
    if (first == null) {
      return null;
    }
    return (startFrame: first, endFrameExclusive: lastExclusive);
  }

  /// "Where does this row's blocks live" as a snap lane, or null for a row
  /// that has none to snap to.
  RangeBlock? Function(int)? trackRowSnapLane(
    TimelineRowAddress row,
    TrackFrameAxis axis,
  ) {
    switch (row) {
      case TrackRowAddress():
        return axis.cutBlockAt;
      case LayerRowAddress(:final layerId):
        // Resolved on the row's OWN track: the active-track lookup left
        // every unselected track's sounds snapless.
        final layer = _trackSe.trackSeAnywhere(layerId)?.layer;
        if (layer != null) {
          return (index) => exposureBlockAt(layer, index);
        }
        // 🚨The transition row snaps to its SPANS, and a row with no snap lane
        // at all produced no span — which cleared the selection instead of
        // making one. Its blocks are instruction events rather than exposures,
        // so the material differs and the shape does not.
        final transition = _transitions
            .trackTransitionOwner(layerId)
            ?.transitionLayer;
        if (transition == null) {
          return null;
        }
        return (index) {
          final covering = instructionSpanCovering(
            transition.instructions,
            index,
          );
          return covering == null
              ? null
              : RangeBlock(
                  startIndex: covering.key,
                  endIndexExclusive: covering.key + covering.value.length,
                );
        };
      case LaneRowAddress():
        // Lane keys are POINTS, not blocks — the lane domain's own rule
        // ("raw cells, no block snap"), so there is nothing to snap to.
        return null;
    }
  }

  /// The snap lane a FOLDER row selects against (R9 #1): the very runs its
  /// band draws, which are its subtree members' exposures merged. Empty for
  /// every row that owns its own blocks.
  List<({int start, int endExclusive})> aggregateRunsForRow(Layer layer) {
    if (!layer.kind.groupsLayers) {
      return const [];
    }
    // R10: the band cache's runs, so the snap and the painted band are one
    // answer. This used to walk the subtree fresh on every call — inside
    // the select-drag loop.
    return _folderBands.folderBandRunsOf(layer.id);
  }

  /// Whether [layerId] names a SINGLE-CEL (image) row of the active cut:
  /// its one covering block is pinned by the write normalization, so the
  /// reshaping verbs (range move, push/pull, comma set, X-here) stand
  /// down — committing them would be reverted in the same write, leaving
  /// a phantom no-op on the undo stack.
  bool isSingleCelLayerId(LayerId layerId) {
    final layer = _project.layerById(layerId);
    return layer != null && layer.kind.holdsSingleCel;
  }
}
