import '../models/layer_id.dart';
import 'history_step_scope.dart';
import 'project_repository.dart';

/// A history step as the tracks' conte structures take it (F-343) — the
/// [HistoryStepScope] the session gives its history.
///
/// ① A step is ONE write of the structures
/// ([ProjectRepository.asOneConteWrite]): a step that takes a row out of
/// every cut's conte, or puts it back, does it cut by cut.
///
/// ② The rows the structure GAVE the cuts in a step go with the step's
/// undo ([ProjectRepository.dropConteFills]). The step's own undo takes
/// back what it did in its cut — the row it mounted on the conte, the
/// folder it made, the conte it made of a row — and the empty rows the
/// other cuts were given for it would keep that row in the structure: the
/// undo would not be one. Nothing else can tell them from rows the user
/// drew on — a picture is not in the model — but the undo can: everything
/// done after its step is undone already.
final class ConteStepScope implements HistoryStepScope {
  ConteStepScope(this._repository);

  final ProjectRepository _repository;

  @override
  Object? execute(void Function() write) => _given(write);

  @override
  void undo(void Function() write, List<Object> made) {
    _repository.asOneConteWrite(() {
      write();
      _repository.dropConteFills({
        for (final given in made) ...given as Set<LayerId>,
      });
    });
  }

  @override
  Object? redo(void Function() write) => _given(write);

  Set<LayerId>? _given(void Function() write) {
    final given = _repository.asOneConteWrite(write);
    return given.isEmpty ? null : given;
  }
}
