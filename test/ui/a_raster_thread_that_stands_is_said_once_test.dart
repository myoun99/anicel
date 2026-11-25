import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/raster_watch.dart';

/// Board a-real-gpu-reset-went-unheard-on-the-main-pc (2026-11-22): a
/// frame the app handed the engine and the engine does not say drawn for
/// [RasterWatch.patience] is the thread that draws the screen standing —
/// said once a run, with what was drawn, what waits and since when. A
/// frame said drawn in time is not, and neither is a timer that comes far
/// later than it was set for: the machine stood still, not that thread.
void main() {
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 11, 22, 16, 47);
    RasterWatch.debugClockOverride = () => now;
    addTearDown(() {
      RasterWatch.debugClockOverride = null;
      RasterWatch.debugForget();
    });
  });

  const patience = RasterWatch.patience;
  const aSecond = Duration(seconds: 1);

  /// [time] passes: on the clock and for what waits on a timer.
  Future<void> passes(WidgetTester tester, Duration time) async {
    now = now.add(time);
    await tester.pump(time);
  }

  testWidgets('a frame handed over that is said drawn in time is no raster '
      'thread standing, however long nothing is handed over after', (
    tester,
  ) async {
    RasterWatch.handedOver(7);
    await passes(tester, patience - aSecond);
    RasterWatch.saidDrawn(7);
    await passes(tester, patience * 3);
    expect(RasterWatch.stood.value, isNull);
  });

  testWidgets('none said drawn for the patience after one was handed over '
      'is the raster thread standing — from the last it came back from, '
      'with the frames and the moments; said once a run', (tester) async {
    var said = 0;
    void count() => said += 1;
    RasterWatch.stood.addListener(count);
    addTearDown(() => RasterWatch.stood.removeListener(count));

    RasterWatch.handedOver(7);
    await passes(tester, patience - aSecond);
    RasterWatch.handedOver(8);
    final handedOverAt = now;
    // Back from 7 alone: 8 waits from here, not from when 7 was handed.
    await passes(tester, aSecond ~/ 2);
    RasterWatch.saidDrawn(7);
    final quietSince = now;
    await passes(tester, patience - aSecond);
    expect(RasterWatch.stood.value, isNull, reason: 'not yet');

    await passes(tester, aSecond);
    expect(RasterWatch.stood.value, (
      drawn: 7,
      handedOver: 8,
      handedOverAt: handedOverAt,
      quietSince: quietSince,
    ));
    expect(said, 1);

    final first = RasterWatch.stood.value;
    RasterWatch.handedOver(9);
    await passes(tester, patience * 3);
    RasterWatch.saidDrawn(9);
    RasterWatch.handedOver(10);
    await passes(tester, patience * 3);
    expect(RasterWatch.stood.value, first, reason: 'once a run');
    expect(said, 1);
  });

  testWidgets('a timer that comes far later than it was set for waited on '
      'no raster thread — the machine stood still — and waits again from '
      'there', (tester) async {
    RasterWatch.handedOver(3);
    // The clock ran on while no timer did: a sleep, a debugger.
    now = now.add(patience * 2 + aSecond);
    await tester.pump(patience);
    expect(RasterWatch.stood.value, isNull, reason: 'the machine, not it');

    await passes(tester, patience - aSecond);
    expect(RasterWatch.stood.value, isNull, reason: 'waits again, whole');
    await passes(tester, aSecond);
    expect(RasterWatch.stood.value?.handedOver, 3);
    expect(
      RasterWatch.stood.value?.quietSince,
      now.subtract(patience),
      reason: 'since it woke',
    );
  });
}
