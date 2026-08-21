import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/layer_rail_columns.dart';
import 'package:anicel/src/ui/timeline/row_control_surface.dart';

/// 🚨H1 (유저 2026-08-21): 「지금 레이어 선택범위시 **버튼쪽 탭다운해서
/// 움직이면 선택범위 작동해버리는데** 보통 그게 아니잖아? **버튼쪽 클릭하면
/// 선택범위 작동 안 하도록.** 그 외 부분. **레이어이름영역이나 그 외 버튼
/// 요소가 아닌 부분만** 작동하도록」
///
/// The row's drag recognizer covers the WHOLE row and has to: the name area
/// and the blank between controls are the surface you grab a row by, and
/// neither is a widget of its own. So the exclusion is asked at the PRESS —
/// "did this land on a control?" — and the rail's shared slot builder is
/// what answers, by marking every slot that holds something.
///
/// ⛔An EMPTY slot stays grabbable: reserved space is not a button, and the
/// rail reserves a great deal of it. A test that only checked "the buttons
/// are excluded" would pass with the whole row excluded, which would take
/// the drag away entirely — so the empty slot and the name are pinned too.
void main() {
  /// The subtree the question is asked about — the row itself, standing in
  /// for the rail row the real gate lives on.
  BuildContext host(WidgetTester tester) =>
      tester.element(find.byType(Scaffold));

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );

  testWidgets('a slot that HOLDS something reads as a control', (tester) async {
    await pump(
      tester,
      Row(children: layerRailLeadingCells(typeButton: const SizedBox.expand())),
    );

    final button = find.byType(SizedBox).evaluate().isEmpty
        ? null
        : tester.getCenter(
            find
                .descendant(
                  of: find.byType(RowControlSurface),
                  matching: find.byType(SizedBox),
                )
                .first,
          );
    expect(button, isNotNull, reason: 'fixture premise: the slot rendered');
    expect(RowControlSurface.covers(host(tester), button!), isTrue);
  });

  testWidgets('an EMPTY slot does NOT — reserved space is not a button', (
    tester,
  ) async {
    // The same skeleton with nothing in any slot: every cell is reserved
    // space, so no point in the row may claim to be a control.
    await pump(
      tester,
      SizedBox(height: 24, child: Row(children: layerRailLeadingCells())),
    );

    expect(
      find.byType(RowControlSurface),
      findsNothing,
      reason: 'nothing to mark — the marks follow the CONTENT, not the slot',
    );
  });

  testWidgets('the marker does not swallow the press it wraps', (tester) async {
    // The exclusion must be invisible to the control itself: it adds
    // itself to the hit path, it does not take the path away.
    var taps = 0;
    await pump(
      tester,
      RowControlSurface(
        child: SizedBox(
          width: 40,
          height: 24,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(RowControlSurface));
    await tester.pump();
    expect(taps, 1, reason: 'translucent: the control still gets its press');
  });

  testWidgets('a point outside every control is not a control', (tester) async {
    await pump(
      tester,
      Row(
        children: [
          RowControlSurface(child: const SizedBox(width: 30, height: 24)),
          const SizedBox(width: 120, height: 24, key: ValueKey<String>('name')),
        ],
      ),
    );

    expect(
      RowControlSurface.covers(
        host(tester),
        tester.getCenter(find.byKey(const ValueKey<String>('name'))),
      ),
      isFalse,
      reason:
          'the NAME area is what the user grabs the row by — 「레이어'
          '이름영역이나 그 외 버튼 요소가 아닌 부분만 작동하도록」',
    );
  });

  testWidgets('a pointer that lands on a control starts no pan for the row', (
    tester,
  ) async {
    // The end-to-end shape, said with the real recognizer: an eager pan
    // around a row whose slot holds a control. Pressing the control and
    // moving must leave the row's own drag untouched.
    var panStarts = 0;
    await pump(
      tester,
      GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanDown: (details) {
          if (!RowControlSurface.covers(host(tester), details.globalPosition)) {
            panStarts += 1;
          }
        },
        child: Row(
          children: [
            RowControlSurface(child: const SizedBox(width: 40, height: 24)),
            const SizedBox(
              width: 120,
              height: 24,
              key: ValueKey<String>('name'),
            ),
          ],
        ),
      ),
    );

    final onControl = tester.getCenter(find.byType(RowControlSurface));
    final gesture = await tester.startGesture(
      onControl,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 20));
    await gesture.up();
    await tester.pump();
    expect(panStarts, 0, reason: 'a press on a control begins nothing');

    final gesture2 = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>('name'))),
      kind: PointerDeviceKind.mouse,
    );
    await gesture2.moveBy(const Offset(0, 20));
    await gesture2.up();
    await tester.pump();
    expect(panStarts, 1, reason: 'and the name area still starts one');
  });
}
