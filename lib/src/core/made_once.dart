import 'dart:async';

/// What is made once, off the turn that asks, and kept: handed at once —
/// in a future of the asker's own — where it is made, the making joined
/// while it goes, and that making never once it has ended.
///
/// 🚨THE VALUE IS KEPT, NOT THE FUTURE OF IT (card
/// an-engine-setup-hangs-in-a-batch, 2026-11-23). A future that is done
/// answers what listens to it from then on in the zone it was MADE in, and
/// a widget test's zone is its faked clock, which nobody pumps once that
/// test ends. 🔬Measured that day: a `Future.value` made in a widget test
/// and listened to by the test after it never answered, and the app's
/// engine opening (`openAppGpuEngine`) the shell's test had made the same
/// way stood every file bundled after it in its `setUpAll` — 12 minutes
/// each, the process idle (보드/인프라: two files, 3 of 3). ⚠️`timeout`
/// does not show it: it takes a done future by a way of its own.
///
/// 🚨Written once. It was written by hand five times — the app's engine's
/// opening, a set of its kernels warmed (`AppKernels.warm`), the frames'
/// tools (`appEngineFrameTools`), the blur strips (`EngineStrokes`) and the
/// engine's faces (`EngineFaces`), which alone kept the value (11-08: 「a
/// second test awaiting the first one's future never woke」); the other
/// four kept the future and handed it on.
///
/// ⛔NOT `InFlight`: that one lets a run go as it ends — answered or
/// failed — and the next ask runs it anew. What is made here is kept,
/// and so is a making that failed: each ask after it is told the same
/// failure, as each was before this was written.
final class MadeOnce<T> {
  /// [free] frees what was made where it is not kept — made by a making
  /// that ended after another road had kept one ([keep]).
  MadeOnce([this._free]);

  final void Function(T)? _free;

  ({T value})? _made;
  ({Object error, StackTrace stack})? _failed;
  Future<T>? _making;

  /// Whether it has been made.
  bool get isMade => _made != null;

  /// What was made, null till it is.
  T? get orNull => _made?.value;

  /// Whether anything has asked for it: made, failed, or on its way.
  bool get isAsked => _made != null || _failed != null || _making != null;

  /// What was made, at once where it is — else [make]'s making: the one on
  /// its way, or one begun now.
  Future<T> of(Future<T> Function() make) {
    if (_made case (:final value)) {
      return Future.value(value);
    }
    if (_failed case (:final error, :final stack)) {
      return Future.error(error, stack);
    }
    return _making ??= _madeBy(make);
  }

  Future<T> _madeBy(Future<T> Function() make) async {
    try {
      final made = await make();
      _making = null;
      return keep(made);
    } catch (error, stack) {
      _making = null;
      _failed = (error: error, stack: stack);
      rethrow;
    }
  }

  /// [value] kept as what was made — answered with what is kept, which is
  /// the one kept first where another was: [value] is then freed.
  T keep(T value) {
    if (_made case (value: final kept)) {
      if (!identical(kept, value)) {
        _free?.call(value);
      }
      return kept;
    }
    _made = (value: value);
    return value;
  }
}
