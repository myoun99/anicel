import '../../models/flip_column_step.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_coverage.dart' show coveringDrawingBlockAt;
import '../../models/track_frame_axis.dart';
import '../../models/timeline_run_behavior.dart' show TimelineRunEdgeMode;
import '../../models/track_conte_row.dart';
import '../../models/track_id.dart';
import '../storyboard_layer_policy.dart' show trackConteRowShown;
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

  /// The V row's flip: the track's CUTS are its columns, on the global axis.
  ///
  /// 🗣️I-73 (유저 2026-10-08): 「v행에서는 콘티블록에 서있다거나 하는걸
  /// 안하도록 … 컷 선택만 되도록」 — the V row's blocks are its cuts, and a
  /// flip counts the row's own blocks (R10 #13). ↩️It counted PANELS from
  /// 2026-09-24 (「콘티레이어 있으면 콘티레이어 블록기준」) while the panels
  /// were drawn inside the cut block; they have a row of their own now, and
  /// that walk is that row's ([flipTrackRow]).
  ///
  /// This is also the axis a GAP is walked on: `selectGlobalFrame` lands
  /// the result inside a cut or parks it in the void, so a playhead
  /// standing between cuts can step out under its own power.
  ///
  /// The same step the layer row takes, with the track's cuts as the
  /// covering material instead of a layer's blocks, which is the whole
  /// point of stating the rule as columns. It carried the identical
  /// key-stepping defect before, so a gap between two cuts was skipped in
  /// both directions here too.
  void flipCuts(TrackId trackId, {required bool forward}) {
    // The MEMOIZED axis (kept beside the layout it narrows): a flip step
    // is a per-move cost, and rebuilding the whole cross-track layout for
    // each one is exactly the tax that memo exists to remove.
    final axis = _projectSettings.axisForTrack(trackId);
    if (axis.isEmpty) {
      return;
    }
    final from = _from(axis);
    _land(
      flipColumnStep(
        frame: from,
        direction: forward ? 1 : -1,
        columnAt: (frame) {
          final cut = axis.cutBlockAt(frame);
          return cut == null
              ? null
              : (start: cut.startIndex, endExclusive: cut.endIndexExclusive);
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
  ///
  /// The track's CONTE row is a row of this rail too — the cuts' conte
  /// layers as the storyboard draws them, one row of blocks on the track's
  /// axis ([trackConteRowShown]) — so its flip counts its PANELS, and a step
  /// off a cut's last panel lands on the next cut's first.
  ///
  /// 🗣️유저 2026-09-24: 「콘티패널에서는 플립이 타임라인패널이랑 같은 규칙으로
  /// 설정한 상태로 블록/프레임별로 이동. 콘티레이어 있으면 콘티레이어
  /// 블록기준」 — said of the V row while the panels were drawn inside the
  /// cut block; they have this row now (I-73), and the V row counts its cuts
  /// again ([flipCuts]). ↩️A cut with no conte layer was one block of that
  /// walk; it holds no block of this row, so it is walked a frame at a time
  /// like any stretch a row leaves empty.
  void flipTrackRow(LayerId layerId, {required bool forward}) {
    final track = _trackSe.trackOwnedRailOwner(layerId);
    if (track == null) {
      return;
    }
    final axis = _projectSettings.axisForTrack(track.id);
    final layer = trackIdOfConteRow(layerId) != null
        ? trackConteRowShown(track.id, axis.entries)
        : track.transitionLayer.id == layerId
        ? track.transitionLayer
        : track.seLayers.where((row) => row.id == layerId).firstOrNull;
    if (layer == null) {
      return;
    }
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
        parkedGlobalFrame: _timeline.editingSession.gapGlobalFrame,
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
/// row's blocks」), on whichever axis the row is walked. A REPEAT's ghost is
/// a column of its own, as it is a block of its own on the row; a HOLD's
/// ghost is no column at all — the flip walks it a frame at a time, as it
/// walks empty space.
///
/// 🗣️F-245 (유저 2026-10-01, 「그게 아님」): 「1(홀드)---- 일경우 1에
/// 서있을때 오른쪽 플립하면 두번째인 - 로 이동되는건 좋음. 근데 그 다음
/// 플립에서도 세번째 -, 네번째 -으로 이동되야한단거임. 일반 1프레임이동이랑
/// 똑같이. 즉 리피트는 고스트프레임을 블록으로 인식해서 걸어가지만 홀드는
/// 빈공간으로 인식해서 플립이 1프레임마다」. ↩️The first reading (09-30,
/// `92882710a`) of 「리피트는 리피트도 블록으로 인식해서 플립해도 되는데,
/// 홀드는 그냥 블록으로 인식해서 안넘어가도록. 즉 1홀드----x이면, 지금
/// 1에있는상태에서 오른쪽누르면 x로 이동하는데, 그게아니라 블록 다음칸 그냥
/// 평범하게 가도록」 made the hold ONE column of its own, so the second step
/// leapt it whole. ↩️A7① (2026-08-18, 「홀드 블록을 한 단위로 건너뛰어」)
/// had absorbed it into the run it holds before that.
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
  final block = coveringDrawingBlockAt(layer.timeline, frame);
  if (block == null || block.entry.ghostOf?.mode == TimelineRunEdgeMode.hold) {
    return null;
  }
  return (start: block.startIndex, endExclusive: block.endIndexExclusive);
}
