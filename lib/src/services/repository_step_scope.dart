import 'history_step_scope.dart';
import 'project_repository.dart';

/// A history step as the repository's invariants take it — the
/// [HistoryStepScope] the session gives its history. ↩️`ConteStepScope`
/// until 2026-11-12, when ④ joined the conte's three.
///
/// ① A step is ONE write of the structures
/// ([ProjectRepository.asOneConteWrite]): a step that takes a row out of
/// every cut's conte, or puts it back, does it cut by cut (F-343).
///
/// ② The rows the structure GAVE the cuts in a step go with the step's
/// undo ([ProjectRepository.dropConteFills]). The step's own undo takes
/// back what it did in its cut — the row it mounted on the conte, the
/// folder it made, the conte it made of a row — and the empty rows the
/// other cuts were given for it would keep that row in the structure: the
/// undo would not be one. Nothing else can tell them from rows the user
/// drew on — a picture is not in the model — but the undo can: everything
/// done after its step is undone already.
///
/// ③ The heads the structure PUT ON rows that joined a conte in a step go
/// with the step's undo too ([ProjectRepository.takeOffConteHeads]): a row
/// made a cut's conte wears its track's head, and the step's own undo
/// gives back only what the step wrote — the kind — while no laying lays
/// a row that is in no conte (F-424).
///
/// ④ The links the always-mirror pass GAVE the synced attach rows in a
/// step, and the empty cels it minted for them, go with the step's undo
/// ([ProjectRepository.dropAttachedMirrors]) for ②'s reason: the step's
/// own undo takes back the base cel it made, and the pass only ever adds
/// (관제 2026-11-12, card
/// `undo-leaves-empty-mirror-cels-on-a-synced-attach-row`).
final class RepositoryStepScope implements HistoryStepScope {
  RepositoryStepScope(this._repository);

  final ProjectRepository _repository;

  @override
  Object? execute(void Function() write) => _made(write);

  @override
  void undo(void Function() write, List<Object> made) {
    final steps = made.cast<ConteWriteMade>();
    _repository.asOneConteWrite(() {
      write();
      _repository.dropConteFills({for (final step in steps) ...step.fills});
      _repository.takeOffConteHeads([
        for (final step in steps) ...step.heads,
      ]);
      _repository.dropAttachedMirrors([
        for (final step in steps) ...step.mirrors,
      ]);
    });
  }

  @override
  Object? redo(void Function() write) => _made(write);

  ConteWriteMade? _made(void Function() write) {
    final made = _repository.asOneConteWrite(write);
    return made.fills.isEmpty && made.heads.isEmpty && made.mirrors.isEmpty
        ? null
        : made;
  }
}
