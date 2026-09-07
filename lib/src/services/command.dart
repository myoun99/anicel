abstract class Command {
  String get description;

  void execute();

  void undo();
}

/// Commands that retain SURFACE SNAPSHOTS as their undo payload (R19
/// P3b) report their approximate weight so the history stack can
/// byte-trim its deep end — a run of full-canvas fills at 8000² retains
/// ~256MB per entry, which the entry-count cap alone would never bound.
abstract interface class RetainedBytesCommand {
  int get estimatedRetainedBytes;
}

/// What a RUN of commands weighs. Both callers are the same question
/// asked of a different list — a composite's children, and each of the
/// history stacks — so they are the same code.
int retainedBytesOf(Iterable<Command> commands) => commands
    .whereType<RetainedBytesCommand>()
    .fold(0, (sum, command) => sum + command.estimatedRetainedBytes);

/// Several commands as ONE undo step: executes in order, undoes in
/// reverse. For flows where one user action legitimately touches two
/// stores (e.g. adding an instruction also writes its memo shorthand into
/// the cut note) without splitting the undo.
/// ⚠️It is a [RetainedBytesCommand] because WRAPPING MUST NOT HIDE
/// WEIGHT. A composite that did not report simply vanished from the byte
/// budget along with everything inside it, and one of the ~30 places that
/// build one wraps a brush stroke — so the entries the budget most needed
/// to see were the ones it could not.
class CompositeCommand implements Command, RetainedBytesCommand {
  CompositeCommand({required this.description, required this.commands});

  @override
  final String description;

  final List<Command> commands;

  @override
  int get estimatedRetainedBytes => retainedBytesOf(commands);

  @override
  void execute() {
    for (final command in commands) {
      command.execute();
    }
  }

  @override
  void undo() {
    for (final command in commands.reversed) {
      command.undo();
    }
  }
}
