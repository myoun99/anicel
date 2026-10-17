import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'poll_until.dart';

/// [patiently] is the one ceiling a test awaits a future at (board
/// `a-test-awaits-a-future-with-a-ceiling-of-its-own`): the whole of
/// [waitPatience] and no less — a busy machine is given all of it — and
/// then a failure, never a wait that ends quietly or not at all. Read on a
/// pumped clock, so the minute costs nothing here.
void main() {
  testWidgets('a future that never comes fails at the ceiling, and not '
      'before it', (tester) async {
    Object? failed;
    unawaited(
      patiently(Completer<void>().future).then<void>(
        (_) {},
        onError: (Object error) => failed = error,
      ),
    );

    await tester.pump(waitPatience - const Duration(seconds: 1));
    expect(failed, isNull, reason: 'the whole ceiling is waited');
    await tester.pump(const Duration(seconds: 1));
    expect(failed, isA<TimeoutException>());
  });

  testWidgets('a future that comes is handed over as it came', (
    tester,
  ) async {
    expect(await patiently(Future<int>.value(7)), 7);
  });
}
