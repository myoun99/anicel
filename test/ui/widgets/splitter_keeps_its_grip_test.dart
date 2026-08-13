import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/dock_edge_splitter.dart';

/// T30 (유저 2026-08-14): 「패널 길이 늘리는 **스플리터가 도중에 그립이 풀려서
/// 멈춤. 마우스 여전히 클릭도중인데도.** 빠르게 드래그하다보면 풀리는거같음.」
///
/// The grip used to read the pointer raw and ask, on every move, whether a
/// rival scroller had travelled far enough ACROSS its axis to have earned the
/// gesture — and answered by letting go. A fast pull puts more travel in each
/// event, so the cross-axis component cleared that threshold sooner. It was
/// never robbed; it resigned.
///
/// The grip wins the arena now, so there is no rival to resign to. These pin
/// the two halves: the deltas keep arriving however crooked the pull is, and
/// a press on the grip never reaches a scrollable underneath it.
const _splitterKey = ValueKey<String>('t30-splitter');

Widget _harness(List<double> deltas, {ScrollController? controller}) {
  final splitter = DockEdgeSplitter(
    key: _splitterKey,
    axis: Axis.horizontal,
    onDragDelta: (delta) {
      deltas.add(delta);
      // The host consumes everything: this test is about the deltas
      // ARRIVING, not about what an edge does with them.
      return delta;
    },
  );
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: controller == null
          ? Center(child: SizedBox(width: 400, child: splitter))
          : ListView(
              controller: controller,
              children: [
                const SizedBox(height: 100),
                SizedBox(width: 400, child: splitter),
                const SizedBox(height: 1200),
              ],
            ),
    ),
  );
}

void main() {
  testWidgets('a crooked, fast pull never loses the grip', (tester) async {
    final deltas = <double>[];
    await tester.pumpWidget(_harness(deltas));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_splitterKey)),
      kind: PointerDeviceKind.mouse,
    );
    // Every move carries far more travel ACROSS the grip's axis than along
    // it — 40px sideways per step, way past any scroll slop. Under the
    // retired rule the first of these ended the drag.
    for (var step = 0; step < 6; step += 1) {
      await gesture.moveBy(const Offset(40, 6));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      deltas.length,
      6,
      reason: 'one delta per move, all the way to the lift',
    );
    expect(
      deltas.fold<double>(0, (sum, d) => sum + d),
      moreOrLessEquals(36, epsilon: 0.01),
      reason: 'a horizontal splitter moves along Y, and it got all of it',
    );
  });

  testWidgets('a press on the grip never reaches the list under it', (
    tester,
  ) async {
    final deltas = <double>[];
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(deltas, controller: controller));

    await tester.drag(
      find.byKey(_splitterKey),
      const Offset(0, -80),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pumpAndSettle();

    expect(
      controller.offset,
      0,
      reason: 'the grip took the gesture on the first movement and kept it',
    );
    expect(deltas, isNotEmpty, reason: 'and spent it on the splitter');
  });
}
