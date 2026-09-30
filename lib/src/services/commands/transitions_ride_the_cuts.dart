import '../../models/layer.dart';
import '../../models/track_id.dart';
import '../../models/track_transitions.dart';
import '../project_repository.dart';

/// What a command that moves cuts owes the transition rows (유저 2026-08-10:
/// 「움직일때만 앵커로서 앞 컷에 앵커」): every track's row carried to where
/// its cuts went ([transitionRowFollowingItsCuts]) in the SAME step, and put
/// back first on the way back — so an undo lands the row exactly where it
/// was, whatever the layout it is undone into.
///
/// ⛔Owned by the commands that write a cut layout, never by their doors: a
/// cut moves through a trim, a gap, a paste, a delete, a reorder, an import,
/// and a door that forgot would leave an O.L standing where the boundary it
/// was drawn across used to be — which every one of them did until this
/// (F-227-ol-follows). `a_layout_command_carries_the_transitions_test` holds
/// the list.
class TransitionsRideTheCuts {
  TransitionsRideTheCuts(this._repository);

  final ProjectRepository _repository;

  /// The rows [carry] moved, as they were — what [carryBack] puts back.
  final Map<TrackId, Layer> _left = {};

  /// Runs [edit] — the command's own move of cuts — then carries every
  /// track's transition row to where its cuts went.
  void carry(void Function() edit) {
    final before = _repository.requireProject();
    edit();
    _left.clear();
    for (final track in _repository.requireProject().tracks) {
      final was = before.tracks.where((t) => t.id == track.id).firstOrNull;
      if (was == null) {
        continue;
      }
      final carried = transitionRowFollowingItsCuts(before: was, after: track);
      if (identical(carried, track.transitionLayer)) {
        continue;
      }
      _left[track.id] = track.transitionLayer;
      _repository.updateTrackTransitionLayer(
        trackId: track.id,
        transitionLayer: carried,
      );
    }
  }

  /// Puts back every row [carry] moved, then runs [edit] — the command's
  /// undo of its move.
  void carryBack(void Function() edit) {
    for (final MapEntry(key: trackId, value: row) in _left.entries) {
      _repository.updateTrackTransitionLayer(
        trackId: trackId,
        transitionLayer: row,
      );
    }
    _left.clear();
    edit();
  }
}
