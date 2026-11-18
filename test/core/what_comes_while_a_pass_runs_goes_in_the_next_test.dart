import 'dart:async';

import 'package:anicel/src/core/one_pass_at_a_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// `OnePassAtATime` — card one-in-flight-the-rest-in-the-next (2026-11-13).
void main() {
  test('🚨asked while a pass runs, none is begun beside it: what came due '
      'goes in the next, together, begun as the first ends', () async {
    final work = _Work();
    work.due += 1;
    final first = work.passes.ask();
    expect(work.taken, [1], reason: 'the first is begun before ask returns');
    expect(work.passes.onItsWay, isTrue);

    work.due += 1;
    await work.passes.ask();
    work.due += 1;
    await work.passes.ask();
    expect(work.taken, [1], reason: 'asked while it runs, nothing is begun');

    work.landTheOneOnItsWay();
    await pumpEventQueue();
    expect(work.taken, [1, 2], reason: 'the two asked meanwhile, in one pass');
    expect(work.passes.onItsWay, isTrue);

    work.landTheOneOnItsWay();
    await first;
    expect(work.taken, [1, 2]);
    expect(work.passes.onItsWay, isFalse);
  });

  test('nothing due, nothing begun', () async {
    final work = _Work();
    await work.passes.ask();
    expect(work.taken, isEmpty);
    expect(work.passes.onItsWay, isFalse);
  });

  test('a pass that says stop ends the passes though work is due — and the '
      'next ask begins them anew', () async {
    final work = _Work()..answer = false;
    work.due += 1;
    final passes = work.passes.ask();
    work.due += 1;
    work.landTheOneOnItsWay();
    await passes;
    expect(work.taken, [1], reason: 'one is still due, and nothing is begun');
    expect(work.passes.onItsWay, isFalse);

    work.answer = true;
    final again = work.passes.ask();
    expect(work.taken, [1, 1]);
    work.landTheOneOnItsWay();
    await again;
  });

  test('🚨a pass that throws ends the passes — it is not begun again for as '
      'long as the work stays due (a666cc4c1) — and says so to who waits; '
      'the next ask begins them anew', () async {
    var begun = 0;
    final passes = OnePassAtATime(
      due: () => true,
      pass: () async {
        begun += 1;
        if (begun == 1) {
          throw StateError('the room refused');
        }
        return false;
      },
    );
    await expectLater(passes.ask(), throwsStateError);
    await pumpEventQueue();
    expect(begun, 1, reason: 'not begun again while it stays due');
    expect(passes.onItsWay, isFalse);

    await passes.ask();
    expect(begun, 2, reason: 'anew');
  });

  test('settled waits for the last of the passes, and is at once where none '
      'is on its way', () async {
    final work = _Work();
    await work.passes.settled();
    work.due += 1;
    unawaited(work.passes.ask());
    var settled = false;
    unawaited(work.passes.settled().then((_) => settled = true));
    work.due += 1;
    work.landTheOneOnItsWay();
    await pumpEventQueue();
    expect(settled, isFalse, reason: 'the next pass is on its way');
    work.landTheOneOnItsWay();
    await pumpEventQueue();
    expect(settled, isTrue);
  });
}

/// Work that comes due by [due], each pass taking all of it and waiting till
/// it is landed ([landTheOneOnItsWay]).
final class _Work {
  int due = 0;
  bool answer = true;
  final List<int> taken = [];
  late Completer<void> _onItsWay;

  late final passes = OnePassAtATime(due: () => due > 0, pass: _pass);

  Future<bool> _pass() async {
    taken.add(due);
    due = 0;
    final landed = _onItsWay = Completer<void>();
    await landed.future;
    return answer;
  }

  void landTheOneOnItsWay() => _onItsWay.complete();
}
