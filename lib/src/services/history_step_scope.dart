/// How a `HistoryManager`'s steps are run against the project behind it —
/// the hook its session gives it (`ConteStepScope`, F-343).
///
/// A step's writes can make what its own undo does not take back: a write
/// is laid by the repository's invariants as well, and those answer the
/// project as it stands, not the step. What each NEW step made is handed
/// back here by its undo.
abstract interface class HistoryStepScope {
  /// Runs a new step's [write], and says what it made that its undo must
  /// take back — null for nothing.
  Object? execute(void Function() write);

  /// Runs a step's undo [write], taking back what the step [made].
  void undo(void Function() write, List<Object> made);

  /// Runs a step's redo [write], and says what it made — as [execute].
  Object? redo(void Function() write);
}
