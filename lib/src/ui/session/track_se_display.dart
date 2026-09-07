import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_empty_gaps.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track.dart';
import '../../models/track_frame_range.dart';
import '../../models/track_se_window.dart';
import '../../models/track_transform_lane_carrier.dart';
import '../../services/command.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import 'transitions.dart';
import 'editor_voice_recording.dart';

/// The TRACK SE DISPLAY — a track's SE layers as the cut's rail shows them:
/// the window a cut sees, the display clones and their cache, which rail
/// rows a track owns, the spill-in layers, and creating SE entries across
/// a range — as its own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: one field of its own and
/// fourteen session members touched. It names the roles it needs in
/// its constructor.
class TrackSeDisplay {
  TrackSeDisplay({required ProjectAccess project, required SelectionAccess selection, required ChangeSink changes, required FrameIds frameIds, required ActiveCutControllers controllers, required Transitions transitions, required EditorVoiceRecording voiceRecording}) : _project = project, _selection = selection, _changes = changes, _frameIds = frameIds, _controllers = controllers, _transitions = transitions, _voiceRecording = voiceRecording;

  final EditorVoiceRecording _voiceRecording;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final ActiveCutControllers _controllers;
  final Transitions _transitions;

  TrackSeWindow get trackSeWindow => TrackSeWindow(
    cutStartFrame: _project.activeCutGlobalStartFrame,
    cutDurationFrames: _project.activeCutOrNull?.duration ?? 0,
  );

  /// Whether [layerId] names a TRACK-owned SE row — a question about what
  /// KIND of row it is, on any track in the project.
  ///
  /// ★It used to ask `activeTrack` only, which quietly made it "…and that
  /// track holds the open cut". Every axis rule keyed off it then answered
  /// NO for another track's S row, so those rows fell onto the cut-layer
  /// paths and did nothing (user, 2026-08-09: "S행은 V랑 관련없이
  /// 독립적으로 움직일 수 있어야 해"). Which cut is open is not part of
  /// what a row IS.
  bool isTrackSeLayerId(LayerId layerId) => trackSeAnywhere(layerId) != null;

  /// Whether [layerId] is a TRACK-OWNED row of the storyboard's rail — an SE
  /// lane or the transition row.
  ///
  /// ★Deliberately not `isTrackSeLayerId` at the call sites that mean THIS.
  /// "Is it an SE row" was standing in for "is it a row this rail can be
  /// standing on", and the transition row is the second answer — the same
  /// substitution that made the cut view's bulk verbs reach for a
  /// track-owned row as if it were a cut layer. Row behaviour that really is
  /// SE-specific (block snapping, sound order drags, range moves) keeps
  /// asking the SE question.
  bool isTrackOwnedRailLayerId(LayerId layerId) =>
      isTrackSeLayerId(layerId) || _project.isTrackTransitionLayerId(layerId);

  /// The track that owns [layerId] as one of its rail rows — the resolver half
  /// of [isTrackOwnedRailLayerId], for the verbs that need the track and not
  /// just a yes.
  Track? trackOwnedRailOwner(LayerId layerId) {
    final carrierTrackId = trackIdOfTransformLaneCarrier(layerId);
    return trackSeAnywhere(layerId)?.track ??
        _transitions.trackTransitionOwner(layerId) ??
        // C②: the V track's synthetic lane CARRIER is a rail row too — an
        // escalated lane drag anchors the track-axis selection on it.
        (carrierTrackId == null ? null : _project.trackById(carrierTrackId));
  }

  /// The GLOBAL track layer for [layerId] (never a display clone).
  Layer? trackSeGlobalLayerById(LayerId layerId) {
    for (final layer in _selection.activeTrack.seLayers) {
      if (layer.id == layerId) {
        return layer;
      }
    }
    return null;
  }

  /// Display-clone cache (UI-R20 #4): the clones used to be rebuilt on
  /// EVERY read, so every session notify handed the grids fresh Layer
  /// identities — defeating all the identity-keyed row memos and
  /// rebuilding every SE row per notify (the "selecting a layer got slow
  /// after adding dialogue" regression). Keyed per SE layer: same source
  /// layer + same window = the SAME clone instance back.
  final Map<LayerId, (Layer, int, int, Layer)> _seDisplayCloneCache = {};

  Layer _trackSeDisplayCloneFor(TrackSeWindow window, Layer layer) {
    final cached = _seDisplayCloneCache[layer.id];
    if (cached != null &&
        identical(cached.$1, layer) &&
        cached.$2 == window.cutStartFrame &&
        cached.$3 == window.cutDurationFrames) {
      return cached.$4;
    }
    final display = window.displayLayer(layer);
    _seDisplayCloneCache[layer.id] = (
      layer,
      window.cutStartFrame,
      window.cutDurationFrames,
      display,
    );
    return display;
  }

  /// The track's SE rows as cut-local display clones for the active cut.
  ///
  /// While a take rolls, the armed lane shows its PREVIEW state (REC1-C):
  /// the in-flight take landed by the same planner the stop will use —
  /// commits and undo keep reading the repository lane untouched.
  List<Layer> get trackSeDisplayLayers {
    final window = trackSeWindow;
    final preview = _voiceRecording.voiceRecordPreviewLane.value;
    return [
      for (final layer in _selection.activeTrack.seLayers)
        _trackSeDisplayCloneFor(
          window,
          preview != null && preview.id == layer.id ? preview : layer,
        ),
    ];
  }

  /// The track SE rows whose display clone starts with a spill-in block —
  /// a sound carrying over from an earlier cut (UI-R7 #6: the timeline
  /// draws the `~` continuation at the cut start and drops the start
  /// grip; the block's real start lives in that earlier cut).
  Set<LayerId> get trackSeSpillInLayerIds {
    final window = trackSeWindow;
    return {
      for (final layer in _selection.activeTrack.seLayers)
        if (window.spillInBlock(layer) != null) layer.id,
    };
  }

  /// The PLAN half of the track rung, mutation-free: which S rows the
  /// range names and which uncovered runs they hold. Split out so the
  /// button's enabled ([_internals.canCreateInstance]) and the verb read the SAME
  /// walk — a twin implementation is how enabled and dispatch drift.
  Map<Layer, List<({int startIndex, int length})>> trackSeCreationGaps(
    TrackFrameRangeSelection range,
  ) {
    Track? track;
    for (final candidate in _project.repository.requireProject().tracks) {
      if (candidate.id == range.trackId) {
        track = candidate;
        break;
      }
    }
    if (track == null) {
      return const {};
    }
    final targetIds = <LayerId>{
      for (final row in [range.anchorRow, ...range.rows])
        if (row is LayerRowAddress) row.layerId,
    };
    final gaps = <Layer, List<({int startIndex, int length})>>{};
    for (final layer in track.seLayers) {
      if (!targetIds.contains(layer.id)) {
        continue;
      }
      final layerGaps = emptyGapsBetween(
        layer,
        range.startFrame,
        range.endFrameExclusive,
      );
      if (layerGaps.isNotEmpty) {
        gaps[layer] = layerGaps;
      }
    }
    return gaps;
  }

  bool createTrackSeEntriesForRange(TrackFrameRangeSelection range) {
    final gapsByLayer = trackSeCreationGaps(range);
    final fills =
        <
          LayerId,
          List<({int startIndex, int length, FrameId frameId, String? name})>
        >{};
    for (final entry in gapsByLayer.entries) {
      final layer = entry.key;
      // ⚠️The fills funnel re-applies the track-SE display lens
      // (`frameOffsetForLayer` adds the active cut's global start on the
      // way in), because its usual callers speak CUT-LOCAL indexes. These
      // gaps are already GLOBAL — pre-subtract the SAME expression the
      // lens uses, or every entry lands double-shifted.
      final lensOffset = isTrackSeLayerId(layer.id)
          ? _project.activeCutGlobalStartFrame
          : 0;
      final layerFills =
          <({int startIndex, int length, FrameId frameId, String? name})>[];
      for (final gap in entry.value) {
        layerFills.add((
          startIndex: gap.startIndex - lensOffset,
          length: gap.length,
          frameId: _frameIds.mintFrameId(layer.id),
          // A blank DIALOGUE, like the cut-scope SE creation makes — the
          // entry exists to be written into.
          name: '',
        ));
      }
      fills[layer.id] = layerFills;
    }
    if (fills.isEmpty) {
      return false;
    }
    final commands = _controllers.timelineController
        .drawingFramesCommandsForLayers(fills);
    _project.historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(
              description: 'Create SE entries',
              commands: commands,
            ),
    );
    _changes.notifyChanged();
    return true;
  }

  /// The track that owns [layerId] as one of its SE lanes, with the GLOBAL
  /// layer itself — ANY track, not just the selected one. A storyboard
  /// drag anchors on whatever row sits under the pointer, and resolving
  /// through [_selection.selectedTrackId]/[trackSeGlobalLayerById] (both active-track
  /// bound) made every verb on an unselected track's row a silent no-op.
  ({Track track, Layer layer})? trackSeAnywhere(LayerId layerId) {
    for (final track in _project.repository.requireProject().tracks) {
      for (final layer in track.seLayers) {
        if (layer.id == layerId) {
          return (track: track, layer: layer);
        }
      }
    }
    return null;
  }
}
