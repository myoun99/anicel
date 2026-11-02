import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/quiet_turns.dart';
import 'package:anicel/src/ui/session/render_caches.dart';

// 🗣️F-529: a change made while the bar filled waited out its raster.
void main() {
  QuietTurns turns({required bool held}) =>
      QuietTurns(clock: QuietClock(quiet: () => null, held: () => held));

  tearDown(() => RenderCaches.aheadGoesInPieces = false);

  test('a frame made ahead goes in pieces while nothing plays', () {
    RenderCaches.aheadGoesInPieces = true;

    expect(RenderCaches.madeAheadInPieces(turns(held: false)), isTrue);
  });

  test('⛔not ahead of a run', () {
    RenderCaches.aheadGoesInPieces = true;

    expect(RenderCaches.madeAheadInPieces(turns(held: true)), isFalse);
  });

  test('⛔not under a test\'s clock', () {
    expect(RenderCaches.madeAheadInPieces(turns(held: false)), isFalse);
  });
}
