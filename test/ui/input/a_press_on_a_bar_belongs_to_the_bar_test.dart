import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/axis_bar_gesture.dart';

/// 🚨★★★A PRESS THAT LANDS ON A BAR BELONGS TO THAT BAR.
///
/// 유저 확정 2026-08-14, ⛔재론 금지: 「슬라이더위에서 조작하기 시작하면
/// 슬라이더조작하는거고 그 외가 스크롤인거야」.
///
/// The recognisers accept on the FIRST MOVEMENT rather than at a slop, so
/// they have already won by the time the scrollable around them reaches its
/// own threshold. What makes that necessary is the straight-DOWN drag on a
/// horizontal bar: it moves 0 along the bar's own axis, so a threshold on
/// |dx| can never be crossed and the rival takes the arena by walkover
/// rather than by racing.
///
/// ⛔The case the old answer protected — a finger resting on a slider while
/// the panel scrolls under it — was never a real gesture: 「절대로안하니까
/// 다신하지마」. Do not resurrect it.
void main() {
  /// A horizontal bar inside a VERTICAL scrollable — the shape the law is
  /// about, and the shape where a slop-based recogniser loses.
  Future<
    ({ScrollController controller, List<double> deltas, int starts, int ends})
  >
  pumpBarInScrollable(WidgetTester tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final deltas = <double>[];
    var starts = 0;
    var ends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: ListView(
              controller: controller,
              children: [
                const SizedBox(height: 100),
                RawGestureDetector(
                  gestures: <Type, GestureRecognizerFactory>{
                    OwningHorizontalDragGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          OwningHorizontalDragGestureRecognizer
                        >(OwningHorizontalDragGestureRecognizer.new, (
                          recognizer,
                        ) {
                          recognizer
                            ..onStart = ((_) => starts += 1)
                            ..onUpdate = ((details) {
                              deltas.add(details.primaryDelta ?? 0);
                            })
                            ..onEnd = ((_) => ends += 1);
                        }),
                  },
                  child: Container(
                    key: const ValueKey<String>('bar'),
                    height: 40,
                    color: const Color(0xFF884444),
                  ),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    );
    return (controller: controller, deltas: deltas, starts: starts, ends: ends);
  }

  testWidgets('a drag ALONG the bar is the bar\'s, and the list does not '
      'move', (tester) async {
    final probe = await pumpBarInScrollable(tester);

    await tester.drag(
      find.byKey(const ValueKey<String>('bar')),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();

    expect(probe.deltas, isNotEmpty);
    // ⚠️Not all 60: the movement before the recogniser accepts is spent
    // winning the arena, not reported. What the law is about is WHO gets
    // the gesture, and the list getting none of it.
    expect(probe.deltas.reduce((a, b) => a + b), greaterThan(0));
    expect(probe.controller.offset, 0);
  });

  testWidgets('🚨a drag STRAIGHT DOWN on a horizontal bar is STILL the '
      'bar\'s — the list must not take it, which is exactly what a slop on '
      '|dx| would have let happen', (tester) async {
    final probe = await pumpBarInScrollable(tester);

    await tester.drag(
      find.byKey(const ValueKey<String>('bar')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();

    expect(
      probe.controller.offset,
      0,
      reason:
          'the press landed on the bar, so the scroll is not the '
          'list\'s to take',
    );
  });

  testWidgets('a vertical drag on a horizontal bar holds the pointer and '
      'changes NOTHING — "you are operating the slider now"', (tester) async {
    final probe = await pumpBarInScrollable(tester);

    await tester.drag(
      find.byKey(const ValueKey<String>('bar')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();

    final travelled = probe.deltas.isEmpty
        ? 0.0
        : probe.deltas.reduce((a, b) => a + b);
    expect(travelled, closeTo(0, 0.001), reason: 'the value follows |dx| only');
  });

  testWidgets('a drag that STARTS off the bar is the list\'s, as it always '
      'was — the law is about where the press lands', (tester) async {
    final probe = await pumpBarInScrollable(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(probe.controller.offset, greaterThan(0));
    expect(probe.deltas, isEmpty);
  });

  test('🚨both recognisers accept at ANY distance — that is the whole '
      'mechanism, and a slop returning here is the bug coming back', () {
    for (final recognizer in [
      OwningHorizontalDragGestureRecognizer(),
      OwningVerticalDragGestureRecognizer(),
    ]) {
      addTearDown(recognizer.dispose);
      for (final kind in PointerDeviceKind.values) {
        expect(
          recognizer.hasSufficientGlobalDistanceToAccept(kind, null),
          isTrue,
          reason: '${recognizer.runtimeType} on $kind',
        );
      }
    }
  });
}
