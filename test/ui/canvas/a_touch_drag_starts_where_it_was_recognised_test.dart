import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';

/// 🗣️**F-260** (유저 10-02): 「시작되면 그때까지 입력된 이동 값이 한번에
/// 입력되서 화면이 갑자기 순간적으로 크게이동되는데 … 시작되기로 인식한 순간
/// … 을 기점으로 시작하게하면 부드럽게 이동시작할거같은데」.
///
/// A touch drag waits out its slop before it is anything — the user keeps
/// that (「프로크리도 그러니」). What it may not do is spend the slop in one
/// frame once it is recognised: a continuous action measures from where it
/// was RECOGNISED.
///
/// ⚠️Every batch carries all of its fingers back to back, the way the
/// pointer queue delivers them. The lock batch of a two-finger drag is the
/// one place a finger read a frame late would skew the anchor — and a
/// skewed anchor stays wrong for the whole gesture.
void main() {
  Future<
    ({
      CanvasViewport Function() view,
      List<double> sizeDrags,
      List<String> sizeCalls,
    })
  >
  pumpCanvas(WidgetTester tester) async {
    var viewport = CanvasViewport();
    final sizeDrags = <double>[];
    final sizeCalls = <String>[];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: CanvasViewportGestureLayer(
              viewport: viewport,
              onViewportChanged: (next) => setState(() => viewport = next),
              onBrushSizeDragStart: () => sizeCalls.add('start'),
              onBrushSizeDragUpdate: (delta, {required snap}) =>
                  sizeDrags.add(delta),
              onBrushSizeDragEnd: () => sizeCalls.add('end'),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (
      view: () => viewport,
      sizeDrags: sizeDrags,
      sizeCalls: sizeCalls,
    );
  }

  /// One batch: every event dispatched before any microtask runs.
  /// `sendEventToBinding` cannot be called twice without an await between,
  /// which would be a batch of one.
  Future<void> batch(WidgetTester tester, List<PointerEvent> events) async {
    for (final event in events) {
      tester.binding.handlePointerEvent(event);
    }
    await tester.idle();
    await tester.pump();
  }

  Future<List<TestPointer>> fingersDown(
    WidgetTester tester,
    List<Offset> at,
  ) async {
    final fingers = [
      for (var i = 0; i < at.length; i += 1)
        TestPointer(i + 1, PointerDeviceKind.touch),
    ];
    for (var i = 0; i < at.length; i += 1) {
      await tester.sendEventToBinding(fingers[i].down(at[i]));
    }
    await tester.pump();
    return fingers;
  }

  List<PointerEvent> moveAll(List<TestPointer> fingers, Offset by) => [
    for (final finger in fingers) finger.move(finger.location! + by),
  ];

  Future<void> liftAll(WidgetTester tester, List<TestPointer> fingers) =>
      batch(tester, [for (final finger in fingers) finger.up()]);

  testWidgets('a two-finger pan moves by the travel AFTER it was recognised '
      '— the slop it waited out never lands, gesture after gesture', (
    tester,
  ) async {
    final probes = await pumpCanvas(tester);

    for (final start in [0.0, 10.0]) {
      final fingers = await fingersDown(tester, const [
        Offset(300, 300),
        Offset(500, 300),
      ]);
      // 30px down together: past the 18px slop, so this batch locks.
      await batch(tester, moveAll(fingers, const Offset(0, 30)));
      expect(
        probes.view(),
        CanvasViewport(panY: start),
        reason:
            '🚨THE REPORT: the 30px the lock waited out landed in one frame',
      );

      await batch(tester, moveAll(fingers, const Offset(0, 10)));
      expect(
        probes.view().panY,
        closeTo(start + 10, 0.001),
        reason: 'the travel since the lock, and only that',
      );
      expect(
        probes.view().zoom,
        closeTo(1, 1e-9),
        reason:
            'the fingers never changed their distance — an anchor that '
            'read the second finger a frame late would have',
      );
      await liftAll(tester, fingers);
    }
  });

  testWidgets('a pinch zooms by the spread AFTER it was recognised', (
    tester,
  ) async {
    final probes = await pumpCanvas(tester);
    final [a, b] = await fingersDown(tester, const [
      Offset(300, 300),
      Offset(500, 300),
    ]);

    // 20px apart each: the lock batch, at 240px.
    await batch(tester, [
      a.move(const Offset(280, 300)),
      b.move(const Offset(520, 300)),
    ]);
    expect(probes.view(), CanvasViewport());

    await batch(tester, [
      a.move(const Offset(270, 300)),
      b.move(const Offset(530, 300)),
    ]);
    expect(
      probes.view().zoom,
      closeTo(260 / 240, 0.001),
      reason:
          'from the 200px the fingers went down at it would read '
          '${260 / 200}',
    );
    await liftAll(tester, [a, b]);
  });

  testWidgets('a brush-size drag starts where it was recognised — once, and '
      'afresh the next time', (tester) async {
    final probes = await pumpCanvas(tester);

    for (var drag = 1; drag <= 2; drag += 1) {
      final fingers = await fingersDown(tester, const [
        Offset(200, 300),
        Offset(260, 300),
        Offset(320, 300),
      ]);
      // 30px up together: the lock batch.
      await batch(tester, moveAll(fingers, const Offset(0, -30)));
      expect(probes.sizeDrags, isEmpty, reason: 'the size never jumps');

      await batch(tester, moveAll(fingers, const Offset(0, -10)));
      expect(
        probes.sizeDrags.single,
        closeTo(10, 0.001),
        reason: 'up = bigger, by the 10px since the lock — not 40',
      );
      await liftAll(tester, fingers);
      expect(probes.sizeCalls, [
        for (var i = 0; i < drag; i += 1) ...['start', 'end'],
      ]);
      probes.sizeDrags.clear();
    }
  });
}
