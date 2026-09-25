import '../../models/flip_column_step.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_repeat.dart';
import '../../models/track_frame_axis.dart';
import '../../models/track_id.dart';
import '../storyboard_layer_policy.dart' show storyboardPanelsOnTrack;
import '../timeline/instruction_span_editing.dart' show instructionSpanCovering;
import 'active_cut_controllers.dart';
import 'project_settings.dart';
import 'session_roles.dart';
import 'track_se_display.dart';

/// THE TRACK'S AXIS, walked — where the storyboard's rows step and flip,
/// and where a playhead parked in a gap steps out: the track's frames,
/// across its cuts.
///
/// 🗣️유저 2026-09-24: 「마지막으로 만진 패널」 — the storyboard's rows ALL
/// live on this axis (the V row, the S rows, the transition row), so while
/// it is the panel being worked in its flips and one-frame steps are walks
/// on it. The cut's own axis stays with [FrameVerbs], which picks between
/// the two.
///
/// The cut axis and this one each land in ONE place: [FrameVerbs]'s
/// `_flipToFrame` there, [_land] here.
class TrackAxisWalk {
  TrackAxisWalk({
    required ProjectAccess project,
    required SelectionAccess selection,
    required TimelineAccess timeline,
    required ActiveCutControllers controllers,
    required ProjectSettings projectSettings,
    required TrackSeDisplay trackSe,
  }) : _project = project,
       _selection = selection,
       _timeline = timeline,
       _controllers = controllers,
       _projectSettings = projectSettings,
       _trackSe = trackSe;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final TimelineAccess _timeline;
  final ActiveCutControllers _controllers;
  final ProjectSettings _projectSettings;

  /// Which track owns a rail row, for the storyboard's S and transition rows
  /// — they live on the TRACK, so their flip reads the track's own row.
  final TrackSeDisplay _trackSe;

  /// The V-row half: the track's PANELS are its columns, on the global axis
  /// ([storyboardPanelsOnTrack]) — a cut's conte blocks where it has a conte
  /// row, else the cut itself as one block.
  ///
  /// 🗣️유저 2026-09-24: 「콘티패널에서는 플립이 타임라인패널이랑 같은 규칙으로
  /// 설정한 상태로 블록/프레임별로 이동. 콘티레이어 있으면 콘티레이어
  /// 블록기준」. ↩️It counted CUTS, so a cut of five panels was one step
  /// while the same row's lead edge traded frames panel by panel (I-21).
  ///
  /// The same column step the layer row takes, with the track's panels as
  /// the covering material instead of a layer's blocks — which is the
  /// whole point of stating the rule as columns. It carried the identical
  /// key-stepping defect before, so a gap between two cuts was skipped in
  /// both directions here too.
  ///
  /// This is also the axis a GAP is walked on: `selectGlobalFrame` lands
  /// the result inside a cut or parks it in the void, so a playhead
  /// standing between cuts can step out under its own power.
  void flipPanels(TrackId trackId, {required bool forward}) {
    // The MEMOIZED layout (identity-keyed on the project): a flip step is
    // a per-move cost, and rebuilding the whole cross-track layout for
    // each one is exactly the tax that memo exists to remove.
    final entries = [
      for (final entry in _projectSettings.projectLayout())
        if (entry.trackId == trackId) entry,
    ];
    if (entries.isEmpty) {
      return;
    }
    final axis = TrackFrameAxis(entries);
    final panels = storyboardPanelsOnTrack(entries);
    final from = _from(axis);
    _land(
      flipColumnStep(
        frame: from,
        direction: forward ? 1 : -1,
        columnAt: (frame) {
          for (final panel in panels) {
            if (frame < panel.start) {
              return null;
            }
            if (frame < panel.endExclusive) {
              return (start: panel.start, endExclusive: panel.endExclusive);
            }
          }
          return null;
        },
      ),
      from: from,
      // Land on the axis the step was measured on: this row may name a
      // track that is not the selected one.
      //
      // ⛔DROPPING `onAxis` SURVIVES MUTATION (2026-09-07), and the
      // classification is AN INNER GUARD ALREADY ANSWERS: standing on a
      // cut row TAKES its track, so by the time the landing resolves
      // `trackFrameAxis()` is the same axis. Kept because it makes the
      // step and the landing one axis BY CONSTRUCTION rather than by
      // that coincidence — the standing rule is free to change.
      onAxis: axis,
    );
  }

  /// A track-owned row — an S row, the transition row — flipped where the
  /// STORYBOARD shows it: the track's own row on the track's own axis, so
  /// the flip crosses cut boundaries the way the strip runs across them.
  ///
  /// ⛔Not the cut's copy. The timeline shows these rows as the active cut's
  /// projection (#741: picking the projection is a different act from
  /// picking the original), and walking that copy kept a storyboard flip
  /// inside one cut — past the cut's end it walked the cut's runway instead
  /// of reaching the next sound.
  void flipTrackRow(LayerId layerId, {required bool forward}) {
    final track = _trackSe.trackOwnedRailOwner(layerId);
    if (track == null) {
      return;
    }
    final layer = track.transitionLayer.id == layerId
        ? track.transitionLayer
        : track.seLayers.where((row) => row.id == layerId).firstOrNull;
    if (layer == null) {
      return;
    }
    final axis = _timeline.axisForTrack(track.id);
    final from = _from(axis);
    _land(
      flipColumnStep(
        frame: from,
        direction: forward ? 1 : -1,
        columnAt: (frame) => flipColumnOfRow(layer, frame),
      ),
      from: from,
      onAxis: axis,
    );
  }

  /// ONE FRAME on the selected track's axis — the storyboard's Ctrl+→ and
  /// `,`·`.`, and a gap's, where the cut axis does not exist: a V row's step
  /// crosses into the next cut the way its flip does.
  void stepOneFrame({required bool forward}) {
    final from = _from(_timeline.trackFrameAxis());
    _land(from + (forward ? 1 : -1), from: from);
  }

  /// Where a step on the TRACK's axis leaves from: where the storyboard
  /// shows the playhead ([TrackFrameAxis.storyboardFrameOf]) — a gap
  /// parking, or the active cut's frame clamped into its cut. A playhead
  /// that stands past its cut's end in the timeline is shown on the cut's
  /// last frame there, and that is the frame this axis counts from.
  int _from(TrackFrameAxis axis) =>
      axis.storyboardFrameOf(
        parkedGlobalFrame: _selection.gapGlobalFrame,
        activeCutId: _project.activeCutId,
        localFrame: _controllers.timelineController.currentFrameIndex,
      ) ??
      _selection.editingGlobalFrame;

  /// 🚨★★★THE TRACK AXIS's landing — one place, the way the cut axis has
  /// its own. The start of the film is the only floor; rightward past the
  /// last cut is a place you may stand. F-21: a step that falls through the
  /// floor lands ON it rather than doing nothing — the layer row's law, on
  /// the axis this row counts.
  ///
  /// ↩️The V row and a gap's one-frame step each wrote this landing in
  /// their own words — one floored, the other refused — and the
  /// storyboard's own rows were about to be a third.
  void _land(int landing, {required int from, TrackFrameAxis? onAxis}) {
    final floored = landing < 0 ? 0 : landing;
    if (floored != from) {
      _selection.selectGlobalFrame(floored, onAxis: onAxis);
    }
  }
}

/// THE flip's column on a layer row at [frame] — the row's own blocks,
/// whatever they are made of (R10 #13: 「whatever the row is, count THAT
/// row's blocks」), on whichever axis the row is walked.
///
/// A7① (2026-08-17): a HOLD is one flip unit — the column absorbs hold-mode
/// ghost tails/lead-ins into their owning run, so the flip never lands
/// inside a hold the HUD draws as empty. Repeat ghosts stay their own
/// columns; the merge lives HERE, in the flip's column definition only
/// (creation gates, painters and playback keep reading raw coverage).
///
/// The TRANSITION row's blocks are its SPANS, and they live in its
/// instruction map rather than on its timeline
/// ([LayerKind.bandIsInstructionsOnly]) — so the flip counted nothing there
/// and walked it a frame at a time while the row drew, outlined and edited
/// spans (the storyboard's standing outline: 「The transition row's blocks
/// are its SPANS」).
FlipColumn? flipColumnOfRow(Layer layer, int frame) {
  if (layer.kind.bandIsInstructionsOnly) {
    final span = instructionSpanCovering(layer.instructions, frame);
    return span == null
        ? null
        : (start: span.key, endExclusive: span.key + span.value.length);
  }
  return holdMergedFlipColumnAt(layer, frame);
}
