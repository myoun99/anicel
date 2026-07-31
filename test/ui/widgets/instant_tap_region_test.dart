import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/instant_tap_region.dart';

/// R10: THE app's answer to the double-tap tax.
///
/// Registering `onDoubleTap` anywhere puts the single tap behind the
/// double-tap window — about 300ms of nothing happening, which the user
/// asked to be rid of everywhere. The primary action comes off the arena
/// instead: pen/mouse on the DOWN, a finger on the release if it did not
/// travel, so a press that becomes a scroll stays a scroll.
void main() {
  Future<({List<Offset> taps, List<Offset> downs})> pump(
    WidgetTester tester, {
    bool Function(PointerDeviceKind kind)? pressSeeksFor,
  }) async {
    final taps = <Offset>[];
    final downs = <Offset>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: InstantTapRegion(
              pressSeeksFor: pressSeeksFor,
              onPressDown: downs.add,
              onTap: taps.add,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(width: 200, height: 100),
            ),
          ),
        ),
      ),
    );
    return (taps: taps, downs: downs);
  }

  Finder region() => find.byType(InstantTapRegion);

  testWidgets('a mouse acts on the DOWN — nothing to wait for', (
    tester,
  ) async {
    final log = await pump(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(region()),
      kind: PointerDeviceKind.mouse,
    );
    // No pump past the down, and no release: the action has already run.
    expect(log.taps, hasLength(1));

    await gesture.up();
    await tester.pump();
    expect(log.taps, hasLength(1), reason: 'the release adds nothing');
  });

  testWidgets('a finger waits for the RELEASE, so a press that becomes a '
      'scroll never acts', (tester) async {
    final log = await pump(tester);

    final scroll = await tester.startGesture(
      tester.getCenter(region()),
      kind: PointerDeviceKind.touch,
    );
    expect(log.taps, isEmpty, reason: 'the finger has not committed yet');
    await scroll.moveBy(const Offset(0, 40));
    await tester.pump();
    await scroll.up();
    await tester.pump();
    expect(log.taps, isEmpty, reason: 'it travelled: that was a scroll');

    // A clean finger tap still acts, on the release.
    final tap = await tester.startGesture(
      tester.getCenter(region()),
      kind: PointerDeviceKind.touch,
    );
    await tap.up();
    await tester.pump();
    expect(log.taps, hasLength(1));
  });

  testWidgets('the device gate decides which is which — the timeline hands '
      'it the touch-scroll preference', (tester) async {
    // Touch treated as a pen: it acts on the down like one.
    final log = await pump(tester, pressSeeksFor: (_) => true);

    await tester.startGesture(
      tester.getCenter(region()),
      kind: PointerDeviceKind.touch,
    );
    expect(log.taps, hasLength(1));
  });

  testWidgets('onPressDown fires on the DOWN whatever the device — the '
      'double-tap gate records the pressed cell there', (tester) async {
    final log = await pump(tester);

    final finger = await tester.startGesture(
      tester.getCenter(region()),
      kind: PointerDeviceKind.touch,
    );
    expect(
      log.downs,
      hasLength(1),
      reason: 'even though the finger has not committed a tap yet',
    );
    expect(log.taps, isEmpty);
    await finger.up();
    await tester.pump();
  });

  testWidgets('the position it reports is the DOWN position, not the '
      'release — a finger that drifts inside the slop still acts where it '
      'landed', (tester) async {
    final log = await pump(tester);
    final centre = tester.getCenter(region());

    final finger = await tester.startGesture(
      centre,
      kind: PointerDeviceKind.touch,
    );
    await finger.moveBy(const Offset(6, 0));
    await tester.pump();
    await finger.up();
    await tester.pump();

    expect(log.taps, hasLength(1));
    expect(
      log.taps.single.dx,
      moreOrLessEquals(log.downs.single.dx, epsilon: 0.01),
      reason: 'the cell you pressed is the cell you get',
    );
  });
}
