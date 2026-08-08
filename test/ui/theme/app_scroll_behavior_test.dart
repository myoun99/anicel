import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar.dart';

/// The app has ONE scrollbar, and this is where that is a contract rather
/// than a habit.
///
/// ⚠️It has to build its own `MaterialApp` with the behaviour installed.
/// The rest of the suite pumps a bare `MaterialApp`, and a bare one runs as
/// `TargetPlatform.android` in tests — where `MaterialScrollBehavior` never
/// built a scrollbar at all. So the entire 5000-test corpus has been blind
/// to every scrollbar decision the desktop app makes, in both directions:
/// it never saw the framework bar this replaces, and it will not see this
/// one either unless a test asks for it the way these do.
void main() {
  // ★THE PLATFORM IS THE POINT, so every case below states one. Tests run
  // as `TargetPlatform.android` by default and the behaviour bars desktop
  // only — so without a variant every assertion here would pass for the
  // wrong reason (no bar, because no platform), including the "and no
  // framework bar" one, which android never had either. The variant is
  // also what resets the override: leaving it set past a test trips
  // `debugAssertAllFoundationVarsUnset`.
  final desktop = TargetPlatformVariant.desktop();

  Widget host({required Widget child, ScrollBehavior? behavior}) => MaterialApp(
    theme: buildAppTheme(),
    scrollBehavior: behavior ?? const AppScrollBehavior(),
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 200, height: 100, child: child),
    ),
  );

  Finder appBar() => find.byType(AppControllerScrollbar);
  Finder frameworkBar() => find.byType(Scrollbar);

  group('AppScrollBehavior', () {
    testWidgets('an overflowing scrollable gets the APP bar and no '
        'framework one — with no controller of its own', (tester) async {
      // The whole reason a behaviour beats hand-adding bars: `Scrollable`
      // always hands `buildScrollbar` its effective controller, so a
      // ListView that owns none still gets a working bar.
      await tester.pumpWidget(
        host(
          child: ListView(children: const [SizedBox(height: 400, width: 100)]),
        ),
      );
      await tester.pumpAndSettle();

      expect(appBar(), findsOneWidget);
      expect(frameworkBar(), findsNothing);
    }, variant: desktop);

    testWidgets('and NO bar at all while the content fits', (tester) async {
      // 유저 확정: 꽉차기전에 안보이는. Presence is the signal — and this is
      // not a fade: nothing here is on a timer.
      await tester.pumpWidget(
        host(
          child: ListView(children: const [SizedBox(height: 40, width: 100)]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      expect(appBar(), findsNothing);
      expect(frameworkBar(), findsNothing);
    }, variant: desktop);

    testWidgets('a HORIZONTAL overflow gets one too, which Flutter never '
        'gave it', (tester) async {
      await tester.pumpWidget(
        host(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: const SizedBox(width: 900, height: 40),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bar = tester.widget<AppControllerScrollbar>(appBar());
      expect(bar.axis, Axis.horizontal);
    }, variant: desktop);

    testWidgets('UnbarredScrollable takes the bar off a command strip', (
      tester,
    ) async {
      // 유저 확정: 가로 스크롤은 내용에만. A compressed tool strip scrolls as
      // an escape valve, and a 12px lane across a 30px row of buttons eats
      // the bottom third of every target in it.
      await tester.pumpWidget(
        host(
          child: UnbarredScrollable(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: const SizedBox(width: 900, height: 40),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(appBar(), findsNothing);
    }, variant: desktop);

    testWidgets('a NESTED scrollable keeps its OWN bar', (tester) async {
      // 🐛The regression this replaces. The first cut stopped the three
      // hand-placed PanelScrollbars from being doubled by switching
      // scrollbars off for their child — but the child is the whole scroll
      // CONTENT and a ScrollConfiguration is inherited, so every scrollable
      // NESTED inside went silent too. The media browser's asset list lost
      // its bar the moment the panel was narrow enough to need the
      // horizontal escape valve above it.
      await tester.pumpWidget(
        host(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 900,
              child: SizedBox(
                height: 100,
                child: ListView(
                  children: const [SizedBox(height: 400, width: 100)],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final axes = tester
          .widgetList<AppControllerScrollbar>(appBar())
          .map((bar) => bar.axis)
          .toSet();
      expect(axes, {Axis.horizontal, Axis.vertical});
    }, variant: desktop);

    test('the BEHAVIOUR is the only thing that places a PanelScrollbar', () {
      // Nothing hand-places one any more, and nothing may start: a bar
      // placed by hand around a scrollable the behaviour also bars is two
      // bars, and the obvious cure for that is the nesting leak above.
      final offenders = <String>[];
      for (final entity in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!entity.path.endsWith('.dart')) {
          continue;
        }
        final name = entity.uri.pathSegments.last;
        if (name == 'panel_scrollbar.dart' ||
            name == 'app_scroll_behavior.dart') {
          continue;
        }
        if (entity.readAsStringSync().contains('PanelScrollbar(')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty);
    });

    testWidgets('a multiline TEXT FIELD never gets one', (tester) async {
      // EditableText delegates the decision to us when it is multiline, so
      // this is ours to refuse — and it must be refused: the lane hit-tests
      // opaque and would swallow taps aimed at the end of a line.
      final controller = TextEditingController(
        text: List<String>.filled(40, 'line').join('\n'),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          child: Material(
            child: TextField(controller: controller, minLines: 2, maxLines: 3),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(appBar(), findsNothing);
    }, variant: desktop);

    testWidgets('two scrollables SHARING one controller do not crash the '
        'frame', (tester) async {
      // 🚨`ScrollController.position` asserts on two attached views, and
      // `hasClients` only rules out zero. Synchronised panes are an
      // ordinary thing to build, and they became this widget's problem the
      // moment it stopped being something a caller opts into.
      final shared = ScrollController();
      addTearDown(shared.dispose);
      await tester.pumpWidget(
        host(
          child: Column(
            children: [
              for (var i = 0; i < 2; i++)
                SizedBox(
                  height: 50,
                  child: ListView(
                    controller: shared,
                    children: const [SizedBox(height: 400, width: 100)],
                  ),
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // And it stands down rather than guessing which pane it is reading.
      expect(appBar(), findsNothing);
    }, variant: desktop);

    testWidgets('the thumb is ONE thickness in every state, and lights '
        'accent on pointer-DOWN rather than on drag', (tester) async {
      await tester.pumpWidget(
        host(
          child: ListView(children: const [SizedBox(height: 400, width: 100)]),
        ),
      );
      await tester.pumpAndSettle();

      Size thumbSize() => tester.getSize(
        find.descendant(of: appBar(), matching: find.byType(AnimatedContainer)),
      );
      Color thumbColor() =>
          (tester
                      .widget<AnimatedContainer>(
                        find.descendant(
                          of: appBar(),
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;

      final atRest = thumbSize();
      expect(thumbColor(), AppColors.hairlineStrong);

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(appBar()));
      await tester.pumpAndSettle();
      expect(thumbSize(), atRest, reason: 'hover may not resize it');
      expect(thumbColor(), Colors.white);

      // Pressed WITHOUT moving: the accent has to be on already.
      await pointer.down(tester.getCenter(appBar()));
      await tester.pumpAndSettle();
      expect(thumbSize(), atRest, reason: 'a press may not resize it either');
      expect(thumbColor(), AppColors.accent);
      await pointer.up();
      await tester.pumpAndSettle();
    }, variant: desktop);

    testWidgets('on a MOBILE platform it bars nothing — and says so rather '
        'than failing to', (tester) async {
      // Every controller-less vertical scroll view on a route shares that
      // route's PrimaryScrollController there, so a per-scrollable bar has
      // no viewport it can name. Two of them used to take the frame down;
      // now the behaviour declines up front.
      await tester.pumpWidget(
        host(
          child: Column(
            children: [
              for (var i = 0; i < 2; i++)
                SizedBox(
                  height: 50,
                  child: ListView(
                    children: const [SizedBox(height: 400, width: 100)],
                  ),
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(appBar(), findsNothing);
      expect(frameworkBar(), findsNothing);
    }, variant: TargetPlatformVariant.mobile());

    testWidgets('the theme keeps the ONE species it cannot reach on the '
        'same visuals', (tester) async {
      // Dropdown and MenuAnchor menus build their own Scrollbar behind a
      // `scrollbars: false` wall, so ScrollbarThemeData is their only
      // styling — and its thickness must not move under the pointer either.
      final theme = buildAppTheme().scrollbarTheme;
      for (final states in <Set<WidgetState>>[
        <WidgetState>{},
        {WidgetState.hovered},
        {WidgetState.dragged},
      ]) {
        expect(
          theme.thickness!.resolve(states),
          4,
          reason: 'constant thickness in $states',
        );
      }
      expect(
        theme.thumbColor!.resolve({WidgetState.dragged}),
        AppColors.accent,
      );
    });
  });
}
