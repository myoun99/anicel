import 'cels_ahead.dart';

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
  /// 🚨★★★**WHICH SIDE IS LIVE CHANGES THE ANSWER, and the entry cannot
  /// know it on its own.** An entry that holds a BEFORE and an AFTER owes
  /// only the half the cel is not currently showing: applied, the cel is
  /// the after and the before is what nobody else holds; undone, the cel
  /// has been put back to the before and it is the AFTER that is held by
  /// this entry alone.
  ///
  /// It reported the before either way, so a stroke that only CREATED
  /// tiles — every stroke reaching fresh paper — billed almost nothing
  /// once undone while holding every tile it had made. 🧪Measured on 40
  /// such strokes: **11.5 MiB billed while applied, 18.5 MiB actually
  /// pinned once undone.**
  ///
  /// ⚠️Only the stacks know, so only they may answer: [undone] is true
  /// exactly for the REDO stack. ⛔Commands that hold one payload rather
  /// than a pair ignore it, and say so where they implement this.
  int estimatedRetainedBytes({required bool undone});
}

/// What a RUN of commands weighs, with [undone] saying which side of each
/// pair the cel is currently showing. Both callers are the same question
/// asked of a different list — a composite's children, and each of the
/// history stacks — so they are the same code.
int retainedBytesOf(Iterable<Command> commands, {required bool undone}) =>
    commands.whereType<RetainedBytesCommand>().fold(
      0,
      (sum, command) => sum + command.estimatedRetainedBytes(undone: undone),
    );

/// Commands that can move their undo payload to the run's 휘발성 room
/// instead of being deleted when the byte budget is exceeded.
///
/// 🚨★★★**PARK EVERY SURFACE THE ENTRY HOLDS, not only the one it is
/// BILLED for.** Those are two different questions and this is the
/// dangerous place to conflate them. An entry is billed for its
/// pre-surface alone, because a stroke's post-surface IS the next
/// stroke's pre-surface and charging both counted a neighbour's bytes
/// twice. But that same sharing means a pre-surface let go on its own
/// frees NOTHING — the tiles stay alive through the previous entry's
/// post. So the bill names one surface and the park names all of them,
/// and [HistoryManager] parks a contiguous deep PREFIX so both ends of
/// every shared tile go together.
abstract interface class ParkableCommand {
  /// False = the room refused, and the bytes are still in RAM.
  Future<bool> parkPayload();

  /// The entry is leaving the stack: anything it parked is now
  /// unreachable, so the room takes it back.
  ///
  /// ⚠️Without this, every entry the budget ever shed after parking would
  /// leave a file behind until the run ended — a store that grows for as
  /// long as the session does, which is the shape of the problem this
  /// tier exists to solve.
  void dropPayload();
}

/// Parks a RUN of commands — the composite's children and, one entry at a
/// time, the history stacks.
///
/// ⚠️A partial park counts as a refusal: an entry stops holding RAM only
/// when everything it holds has moved, so half of it on disk is the cost
/// of a write with none of the benefit.
Future<bool> parkPayloadsOf(Iterable<Command> commands) async {
  var parked = true;
  for (final command in commands.whereType<ParkableCommand>()) {
    if (!await command.parkPayload()) {
      parked = false;
    }
  }
  return parked;
}

/// Gives the room back everything a RUN of commands parked.
void dropPayloadsOf(Iterable<Command> commands) {
  for (final command in commands.whereType<ParkableCommand>()) {
    command.dropPayload();
  }
}

/// Several commands as ONE undo step: executes in order, undoes in
/// reverse. For flows where one user action legitimately touches two
/// stores (e.g. adding an instruction also writes its memo shorthand into
/// the cut note) without splitting the undo.
/// ⚠️It is a [RetainedBytesCommand] because WRAPPING MUST NOT HIDE
/// WEIGHT. A composite that did not report simply vanished from the byte
/// budget along with everything inside it, and one of the ~30 places that
/// build one wraps a brush stroke — so the entries the budget most needed
/// to see were the ones it could not.
class CompositeCommand
    implements
        Command,
        RetainedBytesCommand,
        ParkableCommand,
        PictureRestoringCommand {
  CompositeCommand({required this.description, required this.commands});

  @override
  final String description;

  final List<Command> commands;

  @override
  int estimatedRetainedBytes({required bool undone}) =>
      retainedBytesOf(commands, undone: undone);

  /// ⚠️For the same reason the weight forwards: a composite that did not
  /// forward would be an entry the spill could never move, so the budget
  /// would fall back to DELETING exactly the entries that wrap a stroke.
  @override
  Future<bool> parkPayload() => parkPayloadsOf(commands);

  @override
  void dropPayload() => dropPayloadsOf(commands);

  /// In the order the step runs the children: a later one leans on what an
  /// earlier one put back, and [CelsAhead] carries that along.
  @override
  void readAhead(CelsAhead cels, {required bool undo}) {
    final ordered = undo ? commands.reversed : commands;
    for (final command in ordered.whereType<PictureRestoringCommand>()) {
      command.readAhead(cels, undo: undo);
    }
  }

  @override
  void dropReadAhead() => dropReadAheadOf(commands);

  @override
  void visitHeldTiles(HeldTileVisitor visit, {required bool undone}) {
    for (final command in commands.whereType<PictureRestoringCommand>()) {
      command.visitHeldTiles(visit, undone: undone);
    }
  }

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
