import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';

/// The app tooltip is Flutter's, holding its global pointer route only while
/// it is showing — so a screen full of tooltips at rest costs a pointer
/// event nothing, and every tooltip still shows, hides and dismisses the way
/// Flutter's does.
void main() {
  int globalRoutes() =>
      GestureBinding.instance.pointerRouter.debugGlobalRouteCount;

  Widget grid(Widget Function(int index) cell) => MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Wrap(
        spacing: 40,
        runSpacing: 40,
        children: [for (var i = 0; i < 40; i += 1) cell(i)],
      ),
    ),
  );

  Widget box(int index) => SizedBox(
    key: ValueKey<String>('box-$index'),
    width: 24,
    height: 24,
  );

  Future<TestGesture> mouseAt(WidgetTester tester, Offset position) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: position);
    addTearDown(mouse.removePointer);
    return mouse;
  }

  // Past the fade either way (in 150ms, out 75ms) and the exit delay (100ms)
  // — in FRAMES: an animation started by a timer inside one long pump has
  // had only that pump's last frame, for Flutter's tooltip as for this one.
  Future<void> settleTooltip(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 10; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('forty tooltips at rest hold no pointer route — where Flutter\'s '
      'hold forty', (tester) async {
    await tester.pumpWidget(grid(box));
    final bare = globalRoutes();

    await tester.pumpWidget(
      grid((i) => Tooltip(message: 'tip $i', child: box(i))),
    );
    expect(
      globalRoutes() - bare,
      40,
      reason: 'premise: Flutter\'s tooltip routes itself from initState',
    );

    await tester.pumpWidget(
      grid((i) => AppTooltip(message: 'tip $i', child: box(i))),
    );
    expect(globalRoutes(), bare);
    expect(AppTooltip.debugRoutesHeld, 0);
  });

  testWidgets('a hover shows it and holds the route while it shows; leaving '
      'hides it and lets the route go', (tester) async {
    await tester.pumpWidget(
      grid((i) => AppTooltip(message: 'tip $i', child: box(i))),
    );
    final mouse = await mouseAt(tester, Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('box-3'))));
    await settleTooltip(tester);
    expect(find.text('tip 3'), findsOneWidget);
    expect(AppTooltip.debugRoutesHeld, 1);

    await mouse.moveTo(const Offset(790, 590));
    await settleTooltip(tester);
    expect(find.text('tip 3'), findsNothing);
    expect(AppTooltip.debugRoutesHeld, 0);
  });

  testWidgets('a press somewhere else takes a shown tooltip down — the route '
      'is there when it is needed', (tester) async {
    await tester.pumpWidget(
      grid((i) => AppTooltip(message: 'tip $i', child: box(i))),
    );
    final mouse = await mouseAt(tester, Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('box-3'))));
    await settleTooltip(tester);
    expect(find.text('tip 3'), findsOneWidget);

    await tester.tapAt(const Offset(790, 590));
    await settleTooltip(tester);
    expect(
      find.text('tip 3'),
      findsNothing,
      reason: 'the mouse still hovers it; only the press elsewhere hides it',
    );
    expect(AppTooltip.debugRoutesHeld, 0);
  });

  testWidgets('a long press shows it for a finger, and after the show '
      'duration it hides and lets go', (tester) async {
    await tester.pumpWidget(
      grid((i) => AppTooltip(message: 'tip $i', child: box(i))),
    );
    await tester.longPress(find.byKey(const ValueKey('box-5')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('tip 5'), findsOneWidget);
    expect(AppTooltip.debugRoutesHeld, 1);

    await tester.pump(const Duration(milliseconds: 1500));
    await settleTooltip(tester);
    expect(find.text('tip 5'), findsNothing);
    expect(AppTooltip.debugRoutesHeld, 0);
  });

  testWidgets('a tooltip taken away while it shows lets its route go', (
    tester,
  ) async {
    await tester.pumpWidget(grid(box));
    final bare = globalRoutes();
    await tester.pumpWidget(
      grid((i) => AppTooltip(message: 'tip $i', child: box(i))),
    );
    final mouse = await mouseAt(tester, Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('box-4'))));
    await settleTooltip(tester);
    expect(AppTooltip.debugRoutesHeld, 1);

    await tester.pumpWidget(grid(box));
    expect(AppTooltip.debugRoutesHeld, 0);
    expect(globalRoutes(), bare);
  });

  testWidgets('dismissAllToolTips takes the app\'s tooltips down too', (
    tester,
  ) async {
    await tester.pumpWidget(
      grid((i) => AppTooltip(message: 'tip $i', child: box(i))),
    );
    final mouse = await mouseAt(tester, Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('box-7'))));
    await settleTooltip(tester);
    expect(find.text('tip 7'), findsOneWidget);

    expect(AppTooltip.dismissAllToolTips(), isTrue);
    await settleTooltip(tester);
    expect(find.text('tip 7'), findsNothing);
    expect(AppTooltip.debugRoutesHeld, 0);
  });

  testWidgets('it shows where and as Flutter\'s shows, in the app theme', (
    tester,
  ) async {
    Future<(Rect, Rect)> shownAt(Widget tooltip) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: Center(child: tooltip)),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('box-0'))));
      await settleTooltip(tester);
      final text = find.text('the same words');
      expect(text, findsOneWidget);
      final shown = (
        tester.getRect(text),
        tester.getRect(
          find.ancestor(of: text, matching: find.byType(Container)).first,
        ),
      );
      await mouse.moveTo(const Offset(1, 1));
      await settleTooltip(tester);
      await mouse.removePointer();
      return shown;
    }

    final theirs = await shownAt(
      Tooltip(message: 'the same words', child: box(0)),
    );
    final ours = await shownAt(
      AppTooltip(message: 'the same words', child: box(0)),
    );
    expect(ours, theirs);
  });

  testWidgets('it is a Tooltip: find.byTooltip reads it', (tester) async {
    await tester.pumpWidget(
      grid((i) => AppTooltip(message: 'tip $i', child: box(i))),
    );
    expect(find.byTooltip('tip 9'), findsOneWidget);
  });
}
