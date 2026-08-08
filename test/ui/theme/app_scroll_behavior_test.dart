import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/panels/panel_scrollbar.dart';
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
          child: ListView(
            children: const [SizedBox(height: 400, width: 100)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(appBar(), findsOneWidget);
      expect(frameworkBar(), findsNothing);
    });

    testWidgets('and NO bar at all while the content fits', (tester) async {
      // 유저 확정: 꽉차기전에 안보이는. Presence is the signal — and this is
      // not a fade: nothing here is on a timer.
      await tester.pumpWidget(
        host(
          child: ListView(
            children: const [SizedBox(height: 40, width: 100)],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      expect(appBar(), findsNothing);
      expect(frameworkBar(), findsNothing);
    });

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
    });

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
    });

    testWidgets('an explicit PanelScrollbar is not doubled by the '
        'behaviour', (tester) async {
      // The three hand-placed PanelScrollbars carried TWO bars on desktop
      // before this round — their own and the framework's — because
      // PanelScrollbar never told its child to stand down.
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          child: PanelScrollbar(
            controller: controller,
            child: ListView(
              controller: controller,
              children: const [SizedBox(height: 400, width: 100)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(appBar(), findsOneWidget);
      expect(find.byType(PanelScrollbar), findsOneWidget);
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
            child: TextField(
              controller: controller,
              minLines: 2,
              maxLines: 3,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(appBar(), findsNothing);
    });

    testWidgets('the thumb is ONE thickness in every state, and lights '
        'accent on pointer-DOWN rather than on drag', (tester) async {
      await tester.pumpWidget(
        host(
          child: ListView(
            children: const [SizedBox(height: 400, width: 100)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      Size thumbSize() => tester.getSize(
        find.descendant(
          of: appBar(),
          matching: find.byType(AnimatedContainer),
        ),
      );
      Color thumbColor() => (tester
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
    });

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
      expect(theme.thumbColor!.resolve({WidgetState.dragged}), AppColors.accent);
    });
  });
}
