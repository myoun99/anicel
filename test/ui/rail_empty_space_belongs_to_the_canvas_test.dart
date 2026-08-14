import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../helpers/panel_finders.dart';

/// 유저 (2026-08-15 #1): 「패널을 하나라도 열면, 작은거 열면 밑에 공간
/// 남는데 그 공간에서 터치가 안먹힘」 — and drawing there was refused too,
/// which is the same sentence: a hit test that stops has stopped for every
/// verb at once.
///
/// A rail column is laid out FULL HEIGHT whatever is open on it — that is
/// deliberate, and R6-⑤ pinned it (one tree shape, always, or the splitter
/// releases itself mid-drag). What was not deliberate is that the scroller
/// filling that column took the pointer across the whole rectangle:
/// `SingleChildScrollView.hitTestBehavior` defaults to
/// [HitTestBehavior.opaque], so the pasteboard under a short panel was a
/// pane of glass over live canvas.
///
/// ★The contract is about WHO GETS THE POINTER, not about pixels: the rail
/// owns exactly the rectangles its panels occupy, and every other point in
/// the column belongs to the floor underneath.
void main() {
  Future<void> pumpWithDrawableCel(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    // The default project has no cel at the playhead, and without one the
    // drawing view is not mounted at all — author one, because the point of
    // these tests is where a press CAN and CANNOT reach it.
    final addButton = find.byKey(const ValueKey<String>('new-frame-button'));
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(mainCanvasView(), findsOneWidget);
  }

  testWidgets('the empty space under a short rail panel belongs to the '
      'canvas — a press there reaches the drawing view', (tester) async {
    await pumpWithDrawableCel(tester);

    final column = tester.getRect(
      find.byKey(const ValueKey<String>('editor-panel-dock-left')),
    );
    final panel = tester.getRect(find.byType(BrushPresetPanel));
    expect(
      panel.bottom,
      lessThan(column.bottom - 60),
      reason: 'the window has to be tall enough that the open group leaves '
          'pasteboard below it — otherwise this test proves nothing',
    );

    // Below the panel, inside the column's own width: the exact place the
    // user put a finger.
    final press = Offset(panel.center.dx, column.bottom - 30);
    final result = tester.hitTestOnBinding(press);
    final canvas = tester.renderObject(mainCanvasView());

    expect(
      result.path.any((entry) => entry.target == canvas),
      isTrue,
      reason: 'the rail column swallowed a press aimed at the canvas — the '
          'floor is full-bleed under it, so nothing else can be the target',
    );
  });

  // The other half of the same law, and the guard against fixing this by
  // making the whole column transparent: ON the panel, the rail still wins.
  // It also pins that the SCROLLER is still in the route there — which is
  // what lets the rail go on scrolling once its groups overflow, the only
  // state in which a drag over the column has anywhere to go.
  testWidgets('a press ON the open panel still belongs to the rail, '
      'scroller included', (tester) async {
    await pumpWithDrawableCel(tester);

    final press = tester.getCenter(find.byType(BrushPresetPanel));
    final result = tester.hitTestOnBinding(press);
    final canvas = tester.renderObject(mainCanvasView());
    final scroller = tester.renderObject(
      find.byKey(const ValueKey<String>('rail-scroll-left')),
    );

    expect(
      result.path.any((entry) => entry.target == scroller),
      isTrue,
      reason: 'the rail scroller left the route — a rail that overflows '
          'could no longer be dragged',
    );
    expect(
      result.path.any((entry) => entry.target == canvas),
      isFalse,
      reason: 'a press on a panel must not fall through to the artwork',
    );
  });
}
