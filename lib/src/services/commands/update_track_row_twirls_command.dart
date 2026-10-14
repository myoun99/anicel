import '../../models/layer_id.dart';
import '../../models/track_row_twirls.dart';
import '../../models/track_transform_lane_carrier.dart';
import '../command.dart';
import '../project_repository.dart';

/// A TRACK's own row twirled as [twirls] say — an S row, or the V row by
/// its lane carrier ([trackRowTwirlsOf]) — in one undo step (F-360).
///
/// The row's alone: a track's own row is in no link group and wears no
/// head (the head's walk answers it with itself), and no cut holds it, so
/// none is asked for — the storyboard twirls it standing between cuts.
///
/// ↩️The storyboard kept these twirls itself, session-only — the last ones
/// a file did not keep (유저 2026-10-14: 「fx나 폴더나 이런 접음/펼침상태가
/// 기록이 안되는건지? 제대로 기록되도록」).
class UpdateTrackRowTwirlsCommand implements Command {
  UpdateTrackRowTwirlsCommand({
    required this.repository,
    required this.rowId,
    required this.twirls,
  });

  final ProjectRepository repository;
  final LayerId rowId;
  final RowTwirls twirls;

  RowTwirls? _before;

  @override
  String get description => 'Twirl track row $rowId';

  @override
  void execute() {
    _before ??= trackRowTwirlsOf(repository.requireProject(), rowId);
    _write(twirls);
  }

  @override
  void undo() {
    final before = _before;
    if (before == null) {
      throw StateError('Command has not been executed.');
    }
    _write(before);
  }

  void _write(RowTwirls twirls) {
    final (:lanesExpanded, :expandedLaneGroups) = twirls;
    if (trackIdOfTransformLaneCarrier(rowId) case final trackId?) {
      repository.updateTrackLanes(
        trackId: trackId,
        lanesExpanded: lanesExpanded,
        expandedLaneGroups: expandedLaneGroups,
      );
      return;
    }
    repository.updateLayer(
      layerId: rowId,
      update: (row) => row.copyWith(
        lanesExpanded: lanesExpanded,
        expandedLaneGroups: expandedLaneGroups,
      ),
    );
  }
}
