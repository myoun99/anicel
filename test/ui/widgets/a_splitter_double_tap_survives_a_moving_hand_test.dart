import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/dock_edge_splitter.dart';

/// F-120's sweep (유저 2026-09-13: 「펜이라 클릭중에 커서 위치 바뀌는데 그게
/// 영향이 있을것으로 추측? 그런 커서 위치따라 판정하는거 없도록 … 다른곳도
/// 그렇게 되있을텐데」).
///
/// The splitter's grip takes the arena on the FIRST MOVEMENT — that is what
/// keeps it from letting go mid-drag (T30), and it is not up for trade. Its
/// double tap sat beside that drag as a gesture-arena recogniser, and a
/// recogniser that has to WIN the arena loses it to a drag that accepts on
/// the first movement. A pen is never perfectly still, so the question these
/// ask is the caret's question again: does a double tap that moves a little
/// still reset the edge?
const _splitterKey = ValueKey<String>('double-tap-splitter');

Future<int Function()> _pump(WidgetTester tester) async {
  var doubleTaps = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: DockEdgeSplitter.thickness,
            height: 300,
            child: DockEdgeSplitter(
              key: _splitterKey,
              axis: Axis.vertical,
              onDragDelta: (delta) => delta,
              onDoubleTap: () => doubleTaps += 1,
            ),
          ),
        ),
      ),
    ),
  );
  return () => doubleTaps;
}

Future<void> _press(
  WidgetTester tester,
  PointerDeviceKind kind, {
  required bool moving,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(_splitterKey)),
    kind: kind,
  );
  if (moving) {
    await gesture.moveBy(const Offset(0, 2));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -1));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 60));
}

void main() {
  for (final moving in const [false, true]) {
    for (final kind in const [
      PointerDeviceKind.stylus,
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
    ]) {
      final how = moving ? 'that moves a little' : 'held still';
      testWidgets('${kind.name}: a double tap $how resets the edge', (
        tester,
      ) async {
        final doubleTaps = await _pump(tester);

        await _press(tester, kind, moving: moving);
        await _press(tester, kind, moving: moving);
        await tester.pumpAndSettle();

        expect(doubleTaps(), 1);
      });
    }
  }
}
