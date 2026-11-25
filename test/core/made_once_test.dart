import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/made_once.dart';

/// [MadeOnce] — what is made once is kept, and handed as itself once made
/// (`a_thing_made_once_is_kept_not_its_future_test` says who keeps theirs
/// in it).
void main() {
  test('🚨made in a zone nobody runs any more, it is handed to the next '
      'asker all the same — the future it was made by never answers that '
      'asker', () async {
    final dead = _AZoneOfItsOwnClock();
    final made = MadeOnce<int>();
    late Future<int> making;
    dead.run(() {
      making = made.of(() async => 7);
    });
    dead.flush();
    expect(made.orNull, 7, reason: '⛔premise: made on its clock');

    expect(
      await _answered(making),
      isFalse,
      reason: '⛔premise: what this zone made answers no one after it',
    );
    expect(await _answered(made.of(() async => 8)), isTrue);
    expect(await made.of(() async => 8), 7);
  });

  test('two asks while it is made are ONE making — the same future, '
      '[make] asked once', () async {
    final made = MadeOnce<int>();
    final hold = Completer<int>();
    var asked = 0;
    Future<int> make() {
      asked += 1;
      return hold.future;
    }

    final first = made.of(make);
    expect(made.of(make), same(first));
    expect(made.isAsked, isTrue);
    expect(made.isMade, isFalse);
    hold.complete(3);
    expect(await first, 3);
    expect(asked, 1);
    expect(made.isMade, isTrue);
    expect(made.of(make), isNot(same(first)), reason: 'itself, not that');
    expect(asked, 1);
  });

  test('a making that failed is told to each ask after it, and not made '
      'again', () async {
    final made = MadeOnce<int>();
    var asked = 0;
    Future<int> make() async {
      asked += 1;
      throw StateError('no');
    }

    await expectLater(made.of(make), throwsStateError);
    await expectLater(made.of(make), throwsStateError);
    expect(asked, 1);
    expect(made.isMade, isFalse);
    expect(made.isAsked, isTrue);
  });

  test('kept another way while it was made, the one kept first is the '
      'answer, and what the making made is freed', () async {
    final freed = <List<int>>[];
    final made = MadeOnce<List<int>>(freed.add);
    final hold = Completer<List<int>>();
    final making = made.of(() => hold.future);
    final first = [1];
    expect(made.keep(first), same(first));
    final second = [2];
    hold.complete(second);

    expect(await making, same(first));
    expect(freed, [same(second)]);
    expect(made.keep(first), same(first), reason: 'itself: nothing freed');
    expect(freed, hasLength(1));
  });

  test('nothing made of nothing asked', () {
    final made = MadeOnce<void>();
    expect(made.isAsked, isFalse);
    expect(made.isMade, isFalse);
  });
}

/// A zone whose microtasks run only when [flush] runs them — as a widget
/// test's faked clock, which nobody pumps once its test ends.
final class _AZoneOfItsOwnClock {
  final _due = <void Function()>[];

  late final Zone _zone = Zone.current.fork(
    specification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, task) =>
          _due.add(() => zone.run(task)),
    ),
  );

  R run<R>(R Function() body) => _zone.run(body);

  void flush() {
    while (_due.isNotEmpty) {
      _due.removeAt(0)();
    }
  }
}

/// Whether [future] answers a listener within a second — as an `await`
/// listens, by `then`, and not by `timeout`, which takes a done future by
/// a way of its own.
Future<bool> _answered(Future<Object?> future) {
  final answer = Completer<bool>();
  final watch = Timer(const Duration(seconds: 1), () {
    if (!answer.isCompleted) {
      answer.complete(false);
    }
  });
  unawaited(
    future.then((_) {
      if (!answer.isCompleted) {
        watch.cancel();
        answer.complete(true);
      }
    }),
  );
  return answer.future;
}
