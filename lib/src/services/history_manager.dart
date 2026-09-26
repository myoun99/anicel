import 'package:flutter/foundation.dart';

import '../models/brush_frame_key.dart';
import '../models/standing_place.dart';
import 'history_places.dart';
import 'cels_ahead.dart';
import 'command.dart';
import 'memory_pressure_budget.dart';
import 'persistence/volatile_scratch_files.dart';

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

/// Where a [HistoryManager] stood when a gesture began: how many entries it
/// had pushed and taken back ([HistoryGestures.retractSince]), and how deep
/// its undo stack was.
typedef HistoryMark = ({int pushed, int retracted, int depth});

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

  /// 🚨★★★I-41 — where each entry was made ([HistoryPlaces]): the first
  /// undo walks there, the next one takes the edit back.
  final HistoryPlaces places = HistoryPlaces();

  /// Where the next undo's edit was made, or null when nothing says.
  StandingPlace? get undoPlace =>
      _undoStack.isEmpty ? null : places.of(_undoStack.last);

  /// Where the next redo's edit was made, or null when nothing says.
  ///
  /// ⚠️A walk back never says: it is not an edit, so nothing ever stamps
  /// it — which is what keeps a redo from walking to a walk.
  StandingPlace? get redoPlace =>
      _redoStack.isEmpty ? null : places.of(_redoStack.last);

  /// Leaves the way back on the redo side — the undo that walked to an edit
  /// calls this, so the redo that answers it walks back (「리두대칭」).
  ///
  /// ⚠️It clears nothing: a walk is not an edit, and the redo stack under
  /// it is still the user's to take.
  void leaveWalkBack(WalkBack step) {
    _redoStack.add(step);
    _revision += 1;
    notifyListeners();
  }

  bool get canUndo => _undoStack.isNotEmpty;

  bool get canRedo => _redoStack.isNotEmpty;

  int get undoCount => _undoStack.length;

  int get redoCount => _redoStack.length;

  /// The cap in force, which the session sets from the machine's RAM
  /// ([deviceScaledUndoByteBudget]). Assigning states a new normal;
  /// pressure lowers it separately and is never raised by that act.
  int get byteBudget => _budget.bytes;

  /// 🚨★★★**AND THE PARKING ROOM'S CEILING, FROM THIS ONE CALL.** A
  /// parked payload is this budget spent somewhere else — it is in the
  /// 휘발성 room precisely because RAM had no space for it — so the room
  /// may weigh what the stack was allowed to weigh, and the two numbers
  /// must not be settable apart. 유저 확정 2026-09-10.
  ///
  /// ⛔Pressure does NOT come through here. [_budget] alone drops when the
  /// OS says RAM is tight; the room is not RAM, and shedding history to
  /// relieve memory it was never holding would be the ceiling answering a
  /// question that was not asked of it.
  set byteBudget(int value) {
    _budget.bytes = value;
    VolatileScratchFiles.allow(this, value);
  }

  /// Bytes the snapshot entries currently report — BOTH stacks
  /// (accumulation-guard oracle).
  ///
  /// 🚨REDO COUNTS. [_step] moves an entry between the stacks without
  /// changing what it holds, so a version of this that only walked
  /// [_undoStack] watched half a gigabyte leave the books by being
  /// undone — and a memory warning arriving right then freed nothing,
  /// because by the budget's own reckoning there was nothing to free.
  int get retainedBytes =>
      retainedBytesOf(_undoStack, undone: false) +
      retainedBytesOf(_redoStack, undone: true);

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

  /// What a gesture that writes across many events needs of this stack
  /// while the hand is down — see [HistoryGestures].
  late final HistoryGestures gestures = HistoryGestures._(this);

  void _changed() {
    _revision += 1;
    notifyListeners();
  }

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
    places.stamp(command);
    _undoStack.add(command);
    gestures._pushed += 1;
    if (_undoStack.length > maxEntries) {
      // The oldest commands fall off the deep end, PS-style — and take
      // whatever they parked with them.
      final fallen = _undoStack.length - maxEntries;
      dropPayloadsOf(_undoStack.getRange(0, fallen));
      _undoStack.removeRange(0, fallen);
    }
    // ⚠️REDO GOES FIRST, and the order is not cosmetic any more: a new
    // edit throws the redo stack away, so trimming before the clear
    // measured bytes that were about to leave on their own — and now
    // that the trim SPILLS rather than deletes, it would have written
    // those bytes to disk on the way out.
    dropPayloadsOf(_redoStack);
    _redoStack.clear();
    // A fresh entry is fresh evidence that the room may be writable
    // again — the same re-arming `BrushFrameStore` does on a new edit.
    _spillStoodDown = false;
    _trimRetainedBytes();
    _revision += 1;
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
    // ⚠️THE RELIEF IS NO LONGER INSTANT, and that is the trade the room
    // buys: an over-budget entry is now WRITTEN OUT rather than deleted,
    // so the bytes come back a spill pass later instead of on this line.
    // `BrushFrameStore` already answers pressure that way for cels, and
    // the alternative here is to keep the one behaviour this round
    // exists to remove — losing the user's history at the exact moment
    // the app is most likely to die with their drawing in it.
    _trimRetainedBytes();
  }

  /// 🚨★★★**OVER BUDGET NOW MEANS "MOVE IT", NOT "LOSE IT".** The
  /// over-budget end of the stack used to be DELETED and the user's older
  /// edits simply stopped being undoable. Of the tools the audit read,
  /// none answers a byte ceiling that way — they all page the payload out
  /// (유저 확정 2026-09-07, `cold-tier`). Deleting is what happens when
  /// the room refuses, and only then.
  void _trimRetainedBytes() {
    if (retainedBytes <= _budget.bytes) {
      return;
    }
    if (_spillStoodDown) {
      // The room already refused during this run, so there is nowhere to
      // put these bytes and the old answer is the only one left.
      _shedOverBudget();
      return;
    }
    _scheduleSpill();
  }

  /// Runs one spill pass at a time and re-runs when it finishes with the
  /// budget still exceeded.
  ///
  /// ⚠️`BrushFrameStore._scheduleCooling` is this same shape and they are
  /// deliberately NOT one thing yet: two occurrences merge on the third
  /// (3의 규칙 — 중복 제거는 의도 다음이다). When a third background pass
  /// appears, these two are what it joins.
  void _scheduleSpill() {
    if (_disposed ||
        _activeSpill != null ||
        _spillStoodDown ||
        retainedBytes <= _budget.bytes) {
      return;
    }
    _activeSpill = _spillLoop().whenComplete(() {
      _activeSpill = null;
      _scheduleSpill();
    });
  }

  Future<void>? _activeSpill;

  /// 🚨★★★**A SPILL PASS OUTLIVES THE OBJECT THAT STARTED IT.** It awaits
  /// a background isolate, and the editor can be torn down in between —
  /// the pass then came back to a disposed [ChangeNotifier] and threw
  /// where nobody was catching (found by the session-level pressure pin,
  /// 2026-09-08). Everything the pass touches on the way back asks this
  /// first.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    // ⛔The room gets its files back: nobody can reach this history again,
    // so anything it parked is unreachable bytes on the user's disk until
    // the run ends.
    dropPayloadsOf(_undoStack);
    dropPayloadsOf(_redoStack);
    VolatileScratchFiles.forget(this);
    super.dispose();
  }

  /// ⛔Set when a pass could not move the bytes — either the room refused
  /// or nothing left on the stacks can move — and cleared by a new entry.
  /// Without it the completion re-schedule is an infinite loop: the pass
  /// gives up BECAUSE the budget is still exceeded, which is the very
  /// condition the re-schedule fires on.
  bool _spillStoodDown = false;

  /// Completes when no spill pass is running (tests).
  Future<void> drainSpilling() async {
    while (_activeSpill != null) {
      await _activeSpill;
    }
  }

  Future<void> _spillLoop() async {
    final before = retainedBytes;
    // REDO PARKS FIRST. A redo entry is work the user already stepped
    // back from, and the next execute() throws the whole stack away in
    // any case — spending RAM on it while a real undo goes to disk is the
    // wrong trade.
    final moved =
        await _parkDeepEnd(_redoStack) && await _parkDeepEnd(_undoStack);
    if (moved && retainedBytes < before) {
      return; // Progress; the reschedule decides whether more is needed.
    }
    _spillStoodDown = true;
    _shedOverBudget();
  }

  /// Parks [stack] from its DEEP end while the budget is exceeded,
  /// leaving the top entry resident. False = the room refused.
  ///
  /// 🚨★★★**A CONTIGUOUS PREFIX, NOT THE HEAVIEST ENTRY.** Entry n's
  /// post-surface IS entry n+1's pre-surface, so an entry that lets go on
  /// its own frees nothing at all — the tiles stay alive through its
  /// neighbour. Parking from one end means every shared tile has both of
  /// its holders inside the parked run.
  ///
  /// ⛔The top entry stays in RAM: it is the one the user is about to
  /// press, and reading a payload back is synchronous.
  Future<bool> _parkDeepEnd(List<Command> stack) async {
    var index = 0;
    while (!_disposed &&
        retainedBytes > _budget.bytes &&
        index < stack.length - 1) {
      final command = stack[index];
      // ⚠️The cast is not ceremony: [Command] and [ParkableCommand] are
      // unrelated types, so an `is` check cannot promote between them.
      if (command is ParkableCommand &&
          !await (command as ParkableCommand).parkPayload()) {
        return false;
      }
      index += 1;
    }
    return true;
  }

  /// ⛔THE LAST RESORT, and it used to be the first: entries whose bytes
  /// have nowhere to go are dropped from the deep end.
  void _shedOverBudget() {
    var total = retainedBytes;
    if (_disposed || total <= _budget.bytes) {
      return;
    }
    // 🚨THE READ-AHEAD COPIES GO BEFORE ANY ENTRY DOES. Each is only a
    // head start on a step, and the file it was read from is still in the
    // room; an entry dropped here is history the user cannot get back.
    dropReadAheadOf([..._undoStack, ..._redoStack]);
    total = retainedBytes;
    if (total <= _budget.bytes) {
      return;
    }
    final entriesBefore = _undoStack.length + _redoStack.length;
    // REDO SHEDS FIRST, for the same reason it parks first.
    total -= _shed(_redoStack, total - _budget.bytes, keep: 0, undone: true);
    if (total > _budget.bytes) {
      // ⛔The newest entry always survives: pressure must not cost you the
      // undo you are about to press.
      _shed(_undoStack, total - _budget.bytes, keep: 1, undone: false);
    }
    // 🚨HERE, not at each caller: this is the only place an entry leaves
    // the stacks without the user asking, and a spill pass that ends in a
    // shed reaches it from a microtask nobody else is watching.
    if (_undoStack.length + _redoStack.length != entriesBefore) {
      _revision += 1;
      notifyListeners();
    }
  }

  /// Drops entries from [stack]'s deep end until [excess] bytes are gone,
  /// never leaving fewer than [keep]. Returns the bytes released.
  ///
  /// 🚨★★★**A DROP THAT FREES NOTHING DOES NOT HAPPEN.** The walk stops
  /// at the last entry that actually gave bytes back, so a deep end made
  /// of PARKED entries — which report zero because their bytes are a file
  /// now — is never deleted. Without that, a stack the spill had done its
  /// job on was exactly the stack this would erase: it would walk the
  /// whole parked run collecting nothing, reach the bottom, and take the
  /// user's entire history with it to free not one byte.
  ///
  /// Entries BELOW one that pays are still dropped — a stack cannot lose
  /// its middle, or an undo would skip a step and restore a picture that
  /// was never on screen.
  static int _shed(
    List<Command> stack,
    int excess, {
    required int keep,
    required bool undone,
  }) {
    var released = 0;
    var dropCount = 0;
    var worthDropping = 0;
    var worthReleasing = 0;
    while (released < excess && stack.length - dropCount > keep) {
      final command = stack[dropCount];
      if (command is RetainedBytesCommand) {
        released += (command as RetainedBytesCommand).estimatedRetainedBytes(
          undone: undone,
        );
      }
      dropCount += 1;
      if (released > worthReleasing) {
        worthReleasing = released;
        worthDropping = dropCount;
      }
    }
    if (worthDropping > 0) {
      dropPayloadsOf(stack.getRange(0, worthDropping));
      stack.removeRange(0, worthDropping);
    }
    return worthReleasing;
  }

  /// Called before undo/redo touches the stacks (R16-①): the selection
  /// layer adopts a PENDING move session into history first, so an undo
  /// never pops out from under an unadopted coordinator entry. The hook
  /// may execute() a fresh command; the stacks re-check after it runs.
  VoidCallback? onBeforeUndoRedo;

  /// Whether [onBeforeUndoRedo] would adopt something RIGHT NOW.
  ///
  /// Asked by a step that WAITED for its pictures (the UI's
  /// HistoryPictures): work the user began after pressing — a lift, an
  /// open transform box — is theirs, and a late step that adopted it would
  /// land it out from under their hand.
  bool Function()? pendingBeforeUndoRedo;

  /// Counts every change to the stacks — a push, a step, a clear, a shed.
  ///
  /// A step that waited is honoured only while this has not moved: one
  /// applied over a history that moved on would undo something the user
  /// never asked to undo.
  int get revision => _revision;
  int _revision = 0;

  /// What the next undo — or, with [undo] false, the next redo — would put
  /// back on each cel [wants], read BEFORE the step is taken, so the
  /// pictures it will show can be made ready first. Empty when the step
  /// puts back no snapshot.
  ///
  /// ⚠️A parked payload comes back through a synchronous disk read here,
  /// one step early instead of inside the step, and stays provisional
  /// until the step adopts it ([UndoSurfaceSnapshot.readAhead]) — which is
  /// why WHEN this runs cannot make a step put back the wrong picture.
  Map<BrushFrameKey, CelStep> readAhead({
    required bool undo,
    required bool Function(BrushFrameKey key) wants,
  }) {
    final stack = undo ? _undoStack : _redoStack;
    final cels = CelsAhead(wants: wants);
    if (stack.isNotEmpty) {
      final next = stack.last;
      // ⚠️The cast is not ceremony — see [_parkDeepEnd].
      if (next is PictureRestoringCommand) {
        (next as PictureRestoringCommand).readAhead(cels, undo: undo);
      }
    }
    // What came back is RAM again, and the budget says whether it stays.
    _trimRetainedBytes();
    return cels.cels;
  }

  /// Every tile an entry DEEPER than the next step holds alone, with where
  /// it lies (undo-held-tile-pictures, stage 2): the pictures worth keeping
  /// are the screen's and the next step's each way, and each stack's top IS
  /// that next step, so it is left out.
  void visitDeepHeldTiles(HeldTileVisitor visit) {
    for (var i = 0; i < _undoStack.length - 1; i += 1) {
      final command = _undoStack[i];
      // ⚠️The cast is not ceremony — see [_parkDeepEnd].
      if (command is PictureRestoringCommand) {
        (command as PictureRestoringCommand).visitHeldTiles(
          visit,
          undone: false,
        );
      }
    }
    for (var i = 0; i < _redoStack.length - 1; i += 1) {
      final command = _redoStack[i];
      if (command is PictureRestoringCommand) {
        (command as PictureRestoringCommand).visitHeldTiles(
          visit,
          undone: true,
        );
      }
    }
  }

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
    // A walk back is spent by the redo that takes it — it is not an edit,
    // so there is nothing for an undo to take back.
    if (command is! WalkBack) {
      to.add(command);
      places.stamp(command);
    }
    _revision += 1;
    // The bytes did not move anywhere, but the budget may have been
    // lowered by pressure since the last push — and nothing else runs
    // between one Ctrl+Z and the next.
    _trimRetainedBytes();
    notifyListeners();
  }

  void clear() {
    dropPayloadsOf(_undoStack);
    dropPayloadsOf(_redoStack);
    _undoStack.clear();
    _redoStack.clear();
    _spillStoodDown = false;
    _revision += 1;
    notifyListeners();
  }
}

/// A GESTURE's own entries in its [HistoryManager] — what a gesture that
/// writes across many events (the rail's column swipe) needs while the hand
/// is down: a [mark] before its first write, [retractSince] to take back its
/// newest write, [foldSince] to make what it kept one entry on release.
///
/// Its own object because the stack does not care whether a gesture is
/// under way — the three verbs took [HistoryManager] past the six hundred
/// lines the class ratchet holds it to (2026-09-26). The same library, so
/// it works the stack directly rather than through a wider surface.
class HistoryGestures {
  HistoryGestures._(this._history);

  final HistoryManager _history;

  /// Every entry the history has pushed, and every one [retractSince] took
  /// back, ever — what [mark] counts by, because the stack's length stops
  /// moving once the deep end trims.
  int _pushed = 0;
  int _retracted = 0;

  /// Where the stack stands now — taken before a gesture's first write.
  HistoryMark get mark => (
    pushed: _pushed,
    retracted: _retracted,
    depth: _history._undoStack.length,
  );

  /// Takes back the newest entry pushed since [since] and FORGETS it —
  /// undone, and not handed to redo: a gesture withdrawing its own latest
  /// write while it is still under way (F-182, 유저 09-25: 「레이어 라벨 버튼
  /// 드래그 일괄조작, 원래 위치로 돌아가면 원복하도록」 — the rail swipe's
  /// cursor drawing back over rows it painted). A redo of something the
  /// hand already took back would be a step the user never made.
  ///
  /// ⛔Nothing at or below [since] is touched. False when the gesture has
  /// nothing of its own left to take.
  bool retractSince(HistoryMark since) {
    final stack = _history._undoStack;
    if (stack.length <= since.depth) {
      return false;
    }
    final command = stack.removeLast();
    command.undo();
    dropPayloadsOf([command]);
    _retracted += 1;
    _history._changed();
    return true;
  }

  /// Folds every entry pushed since [since] into ONE — for a gesture that
  /// writes across many events, which [HistoryManager.runAsOneStep]'s
  /// synchronous body cannot span: the rail's column swipe, whose press and
  /// sweep land row by row (swipe-is-one-undo, 유저 08-28: 「일괄로 버튼
  /// 조작하고 언두하면 바꼈던 레이어들 다 한번에 언두되야하는데 안됨」).
  ///
  /// ⛔Only a run still whole: the entries pushed since [since] and not
  /// taken back, exactly them, on top of the stack. An undo, a redo or the
  /// deep end in between leaves something else there, and folding that
  /// would take back what the gesture did not do — so the entries are left
  /// as they are.
  void foldSince(HistoryMark since, String description) {
    final stack = _history._undoStack;
    final kept = (_pushed - since.pushed) - (_retracted - since.retracted);
    if (kept < 2 || stack.length != since.depth + kept) {
      return;
    }
    final run = stack.sublist(since.depth);
    stack.removeRange(since.depth, stack.length);
    // Already executed, as a group's are: this re-files them, it runs
    // nothing a second time.
    final folded = CompositeCommand(description: description, commands: run);
    _history.places.stamp(folded);
    stack.add(folded);
    _history._changed();
  }
}
