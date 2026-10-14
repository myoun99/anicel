import '../../core/identity_memo.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_empty_gaps.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track.dart';
import '../../models/track_projection_row.dart';
import '../../models/track_frame_range.dart';
import '../../models/track_se_window.dart';
import '../../models/track_transform_lane_carrier.dart';
import '../timeline/memo_token.dart' show ByIdentity;
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

  /// The open cut's window on the track's rows — THE converter between the
  /// cut's frames and the track's. It opens where the cut's OWN frame 0
  /// stands ([ProjectAccess.activeCutMediaStartFrame]) and its cut ends
  /// where the cut does on the track, so in a cut an O.L arrives into the
  /// のりしろ before the conte is inside the window, as it is on every row
  /// of the cut.
  TrackSeWindow get trackSeWindow {
    final cut = _project.activeCutOrNull;
    final opens = _project.activeCutMediaStartFrame;
    return TrackSeWindow(
      cutStartFrame: opens,
      cutDurationFrames: cut == null
          ? 0
          : _project.activeCutGlobalStartFrame + cut.duration - opens,
    );
  }

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

  /// How far [layerId]'s OWN frame axis runs ahead of the cut's: the open
  /// cut's global start for a track-owned SE row, whose keys live on the
  /// track's frames, and zero for every row keyed on the cut.
  ///
  /// 🚨ASKED HERE AND NOWHERE ELSE. Six verbs wrote this conditional out by
  /// hand — the controllers' frame offset, the lane verbs' write axis, the
  /// lane selection's hit test and its drag, the fill funnel's
  /// pre-subtraction below and the cut-local lane range — and the clipboard
  /// (F-115) was about to be the seventh. Copies that agree today are the
  /// ones that part later; the source scan
  /// `the_row_axis_offset_is_asked_in_one_place_test` keeps it here.
  int rowAxisOffset(LayerId layerId) =>
      isTrackSeLayerId(layerId) ? _project.activeCutMediaStartFrame : 0;

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
    // C②: the V track's synthetic lane CARRIER is a rail row too — an
    // escalated lane drag anchors the track-axis selection on it. And so are
    // the track's PROJECTION rows (I-73): the cuts' conte layers and camera
    // layers shown as rows of this rail, which no cut's layer id names
    // ([trackIdOfProjectionRow]).
    final mintedFor =
        trackIdOfTransformLaneCarrier(layerId) ??
        trackIdOfProjectionRow(layerId);
    return trackSeAnywhere(layerId)?.track ??
        _transitions.trackTransitionOwner(layerId) ??
        (mintedFor == null ? null : _project.trackById(mintedFor));
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

  /// Maps a DISPLAY block start to the layer's COMMIT form key: identity
  /// for cut layers; the global-axis start for track-SE rows.
  int commitBlockStart(LayerId layerId, int displayStart) {
    if (!isTrackSeLayerId(layerId)) {
      return displayStart;
    }
    final global = trackSeGlobalLayerById(layerId);
    if (global == null) {
      return displayStart;
    }
    return trackSeWindow.globalBlockStartFor(global, displayStart);
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
  ///
  /// 🚨ONE LIST PER STATE (I-57, 10-14): the project, the cut stood in, the
  /// track it stands on and the take in flight are all it reads, so it is
  /// listed once for them and handed back until one changes
  /// ([IdentityMemo]). Listed per ask, it was listed 578 times a cut
  /// crossing on the AMMI OP — every `layers` the session composed and
  /// every picture of the track stack asked — each ask walking the track's
  /// cuts for the window.
  List<Layer> get trackSeDisplayLayers {
    final preview = _voiceRecording.voiceRecordPreviewLane.value;
    return _shown.resolve(
      identity: _project.repository.requireProject(),
      key: (
        _project.activeCutId,
        _selection.selectedTrackId,
        ByIdentity(preview),
      ),
      build: () => _listed(preview),
    );
  }

  final _shown = IdentityMemo<List<Layer>>();

  /// [trackSeDisplayLayers] as listed with [preview] in flight.
  ///
  /// 🚨A PARAMETER, NOT THE CLOSURE'S CAPTURE (I-57, 2026-10-14): listed
  /// inside the memo's closure, `preview` was a capture checked inside the
  /// loop, and the AOT compiler read it past its check — every release
  /// build died at start with no take rolling
  /// (`a_value_checked_in_a_loop_is_read_through_a_local_test`).
  List<Layer> _listed(Layer? preview) {
    final window = trackSeWindow;
    return List.unmodifiable([
      for (final layer in _selection.activeTrack.seLayers)
        _trackSeDisplayCloneFor(
          window,
          preview != null && preview.id == layer.id ? preview : layer,
        ),
    ]);
  }

  /// A row as a drag step leaves it, on its OWN axis, in the two forms a
  /// drag preview publishes: [shown] for the panels that draw the open cut
  /// — a track-SE row as its cut-local display clone — and [global] for the
  /// storyboard's track-global strips, which read the row's own axis, null
  /// for a row keyed on the cut (nothing there reads a second form).
  ///
  /// 🚨ASKED HERE AND NOWHERE ELSE. Six drag steps wrote this pair out by
  /// hand — the edge drag's single and bulk previews, the range move's
  /// cross-row, multi-row and slide previews, the lane move's name tag —
  /// and the lane move's transform and effect arms never wrote it at all:
  /// they put the GLOBAL row in the channel that carries the cut's display
  /// clones, which sits every diamond of a moving SE row a cut's start to
  /// the right on any non-first cut. Copies that agree today are the ones
  /// that part later, so the source scan
  /// `a_drag_previews_a_track_se_row_in_one_place_test` keeps it here.
  ({Layer shown, Layer? global}) previewFormsOf(Layer row) =>
      isTrackSeLayerId(row.id)
      ? (shown: trackSeWindow.displayLayer(row), global: row)
      : (shown: row, global: null);

  /// The track SE rows whose display clone starts with a spill-in block —
  /// a sound carrying over from an earlier cut — each with how far into
  /// that block the cut starts.
  ///
  /// UI-R7 #6: the timeline draws the `~` continuation at the cut start and
  /// drops the start grip; the block's real start lives in that earlier cut.
  /// 🚨F-113 (2026-09-15): the VALUE is how far into its sound the clone's
  /// frame 0 already is. The storyboard and playback read the track's own
  /// row and place the sound right; the cut's clone restarts the block at 0,
  /// so its waveform was drawn from the file's first frame until this said
  /// where it really is.
  Map<LayerId, int> get trackSeSpillInLeadFrames {
    final window = trackSeWindow;
    return {
      for (final layer in _selection.activeTrack.seLayers)
        layer.id: ?window.spillInLeadFrames(layer),
    };
  }

  /// The PLAN half of the track rung, mutation-free: which S rows the
  /// range names and which uncovered runs they hold. Split out so the
  /// button's enabled (`CellInstances.canCreateInstance`) and the verb read
  /// the SAME walk — a twin implementation is how enabled and dispatch drift.
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
      // (`frameOffsetForLayer` adds the row's axis offset on the way in),
      // because its usual callers speak CUT-LOCAL indexes. These gaps are
      // already GLOBAL — pre-subtract the SAME offset ([rowAxisOffset]), or
      // every entry lands double-shifted.
      final lensOffset = rowAxisOffset(layer.id);
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
    _project.historyManager.executeAsOneStep(
      'Create SE entries',
      _controllers.timelineController.drawingFramesCommandsForLayers(fills),
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
