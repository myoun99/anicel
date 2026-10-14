import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/quiet_turns.dart';

/// 🚨Background GPU work takes its turn in the quiet between held frames,
/// one job at a time ([QuietTurns]). What a turn fits — the wait for the
/// quiet to begin, a quiet with no room, one that is over, a job longer
/// than what is left, the length learned — is pinned through the
/// timeline's warm-up (`the_next_page_is_baked_while_the_page_before_plays
/// _test`); these are the turns themselves.
void main() {
  ({int fromMicros, int untilMicros})? quiet;
  late Completer<void> moved;
  late QuietTurns turns;

  setUp(() {
    quiet = (fromMicros: 0, untilMicros: 1000000);
    moved = Completer<void>();
    turns = QuietTurns(
      clock: QuietClock(
        quiet: () => quiet,
        now: () => 0,
        wait: (_) async {},
        moved: () => moved.future,
      ),
    );
  });

  bool neverGone() => false;

  /// Whether [turn] has been given, a few turns of the event queue on.
  Future<bool Function()> asked(Future<QuietTurn?> turn) async {
    var given = false;
    unawaited(turn.then((_) => given = true));
    await pumpEventQueue();
    return () => given;
  }

  test('🚨one job at a time in a quiet: the next is given its turn once the '
      'one before it lands', () async {
    final first = await turns.inAQuiet(QuietSpan(), gone: neverGone);
    final second = await asked(turns.inAQuiet(QuietSpan(), gone: neverGone));
    expect(second(), isFalse, reason: 'two that each fit, side by side, '
        'end past the quiet together');

    first!.landed();
    await pumpEventQueue();

    expect(second(), isTrue);
  });

  test('a job that gives up gives its turn back as well', () async {
    final first = await turns.inThisQuiet(QuietSpan(), gone: neverGone);
    final second = await asked(turns.inThisQuiet(QuietSpan(), gone: neverGone));
    expect(second(), isFalse, reason: '⛔premise');

    first!.gaveUp();
    await pumpEventQueue();

    expect(second(), isTrue);
  });

  test('⛔where no quiet is kept, every job is given its turn at once, side '
      'by side', () async {
    quiet = null;
    final first = await turns.inAQuiet(QuietSpan(), gone: neverGone);

    final second = await asked(turns.inAQuiet(QuietSpan(), gone: neverGone));

    expect(first, isNotNull);
    expect(second(), isTrue, reason: 'nobody queues where nothing is held');
  });

  test('🚨what the next held frame shows is given its turn at once — past a '
      'turn being taken, and whatever the quiet', () async {
    final first = await turns.inAQuiet(QuietSpan(), gone: neverGone);
    expect(first, isNotNull, reason: '⛔premise: a turn is being taken');
    quiet = (fromMicros: 0, untilMicros: 0);

    final due = await asked(
      turns.inAQuiet(QuietSpan(), gone: neverGone, due: () => true),
    );

    expect(due(), isTrue);
  });

  test('a job the quiet has no room for waits for the quiet to move, and '
      'takes the next', () async {
    quiet = (fromMicros: 0, untilMicros: 0);
    final waiting = await asked(
      turns.inAQuiet(QuietSpan(), gone: neverGone),
    );
    expect(waiting(), isFalse, reason: 'no room in this one');

    quiet = (fromMicros: 0, untilMicros: 1000000);
    moved.complete();
    await pumpEventQueue();

    expect(waiting(), isTrue);
  });

  test('🚨one waiting for the quiet goes at once when the next held frame '
      'comes to show what it makes', () async {
    quiet = (fromMicros: 0, untilMicros: 0);
    var due = false;
    final waiting = await asked(
      turns.inAQuiet(QuietSpan(), gone: neverGone, due: () => due),
    );
    expect(waiting(), isFalse, reason: '⛔premise');

    due = true;
    moved.complete();
    await pumpEventQueue();

    expect(waiting(), isTrue, reason: 'the quiet has no more room than before');
  });

  test('a job stood down while it waits is given no turn, and holds none', () async {
    quiet = (fromMicros: 0, untilMicros: 0);
    var gone = false;
    final given = turns.inAQuiet(QuietSpan(), gone: () => gone);
    await pumpEventQueue();

    gone = true;
    moved.complete();

    expect(await given, isNull);
    quiet = (fromMicros: 0, untilMicros: 1000000);
    final next = await asked(turns.inAQuiet(QuietSpan(), gone: neverGone));
    expect(next(), isTrue, reason: 'the turn it waited in was given back');
  });

  test('a turn in this quiet only: none when it has no room, and the turn is '
      'given back', () async {
    quiet = (fromMicros: 0, untilMicros: 0);

    expect(await turns.inThisQuiet(QuietSpan(), gone: neverGone), isNull);

    quiet = (fromMicros: 0, untilMicros: 1000000);
    final next = await asked(turns.inThisQuiet(QuietSpan(), gone: neverGone));
    expect(next(), isTrue);
  });
}
