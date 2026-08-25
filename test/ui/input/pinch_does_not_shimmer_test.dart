import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';

/// **F-11 — the pinch zoomed a step out and back, every frame.**
///
/// 유저: 「터치 확대축소 **떨림** … 확대율이 튀어 **1프레임 확대됐다 돌아오는**
/// 현상」.
///
/// 🧪The mechanism, measured: a pinch's two fingers move in the same frame
/// but arrive as SEPARATE events, and the update ran on each one. Between
/// finger A's event and finger B's, the distance was computed from A's new
/// position and B's OLD one — so on a pure pan, with the distance never
/// changing, the emitted zoom read `1.05 → 1.00 → 1.05` inside one batch.
void main() {
  /// The canvas, plus every viewport it emits — the emissions rather than
  /// the settled value, because the whole report is about a value that
  /// comes back before anyone can see it settle.
  Future<List<CanvasViewport>> pumpCanvas(WidgetTester tester) async {
    final emitted = <CanvasViewport>[];
    var viewport = CanvasViewport();
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: CanvasViewportGestureLayer(
              viewport: viewport,
              onViewportChanged: (next) {
                emitted.add(next);
                setState(() => viewport = next);
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return emitted;
  }

  /// Two fingers down, then locked into the navigate gesture.
  Future<(TestPointer, TestPointer)> pinchDown(WidgetTester tester) async {
    final a = TestPointer(1, PointerDeviceKind.touch);
    final b = TestPointer(2, PointerDeviceKind.touch);
    await tester.sendEventToBinding(a.down(const Offset(300, 300)));
    await tester.sendEventToBinding(b.down(const Offset(500, 300)));
    await tester.pump();
    // Past the slop, so the group locks.
    await tester.sendEventToBinding(a.move(const Offset(295, 300)));
    await tester.sendEventToBinding(b.move(const Offset(505, 300)));
    await tester.pump();
    return (a, b);
  }

  testWidgets('🚨a PURE PAN never moves the zoom, not even for one event', (
    tester,
  ) async {
    final emitted = await pumpCanvas(tester);
    final (a, b) = await pinchDown(tester);
    emitted.clear();

    final zooms = <double>[];
    for (var step = 1; step <= 4; step += 1) {
      final dx = 295 + step * 10.0;
      // ⚠️ONE BATCH: both fingers' events dispatch back to back, the way
      // the pointer queue delivers them. `sendEventToBinding` is guarded
      // and cannot be called twice without an await between — which would
      // be a batch of one, and a batch of one is exactly the case that
      // never had the bug.
      tester.binding.handlePointerEvent(a.move(Offset(dx, 300)));
      tester.binding.handlePointerEvent(b.move(Offset(dx + 210, 300)));
      await tester.idle();
      zooms.addAll(emitted.map((viewport) => viewport.zoom));
      emitted.clear();
      await tester.pump();
    }

    expect(
      zooms,
      isNotEmpty,
      reason: 'fixture premise: the pan really is reaching the canvas',
    );
    expect(
      zooms.toSet(),
      hasLength(1),
      reason:
          '🚨THE REPORT: the fingers stayed 210px apart the whole way, so '
          'every emitted zoom must be the same number. Two values means it '
          'stepped out and came back — $zooms',
    );
  });

  testWidgets('and the batch emits ONCE, not once per finger', (tester) async {
    final emitted = await pumpCanvas(tester);
    final (a, b) = await pinchDown(tester);
    emitted.clear();

    tester.binding.handlePointerEvent(a.move(const Offset(280, 300)));
    tester.binding.handlePointerEvent(b.move(const Offset(520, 300)));
    await tester.idle();

    expect(
      emitted,
      hasLength(1),
      reason:
          'one update per batch, off the freshest position of every finger '
          '— the second emission was the one built from a stale one',
    );
  });

  testWidgets('a real pinch still zooms, and by the full amount', (
    tester,
  ) async {
    final emitted = await pumpCanvas(tester);
    final (a, b) = await pinchDown(tester);
    emitted.clear();

    // Apart to 400px, from the 200px the fingers went DOWN at (the anchor
    // is the touchdown, so the whole travel counts).
    tester.binding.handlePointerEvent(a.move(const Offset(200, 300)));
    tester.binding.handlePointerEvent(b.move(const Offset(600, 300)));
    await tester.idle();
    await tester.pump();

    expect(emitted, isNotEmpty);
    expect(
      emitted.last.zoom,
      closeTo(2.0, 0.001),
      reason:
          'coalescing changes WHEN the update runs, never what it computes',
    );
  });

  testWidgets('⛔a batch carrying ONE finger still updates', (tester) async {
    final emitted = await pumpCanvas(tester);
    final (a, _) = await pinchDown(tester);
    emitted.clear();

    // The other finger is resting — it emits nothing, and waiting for it
    // would stall the gesture.
    tester.binding.handlePointerEvent(a.move(const Offset(200, 300)));
    await tester.idle();

    expect(
      emitted,
      isNotEmpty,
      reason:
          'the fix is to coalesce a batch, not to wait for every finger — a '
          'finger that has stopped moving sends nothing to wait for',
    );
  });
}
