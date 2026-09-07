import 'package:flutter/foundation.dart';

import 'command.dart';
import 'memory_pressure_budget.dart';

/// The undo byte budget for THIS machine — physical RAM/8, clamped.
///
/// 유저 확정 (2026-09-07, `undo-commands-audit-Q3` = `ram8`): the undo
/// stack was the last budget in the app still assuming a desktop while
/// the cel store beside it already scaled with the machine
/// (`deviceScaledHotCelBudget`, RAM/4). Two fixed budgets on a 2GB tablet
/// reserved 45% of it between them.
///
/// RAM/8 rather than the store's RAM/4 because the two must SUM to
/// something a small machine survives, and of the pair the store is the
/// one feeding the screen. It is also GIMP's number for the same job
/// (`undo-size`, physical memory / 8).
///
/// ⚠️The ceiling is today's fixed value, so this can only ever LOWER a
/// machine's budget, never raise one. The floor is two full-canvas 4000²
/// transforms (64 MiB each, measured 2026-09-07) — below that the stack
/// cannot hold one edit and its predecessor, which is not a budget but an
/// off switch.
int deviceScaledUndoByteBudget({required int? physicalMemoryBytes}) =>
    deviceScaledBudget(
      physicalMemoryBytes: physicalMemoryBytes,
      divisor: 8,
      floor: 128 * 1024 * 1024,
      ceiling: HistoryManager.retainedByteBudget,
    );

/// The undo/redo stacks. A [ChangeNotifier] so stack-state consumers (the
/// app bar's undo/redo buttons) can subscribe directly: brush strokes
/// execute here from the canvas WITHOUT a session notify, so nothing else
/// would ever tell them a stroke landed.
class HistoryManager extends ChangeNotifier {
  HistoryManager({this.maxEntries = defaultMaxEntries})
    : assert(maxEntries > 0);

  /// Undo-depth cap. The stack previously grew for the whole session —
  /// brush strokes land here at drawing speed, so long sessions pinned
  /// thousands of command objects (an accumulation source behind the
  /// progressive brush lag). Deep enough that nobody undoes past it in
  /// practice; the brush coordinator's own bitmap history is far shorter
  /// anyway.
  static const int defaultMaxEntries = 200;

  /// Byte cap for the surface snapshots the stack's [RetainedBytesCommand]
  /// entries retain (R19 P3b): undo pixels are bounded even when every
  /// entry is a full-canvas fill — the deepest entries fall off first,
  /// PS-style, and the newest entry always survives.
  ///
  /// ⚠️Now the CEILING rather than the number every machine gets: the
  /// session sets [byteBudget] from RAM ([deviceScaledUndoByteBudget]),
  /// and a machine that will not say how much it has keeps this.
  ///
  /// ⛔It bounded nothing until 2026-09-07. Three of the five commands
  /// that hold pixels misreported their weight — one by 2048× — so the
  /// sweep below never had a total worth sweeping, and the only real
  /// bound on undo pixels was [defaultMaxEntries].
  static const int retainedByteBudget = 512 * 1024 * 1024;

  /// 🚨WHERE PRESSURE PUTS IT. [respondToMemoryPressure] drops the live
  /// budget straight to this and sweeps at once.
  ///
  /// ⚠️A DROP, not the cel store's halving, and deliberately so: an
  /// over-budget cel COOLS (its bytes survive in the cold tier, and
  /// promoting it back costs a decode), while an over-budget undo entry is
  /// DELETED. That asymmetry is why the store can afford a gentle cut and
  /// this cannot afford to keep the bytes at all.
  ///
  /// ⚠️This number is MY judgement, not a measurement (2026-08-27). What is
  /// measured is that the old behaviour was wrong: the stack held its full
  /// 512 MB through a memory warning while the store beside it halved, and
  /// a MOVE retains a PRE and a POST full-canvas surface per confirm — on a
  /// 4000×4000 cel that is 128 MB a transform, so the third or fourth one
  /// crosses half a gigabyte. That is exactly where the user's iPhone died
  /// (「세번째, 네번째 변형쯤에서 말없이 앱 종료됨」).
  ///
  /// ⛔It is not a device-class check. 유저 방침: 구형 기기에서도 돌아야 하고
  /// 「최소 사양을 올려 해결」은 내가 고를 안이 아니다 — so the answer is to
  /// hold less when the OS says to, on every device.
  static const int retainedByteBudgetUnderPressure = 64 * 1024 * 1024;

  final int maxEntries;

  /// The cap in force. Lowered by [respondToMemoryPressure], never raised —
  /// and the lowers-only guard is now [MemoryPressureBudget]'s, the same
  /// object `BrushFrameStore` holds. This class used to describe that
  /// sharing in a comment while keeping its own copy of the code.
  final MemoryPressureBudget _budget = MemoryPressureBudget.droppingTo(
    normal: retainedByteBudget,
    underPressure: retainedByteBudgetUnderPressure,
  );

  final List<Command> _undoStack = <Command>[];
  final List<Command> _redoStack = <Command>[];

  bool get canUndo => _undoStack.isNotEmpty;

  bool get canRedo => _redoStack.isNotEmpty;

  int get undoCount => _undoStack.length;

  int get redoCount => _redoStack.length;

  /// The cap in force, which the session sets from the machine's RAM
  /// ([deviceScaledUndoByteBudget]). Assigning states a new normal;
  /// pressure lowers it separately and is never raised by that act.
  int get byteBudget => _budget.bytes;

  set byteBudget(int value) => _budget.bytes = value;

  /// Bytes the snapshot entries currently report — BOTH stacks
  /// (accumulation-guard oracle).
  ///
  /// 🚨REDO COUNTS. [_step] moves an entry between the stacks without
  /// changing what it holds, so a version of this that only walked
  /// [_undoStack] watched half a gigabyte leave the books by being
  /// undone — and a memory warning arriving right then freed nothing,
  /// because by the budget's own reckoning there was nothing to free.
  int get retainedBytes =>
      retainedBytesOf(_undoStack) + retainedBytesOf(_redoStack);

  /// Collects everything executed inside [body] into ONE undo entry.
  ///
  /// ⑨ needs it: deleting a row SELECTION is several coordinator verbs, and
  /// each already knows how to compose its own cascade (a folder dissolves,
  /// a base takes its riders with it). Asking them to hand commands back
  /// instead of running them would mean rewriting every one of those
  /// branches; wrapping the executor leaves them intact and still gives the
  /// user what they did — one gesture, one undo.
  ///
  /// Nesting is a no-op (the outermost group wins), so a verb that groups
  /// internally stays safe to call from inside one.
  void runAsOneStep(String description, void Function() body) {
    if (_group != null) {
      body();
      return;
    }
    final group = <Command>[];
    _group = group;
    try {
      body();
    } finally {
      _group = null;
    }
    if (group.isEmpty) {
      return;
    }
    // Already executed: this pushes them as one entry rather than running
    // anything a second time.
    _push(
      group.length == 1
          ? group.single
          : CompositeCommand(description: description, commands: group),
    );
  }

  List<Command>? _group;

  void execute(Command command) {
    command.execute();
    final group = _group;
    if (group != null) {
      group.add(command);
      return;
    }
    _push(command);
  }

  void _push(Command command) {
    _undoStack.add(command);
    if (_undoStack.length > maxEntries) {
      // The oldest commands fall off the deep end, PS-style.
      _undoStack.removeRange(0, _undoStack.length - maxEntries);
    }
    _trimRetainedBytes();
    _redoStack.clear();
    notifyListeners();
  }

  /// 🚨THE OS SAID MEMORY IS TIGHT — and this stack used to be deaf to it.
  ///
  /// `didHaveMemoryPressure` already reached `BrushFrameStore`, which halves
  /// its cel budget and cools at once. The undo stack, holding up to half a
  /// gigabyte of full-canvas surface snapshots beside it, heard nothing and
  /// kept every byte. On iOS the warning is the last thing before the kill.
  ///
  /// ⛔The newest entry always survives, exactly as the budget sweep
  /// guarantees: pressure must not cost you the undo you are about to press.
  void respondToMemoryPressure() {
    if (!_budget.respondToMemoryPressure()) {
      return; // Pressure only ever lowers.
    }
    final before = _undoStack.length;
    _trimRetainedBytes();
    if (_undoStack.length != before) {
      notifyListeners();
    }
  }

  void _trimRetainedBytes() {
    var total = retainedBytes;
    if (total <= _budget.bytes) {
      return;
    }
    // REDO SHEDS FIRST. A redo entry is work the user already stepped
    // back from, and the next execute() throws the whole stack away in
    // any case — spending the budget on it while a real undo falls off
    // the deep end is the wrong trade.
    total -= _shed(_redoStack, total - _budget.bytes, keep: 0);
    if (total <= _budget.bytes) {
      return;
    }
    // ⛔The newest entry always survives: pressure must not cost you the
    // undo you are about to press.
    _shed(_undoStack, total - _budget.bytes, keep: 1);
  }

  /// Drops entries from [stack]'s deep end until [excess] bytes are gone,
  /// never leaving fewer than [keep]. Returns the bytes released.
  static int _shed(List<Command> stack, int excess, {required int keep}) {
    var released = 0;
    var dropCount = 0;
    while (released < excess && stack.length - dropCount > keep) {
      final command = stack[dropCount];
      if (command is RetainedBytesCommand) {
        released += (command as RetainedBytesCommand).estimatedRetainedBytes;
      }
      dropCount += 1;
    }
    if (dropCount > 0) {
      stack.removeRange(0, dropCount);
    }
    return released;
  }

  /// Called before undo/redo touches the stacks (R16-①): the selection
  /// layer adopts a PENDING move session into history first, so an undo
  /// never pops out from under an unadopted coordinator entry. The hook
  /// may execute() a fresh command; the stacks re-check after it runs.
  VoidCallback? onBeforeUndoRedo;

  void undo() => _step(
    from: _undoStack,
    to: _redoStack,
    apply: (command) => command.undo(),
    nothingToDo: 'No commands to undo.',
  );

  void redo() => _step(
    from: _redoStack,
    to: _undoStack,
    apply: (command) => command.execute(),
    nothingToDo: 'No commands to redo.',
  );

  /// Moves one command between the stacks: refuse when there is none,
  /// let the hook run, RE-CHECK, then apply it and hand it to the other
  /// stack.
  ///
  /// ⛔THE SECOND CHECK IS THE POINT, and it reads as redundant until you
  /// know why: [onBeforeUndoRedo] may `execute()` a fresh command, which
  /// pushes to undo and CLEARS redo. So the stack this step was about can
  /// be empty by the time the hook returns, and popping it then is a
  /// range error on a press the user is allowed to make.
  ///
  /// ⚠️The empty stack THROWS on entry but RETURNS after the hook — the
  /// first is a caller that asked for something impossible, the second is
  /// the hook doing its job.
  void _step({
    required List<Command> from,
    required List<Command> to,
    required void Function(Command command) apply,
    required String nothingToDo,
  }) {
    if (from.isEmpty) {
      throw StateError(nothingToDo);
    }
    onBeforeUndoRedo?.call();
    if (from.isEmpty) {
      return;
    }
    final command = from.removeLast();
    apply(command);
    to.add(command);
    // The bytes did not move anywhere, but the budget may have been
    // lowered by pressure since the last push — and nothing else runs
    // between one Ctrl+Z and the next.
    _trimRetainedBytes();
    notifyListeners();
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }
}
