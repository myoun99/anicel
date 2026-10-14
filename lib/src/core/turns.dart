import 'dart:async';
import 'dart:collection';

/// Work that runs at most [atOnce] at a time: the rest wait their turn, in
/// the order they asked.
///
/// ⚠️A turn that ends passes STRAIGHT to the next in line, never put down
/// and picked up again — one that asks in between would take it first.
final class Turns {
  Turns(this.atOnce) : assert(atOnce > 0);

  final int atOnce;

  int _running = 0;
  final Queue<Completer<void>> _waiting = Queue();

  /// How many hold a turn right now.
  int get running => _running;

  /// [work] in its turn — what it answers, or what it throws.
  Future<T> run<T>(Future<T> Function() work) async {
    if (_running < atOnce) {
      _running += 1;
    } else {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    try {
      return await work();
    } finally {
      if (_waiting.isEmpty) {
        _running -= 1;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  }
}
