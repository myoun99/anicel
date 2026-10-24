import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';

import '../../helpers/app_icon_button_probe.dart';

/// The app tooltip is ONE box that summons the window every tooltip in the
/// app shares — so a screen full of tooltips at rest costs a pointer event
/// nothing and a panel shown again one element apiece, and every tooltip
/// still shows, hides and dismisses the way Flutter's does.
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

  /// Whether [words] are on screen — a window still in the tree but faded
  /// to nothing shows nothing.
  bool shows(WidgetTester tester, String words) {
    final text = find.text(words);
    if (text.evaluate().isEmpty) {
      return false;
    }
    final fade = find.ancestor(of: text, matching: find.byType(FadeTransition));
    return tester.widget<FadeTransition>(fade.first).opacity.value > 0;
  }

  testWidgets('it is one element over its child', (tester) async {
    await tester.pumpWidget(
      grid((i) => AppTooltip(message: 'tip $i', child: box(i))),
    );
    final tooltip = tester.element(find.byType(AppTooltip).first);
    final children = <Element>[];
    tooltip.visitChildren(children.add);
    expect(children.single.widget.key, const ValueKey<String>('box-0'));
  });

  testWidgets("forty tooltips at rest hold no pointer route — where Flutter's "
      'hold forty', (tester) async {
    await tester.pumpWidget(grid(box));
    final bare = globalRoutes();

    await tester.pumpWidget(
      grid((i) => Tooltip(message: 'tip $i', child: box(i))),
    );
    expect(
      globalRoutes() - bare,
      40,
      reason: "premise: Flutter's tooltip routes itself from initState",
    );

    await tester.pumpWidget(
      grid((i) => AppTooltip(message: 'tip $i', child: box(i))),
    );
    expect(globalRoutes(), bare);
  });

  testWidgets('a hover shows it and holds the route while it shows; leaving '
      'hides it and lets the route go', (tester) async {
    await tester.pumpWidget(
      grid((i) => AppTooltip(message: 'tip $i', child: box(i))),
    );
    final bare = globalRoutes();
    final mouse = await mouseAt(tester, Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('box-3'))));
    await settleTooltip(tester);
    expect(find.text('tip 3'), findsOneWidget);
    expect(globalRoutes(), bare + 1);

    await mouse.moveTo(const Offset(790, 590));
    await settleTooltip(tester);
    expect(find.text('tip 3'), findsNothing);
    expect(globalRoutes(), bare);
  });

  testWidgets('a press somewhere else takes a shown tooltip down — the route '
      'is there when it is needed', (tester) async {
    await tester.pumpWidget(
      grid((i) => AppTooltip(message: 'tip $i', child: box(i))),
    );
    final bare = globalRoutes();
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
    expect(globalRoutes(), bare);
  });

  testWidgets('a long press shows it for a finger, and after the show '
      'duration it hides and lets go', (tester) async {
    await tester.pumpWidget(
      grid((i) => AppTooltip(message: 'tip $i', child: box(i))),
    );
    final bare = globalRoutes();
    await tester.longPress(find.byKey(const ValueKey('box-5')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('tip 5'), findsOneWidget);
    expect(globalRoutes(), bare + 1);

    await tester.pump(const Duration(milliseconds: 1500));
    await settleTooltip(tester);
    expect(find.text('tip 5'), findsNothing);
    expect(globalRoutes(), bare);
  });

  testWidgets('a tooltip whose trigger is manual opens to a hover, never to '
      'a long press', (tester) async {
    await tester.pumpWidget(
      grid(
        (i) => AppTooltip(
          message: 'tip $i',
          triggerMode: TooltipTriggerMode.manual,
          child: box(i),
        ),
      ),
    );
    await tester.longPress(find.byKey(const ValueKey('box-5')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('tip 5'), findsNothing);

    final mouse = await mouseAt(tester, Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('box-5'))));
    await settleTooltip(tester);
    expect(find.text('tip 5'), findsOneWidget);
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
    expect(globalRoutes(), bare + 1);

    await tester.pumpWidget(grid(box));
    expect(
      shows(tester, 'tip 4'),
      isFalse,
      reason: 'gone in the frame its target went, as a tooltip unmounted '
          'with its target was',
    );
    expect(globalRoutes(), bare);
    await tester.pump();
    expect(find.text('tip 4'), findsNothing);
  });

  testWidgets("dismissAllToolTips takes the app's tooltips down too", (
    tester,
  ) async {
    await tester.pumpWidget(
      grid((i) => AppTooltip(message: 'tip $i', child: box(i))),
    );
    final bare = globalRoutes();
    final mouse = await mouseAt(tester, Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('box-7'))));
    await settleTooltip(tester);
    expect(find.text('tip 7'), findsOneWidget);

    expect(AppTooltip.dismissAllToolTips(), isTrue);
    await settleTooltip(tester);
    expect(find.text('tip 7'), findsNothing);
    expect(globalRoutes(), bare);
  });

  testWidgets("it shows where and as Flutter's shows, in the app theme", (
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

  testWidgets("a screen reader hears it as Flutter's", (tester) async {
    final handle = tester.ensureSemantics();
    Widget scene(Widget tooltip) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: Semantics(
            container: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [const Text('before'), tooltip],
            ),
          ),
        ),
      ),
    );
    Future<SemanticsData> heard(Widget tooltip) async {
      await tester.pumpWidget(scene(tooltip));
      return tester.getSemantics(find.text('before')).getSemanticsData();
    }

    const words = Text('words');
    final theirs = await heard(const Tooltip(message: 'said', child: words));
    final ours = await heard(const AppTooltip(message: 'said', child: words));
    expect(ours.tooltip, 'said');
    expect(ours.tooltip, theirs.tooltip);
    expect(ours.label, theirs.label);
    expect(ours.textDirection, theirs.textDirection);
    expect(ours.flagsCollection, theirs.flagsCollection);
    expect(ours.actions, theirs.actions);

    // Built again with other words, it says them in the same frame.
    await tester.pumpWidget(
      scene(const AppTooltip(message: 'said again', child: words)),
    );
    expect(
      tester.getSemantics(find.text('before')).getSemanticsData().tooltip,
      'said again',
    );
    handle.dispose();
  });

  testWidgets("it takes a press on all of its box, as Flutter's does — and "
      'an empty one is its child alone', (tester) async {
    Future<int> pressesUnder(Widget tooltip) async {
      var under = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => under += 1,
                ),
              ),
              Center(child: tooltip),
            ],
          ),
        ),
      );
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('box-0'))),
      );
      return under;
    }

    expect(await pressesUnder(Tooltip(message: 'm', child: box(0))), 0);
    expect(await pressesUnder(AppTooltip(message: 'm', child: box(0))), 0);
    expect(await pressesUnder(Tooltip(message: '', child: box(0))), 1);
    expect(await pressesUnder(AppTooltip(message: '', child: box(0))), 1);
  });

  testWidgets('only the innermost tooltip answers a hover — another tooltip '
      'or a button inside it', (tester) async {
    Widget outer(Widget inner) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: AppTooltip(
            message: 'outer',
            child: SizedBox(
              key: const ValueKey<String>('outer'),
              width: 200,
              height: 60,
              child: Align(alignment: Alignment.centerRight, child: inner),
            ),
          ),
        ),
      ),
    );
    Future<List<String>> shownOver(Widget inner, Offset Function() at) async {
      await tester.pumpWidget(outer(inner));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(at());
      await settleTooltip(tester);
      final shown = [
        for (final words in ['outer', 'inner'])
          if (find.text(words).evaluate().isNotEmpty) words,
      ];
      await mouse.removePointer();
      await settleTooltip(tester);
      return shown;
    }

    Offset leftOfTheOuter() =>
        tester.getTopLeft(find.byKey(const ValueKey('outer'))) +
        const Offset(10, 30);
    final nested = AppTooltip(message: 'inner', child: box(1));
    expect(
      await shownOver(
        nested,
        () => tester.getCenter(find.byKey(const ValueKey('box-1'))),
      ),
      ['inner'],
    );
    expect(await shownOver(nested, leftOfTheOuter), ['outer']);

    final button = AppIconButton(
      keyValue: 'inner-button',
      tooltip: 'inner',
      icon: const Icon(Icons.close),
      onPressed: () {},
    );
    expect(
      await shownOver(
        button,
        () => tester.getCenter(find.tooltipSaying('inner')),
      ),
      ['inner'],
    );
  });

  testWidgets('find.tooltipSaying reads it', (tester) async {
    await tester.pumpWidget(
      grid((i) => AppTooltip(message: 'tip $i', child: box(i))),
    );
    expect(find.tooltipSaying('tip 9'), findsOneWidget);
  });
}
