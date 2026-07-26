import '../../models/cut_id.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../project_repository.dart';

/// Resequences a track's cuts — THE cut-order edit.
///
/// It carries both orders rather than an index pair because the move that
/// produces it is not always one cut's: a storyboard drag can carry a whole
/// selected run past a neighbour, and unwinding that as a series of
/// single-cut moves would be several undo steps for one gesture.
class SetCutOrderCommand implements Command {
  SetCutOrderCommand({
    required this.repository,
    required this.trackId,
    required this.order,
  });

  final ProjectRepository repository;
  final TrackId trackId;
  final List<CutId> order;

  List<CutId>? _originalOrder;
  bool _hasExecuted = false;

  @override
  String get description => 'Reorder cuts on track $trackId';

  @override
  void execute() {
    _originalOrder ??= _currentOrder();
    repository.setCutOrder(trackId: trackId, order: order);
    _hasExecuted = true;
  }

  @override
  void undo() {
    final originalOrder = _originalOrder;
    if (!_hasExecuted || originalOrder == null) {
      throw StateError('Command has not been executed.');
    }

    repository.setCutOrder(trackId: trackId, order: originalOrder);
  }

  List<CutId> _currentOrder() {
    final project = repository.requireProject();
    for (final track in project.tracks) {
      if (track.id != trackId) {
        continue;
      }
      return [for (final cut in track.cuts) cut.id];
    }

    throw StateError('Track not found: $trackId');
  }
}
