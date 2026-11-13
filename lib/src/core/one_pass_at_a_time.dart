import 'dart:async';

/// Work done in passes, ONE AT A TIME: asked while a pass runs, it is not
/// begun beside it — what came due meanwhile goes in the next pass, which
/// begins the moment the one before ends. The passes end when nothing is
/// due, when a pass says to stop, or when one throws.
///
/// 🚨Written once. It was written out by hand six times (card
/// one-in-flight-the-rest-in-the-next, 2026-11-13) — a frame's steps going
/// through its plugins (`FramePictureView`), a settings file's writes
/// (`saveVersionedSettings`), the usage stats' posts (`UsageStats`), the
/// brush tips' pictures (`BrushTipThumbnails`), the cels' cooling
/// (`BrushFrameStore`) and the undo stack's spill (`HistoryManager`). The
/// spill and the cooling had been kept two on purpose, to be joined by a
/// third (3의 규칙); four more were already there, and the spill still ran
/// again after a pass that threw: the spin the cooling had been cured of.
///
/// ⛔NOT `InFlight`: asked while its run goes, an ask JOINS that run — the
/// same future, the same answer. Here what was asked after a pass began is
/// not in it; it is the next pass's.
/// ⛔NOT `LaidWhole`: a piece of that law has no effect till it is put up
/// whole. Each pass here has its effect as it ends — a file written, a
/// batch posted, a cel parked.
///
/// What comes due is its holder's to keep, and so is how it gathers — a
/// rect grown to take each step in (the frame's steps), the newest in place
/// of the one before (a settings file), a queue (the posts, the tip
/// pictures), whatever the budget is over by (the cooling, the spill).
/// [due] reads it, and a pass takes from it.
final class OnePassAtATime {
  OnePassAtATime({
    required bool Function() due,
    required Future<bool> Function() pass,
  }) : _due = due,
       _pass = pass;

  /// Whether there is work for a pass now.
  final bool Function() _due;

  /// One pass: false where the passes should stop though work is still due
  /// — a refusal nothing about the next pass would change.
  final Future<bool> Function() _pass;

  /// The passes on their way, from the first to the one nothing followed.
  Future<void>? _onItsWay;

  /// Whether a pass is on its way.
  bool get onItsWay => _onItsWay != null;

  /// The passes begun where none is on its way and work is due — the first
  /// begun before this returns. Completes when they end, with the error of a
  /// pass that threw. ⚠️Asked while they run, it completes at once: what it
  /// asked for goes in the next pass, which nobody waits on alone
  /// ([settled] does).
  Future<void> ask() {
    if (_onItsWay != null || !_due()) {
      return Future<void>.value();
    }
    final passes = Completer<void>();
    _onItsWay = passes.future;
    unawaited(_passes(passes));
    return passes.future;
  }

  /// Completes once no pass is on its way.
  Future<void> settled() async {
    for (var passes = _onItsWay; passes != null; passes = _onItsWay) {
      await passes;
    }
  }

  Future<void> _passes(Completer<void> passes) async {
    try {
      while (await _pass() && _due()) {}
      _onItsWay = null;
      passes.complete();
    } on Object catch (error, stack) {
      // 🚨A PASS THAT THREW ENDS THE PASSES. Nothing about the next is more
      // likely to go, and work that stays due because it would not go
      // asks again for ever: the cooling spun on microtasks that way and
      // starved the screen (a666cc4c1), and the spill ran again after a throw
      // till it came here. The next ask begins them anew.
      _onItsWay = null;
      passes.completeError(error, stack);
    }
  }
}
