import '../models/cut_id.dart';
import '../models/layer_id.dart';
import '../models/track_row_twirls.dart';
import '../services/command.dart';
import '../services/commands/update_layer_lane_group_expanded_command.dart';
import '../services/commands/update_layer_lanes_expanded_command.dart';
import '../services/commands/update_track_row_twirls_command.dart';
import '../services/history_manager.dart';
import '../services/project_lookup.dart';
import '../services/project_repository.dart';

/// Where a row's twirls are written — its property lanes, and the groups
/// among them — for `LayerController`, which hands it the cut a row is
/// written in.
///
/// Split from the controller when F-396 took it past six hundred lines
/// (`clean_code_stays_measured_test`): the twirls were the one family in it
/// with a step of their own to hand out ([laneGroupShownCommand]).
class RowTwirlWriter {
  RowTwirlWriter({
    required ProjectRepository repository,
    required HistoryManager historyManager,
    required CutId? Function(LayerId rowId) cutOfRow,
  }) : _repository = repository,
       _historyManager = historyManager,
       _cutOfRow = cutOfRow;

  final ProjectRepository _repository;
  final HistoryManager _historyManager;

  /// The cut a row is written in — null for a track's own row in a gap.
  final CutId? Function(LayerId rowId) _cutOfRow;

  /// The row's property-lane twirl — the fx and Transform lanes live under
  /// it — on every row of its head ([UpdateLayerLanesExpandedCommand]), or
  /// on a track's own row alone ([_twirled]).
  void toggleLayerLanes(LayerId layerId) => _twirled(
    layerId,
    onItsTrack: (was) => (
      lanesExpanded: !was.lanesExpanded,
      expandedLaneGroups: was.expandedLaneGroups,
    ),
    inItsCut: (cutId) => UpdateLayerLanesExpandedCommand(
      repository: _repository,
      cutId: cutId,
      layerId: layerId,
      expanded: !requireLayerAnywhere(
        _repository.requireProject(),
        layerId,
      ).lanesExpanded,
    ),
  );

  /// [laneId]'s group inside the row's twirl-down, twirled to [expanded] on
  /// every row of its head ([UpdateLayerLaneGroupExpandedCommand]), or on a
  /// track's own row alone ([_twirled]).
  void setLayerLaneGroupExpanded(
    LayerId layerId,
    String laneId, {
    required bool expanded,
  }) => _twirled(
    layerId,
    onItsTrack: (was) => (
      lanesExpanded: was.lanesExpanded,
      expandedLaneGroups: expanded
          ? {...was.expandedLaneGroups, laneId}
          : ({...was.expandedLaneGroups}..remove(laneId)),
    ),
    inItsCut: (cutId) => UpdateLayerLaneGroupExpandedCommand(
      repository: _repository,
      cutId: cutId,
      layerId: layerId,
      laneId: laneId,
      expanded: expanded,
    ),
  );

  /// Where [rowId]'s twirl is written, in one step either way: a TRACK's
  /// own row — an S row, the V row by its lane carrier ([trackRowTwirlsOf])
  /// — on its track, as [onItsTrack] turns it
  /// ([UpdateTrackRowTwirlsCommand]); a row a cut holds on its head, by
  /// [inItsCut], in its own cut ([_cutOfRow]).
  ///
  /// ⚠️A track's own row not as every other write of a row goes
  /// (`LayerController`'s, in its own cut): no cut holds it, and in a gap
  /// there is none to address it in — the storyboard, which stands there,
  /// twirls its S and V rows all the same.
  void _twirled(
    LayerId rowId, {
    required RowTwirls Function(RowTwirls was) onItsTrack,
    required Command Function(CutId cutId) inItsCut,
  }) {
    final command = _twirlCommand(
      rowId,
      onItsTrack: onItsTrack,
      inItsCut: inItsCut,
    );
    if (command != null) {
      _historyManager.execute(command);
    }
  }

  /// [_twirled]'s step, unrun — null for a track's own row in a gap, which
  /// no cut addresses.
  Command? _twirlCommand(
    LayerId rowId, {
    required RowTwirls Function(RowTwirls was) onItsTrack,
    required Command Function(CutId cutId) inItsCut,
  }) {
    final was = trackRowTwirlsOf(_repository.requireProject(), rowId);
    if (was == null) {
      final cutId = _cutOfRow(rowId);
      return cutId == null ? null : inItsCut(cutId);
    }
    return UpdateTrackRowTwirlsCommand(
      repository: _repository,
      rowId: rowId,
      twirls: onItsTrack(was),
    );
  }

  /// The step that leaves [laneId]'s group SHOWN on [rowId]: the row's
  /// lanes twirled down and the group open among them, by the twirls'
  /// own commands ([_twirlCommand]). Null where both already stand open.
  ///
  /// 🗣️F-396 (유저 2026-10-18): 「레이어 fx펼침 접은상태에서 fx추가하면
  /// 펼치고 해당 fx헤더도 펼치도록. 그래야 처음 사용하는 입장에서
  /// 알기쉬움」 — an add runs it in its own undo step.
  Command? laneGroupShownCommand(LayerId rowId, String laneId) {
    final was = rowTwirlsOf(_repository.requireProject(), rowId);
    if (was == null ||
        (was.lanesExpanded && was.expandedLaneGroups.contains(laneId))) {
      return null;
    }
    return _twirlCommand(
      rowId,
      onItsTrack: (was) => (
        lanesExpanded: true,
        expandedLaneGroups: {...was.expandedLaneGroups, laneId},
      ),
      inItsCut: (cutId) => oneStepOf('Show lane group', [
        UpdateLayerLanesExpandedCommand(
          repository: _repository,
          cutId: cutId,
          layerId: rowId,
          expanded: true,
        ),
        UpdateLayerLaneGroupExpandedCommand(
          repository: _repository,
          cutId: cutId,
          layerId: rowId,
          laneId: laneId,
          expanded: true,
        ),
      ])!,
    );
  }
}
