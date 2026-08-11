import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/home_page.dart';

/// R6-⑤ — 유저: 「컬러휠패널, 타임시트패널의 아래스플리터가 조작중에 멋대로
/// 그립이 풀려버림. **클릭중인데도.**」
///
/// The splitter widget was never the problem. `_buildRailColumn` returned two
/// DIFFERENT trees — `Padding > Align > column` while the groups fit, and
/// `Stack > … > SingleChildScrollView > column` once they did not. Dragging a
/// group's bottom height grip is what changes that total, so crossing the
/// boundary swapped the trees mid-gesture, element matching failed, and the
/// whole column was rebuilt — disposing the State of the very splitter the
/// hand was holding.
///
/// ★So the contract is about IDENTITY, not about pixels: the scroller's
/// element must be the SAME one before and after the rail overflows. A test
/// that only checked "it still scrolls" would pass on the old code too.
void main() {
  Future<void> pump(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the rail keeps ONE tree shape across the overflow boundary — '
      'the scroller is always mounted, only sometimes live', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Tall enough that the open rail groups fit.
    await pump(tester, const Size(1600, 1100));

    final scroller = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('rail-scroll-'),
    );
    expect(
      scroller,
      findsWidgets,
      reason: 'the scroller is mounted even while the rail fits — that is what '
          'keeps the tree from changing shape under a live drag',
    );
    final before = tester.element(scroller.first);

    // Now squeeze the window until the same groups cannot fit. On the old
    // code this is the moment the tree was swapped.
    await pump(tester, const Size(1600, 460));
    expect(scroller, findsWidgets);

    expect(
      tester.element(scroller.first),
      same(before),
      reason: 'the column was rebuilt across the boundary — that rebuild is '
          'what disposed the held splitter and released the grip',
    );
  });
}
