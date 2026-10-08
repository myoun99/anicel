// 🗣️top-strip-narrow-overflow-Q1 (유저 2026-10-01): 「줄이지 않고 바로 ⋯
// 목록으로」, corrected a minute later — 「답변 정정. 막대 먼저 줄어들고 다음
// 목록으로」.
//
// AS THE WINDOW NARROWS THE STRIP GIVES WAY IN ONE ORDER AND NEVER RUNS OFF
// ITS END: the project tabs first, down to their list button's place, which
// they keep to the end; then the size and opacity bars, each as far as its
// own writing allows; and past that the brush's whole group is one button
// that opens the same controls under it.
//
// ⚠️In the app's faces or not at all ([loadTheAppFaces]): in the test font
// every glyph is a square, the bars' writing asks for more than the full bar,
// and there is nothing to narrow — the middle standing never happens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/words_cut_off.dart';

const sizeBar = ValueKey<String>('top-strip-size-bar');
const opacityBar = ValueKey<String>('top-strip-opacity-bar');
const groupButton = ValueKey<String>('top-strip-brush-group-button');
const blendButton = ValueKey<String>('brush-tool-blend-menu-button');
const tabList = ValueKey<String>('project-tab-overflow');
const firstTab = ValueKey<String>('project-tab-0');

/// What one tab asks of the row, and so what its list button stands in —
/// the tab row's own law (「넘치면 오버플로로 넘긴다」).
const tabPlace = 96.0;

/// What the strip's brush group is at one window width.
enum Standing { full, narrowed, button }

Future<void> pumpAt(WidgetTester tester, double width) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: const HomePage()),
  );
  await tester.pumpAndSettle();
}

Future<void> narrowTo(WidgetTester tester, double width) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  await tester.pumpAndSettle();
}

Finder inStrip(Key key) => find.descendant(
  of: find.byType(EditorTopStrip),
  matching: find.byKey(key),
);

double widthOf(WidgetTester tester, Key key) =>
    tester.getSize(inStrip(key)).width;

ValueNotifier<BrushToolState> toolOf(WidgetTester tester) =>
    tester.widget<EditorTopStrip>(find.byType(EditorTopStrip)).brushTool!;

Standing standingOf(WidgetTester tester) {
  if (inStrip(groupButton).evaluate().isNotEmpty) {
    return Standing.button;
  }
  final narrowed =
      widthOf(tester, sizeBar) < 140 || widthOf(tester, opacityBar) < 140;
  return narrowed ? Standing.narrowed : Standing.full;
}

/// The narrowest a bar of the strip may stand, by the bar's own measure.
double narrowestOf(WidgetTester tester, Key key) => tester
    .widget<FieldSlider>(inStrip(key))
    .narrowestIn(tester.element(inStrip(key)));

/// The widths a sweep stops at, wide to narrow: EVERY PIXEL where the
/// standings change hands, every tenth elsewhere.
///
/// The bars start to narrow under 770 in any language and at any text size
/// (the strip's fixed parts and the tabs' place are not words), and the
/// group becomes the button no lower than the narrowest pair of names lets
/// it — 727 in Korean, measured 2026-10-07. 780 down to 690 holds both with
/// room; a pair of names short enough to pass 690 would fail 「went all the
/// way to its narrowest」 below, which is the cue to widen this.
Iterable<double> widthsDown(double from, double to) sync* {
  for (
    var width = from;
    width >= to;
    width -= width <= 780 && width > 690 ? 1 : 10
  ) {
    yield width;
  }
}

/// Narrows the window from [from] to [to] ([widthsDown]), asking [at] of
/// every width, and returns the standings in the order they came.
///
/// ⚠️Never to under 480: at 437 the CANVAS panel's bottom bar runs over by
/// two thirds of a pixel (`viewport_bottom_bar_build.dart`, found 2026-10-07
/// writing this) — not the strip's, and every error at every width is this
/// sweep's to fail on.
Future<List<Standing>> sweep(
  WidgetTester tester, {
  required double from,
  required double to,
  required void Function(double width, Standing standing) at,
}) async {
  final seen = <Standing>[];
  for (final width in widthsDown(from, to)) {
    await narrowTo(tester, width);
    expect(tester.takeException(), isNull, reason: 'at $width');
    expect(
      tester.getRect(find.byType(EditorTopStrip)).right,
      lessThanOrEqualTo(width),
      reason: 'at $width',
    );
    final standing = standingOf(tester);
    if (seen.isEmpty || seen.last != standing) {
      seen.add(standing);
    }
    at(width, standing);
  }
  return seen;
}

void main() {
  setUpAll(loadTheAppFaces);

  for (final language in [AppLanguage.en, AppLanguage.ja, AppLanguage.ko]) {
    testWidgets('🚨$language: from a wide window to a narrow one the strip '
        'never runs off its end, and the brush group gives way in one '
        'order — full bars, narrowed bars, one button', (tester) async {
      AppText.settings.value = AppLanguageSettings(programLanguage: language);
      addTearDown(
        () => AppText.settings.value = const AppLanguageSettings(),
      );
      await pumpAt(tester, 900);
      // The widest number the size bar writes — the one its narrowest is
      // measured for, so 「nothing is cut」 below is asked of the worst case.
      toolOf(tester).value = toolOf(
        tester,
      ).value.copyWith(size: BrushToolState.maxSize);
      await tester.pumpAndSettle();
      final narrowest = (
        size: narrowestOf(tester, sizeBar),
        opacity: narrowestOf(tester, opacityBar),
      );
      expect(
        narrowest.size,
        lessThan(140),
        reason: '⛔premise: in the app\'s faces there is something to narrow',
      );
      expect(narrowest.opacity, lessThan(140), reason: '⛔premise');

      var last = (size: 140.0, opacity: 140.0);
      final seen = await sweep(
        tester,
        from: 900,
        to: 480,
        at: (width, standing) {
          // The tabs' place is kept at every width: the one tab stands in
          // it and never has to leave for the list.
          expect(
            inStrip(firstTab),
            findsOneWidget,
            reason: 'the tab keeps its place — at $width',
          );
          expect(inStrip(tabList), findsNothing, reason: 'at $width');
          if (standing == Standing.button) {
            expect(inStrip(sizeBar), findsNothing, reason: 'at $width');
            expect(inStrip(opacityBar), findsNothing, reason: 'at $width');
            expect(inStrip(blendButton), findsNothing, reason: 'at $width');
            return;
          }
          final now = (
            size: widthOf(tester, sizeBar),
            opacity: widthOf(tester, opacityBar),
          );
          expect(now.size, lessThanOrEqualTo(last.size), reason: 'at $width');
          expect(
            now.opacity,
            lessThanOrEqualTo(last.opacity),
            reason: 'a bar never widens as the window narrows — at $width',
          );
          last = now;
          if (standing == Standing.full) {
            expect(now, (size: 140.0, opacity: 140.0), reason: 'at $width');
            return;
          }
          // Whole pixels, so the pixel rounding takes is allowed for.
          expect(
            now.size,
            greaterThan(narrowest.size - 1),
            reason: 'the size bar keeps to its own narrowest — at $width',
          );
          expect(
            now.opacity,
            greaterThan(narrowest.opacity - 1),
            reason: 'the opacity bar keeps to its own — at $width',
          );
          expect(
            [
              ...wordsCutAcross(inStrip(sizeBar)),
              ...wordsCutAcross(inStrip(opacityBar)),
            ],
            isEmpty,
            reason: 'the name and the number are whole — at $width',
          );
        },
      );

      expect(
        seen,
        [Standing.full, Standing.narrowed, Standing.button],
        reason: 'each standing once, in this order — never back',
      );
      expect(
        last.size,
        lessThan(narrowest.size + 1),
        reason: 'the size bar went all the way to its narrowest before the '
            'group became the button',
      );
      expect(last.opacity, lessThan(narrowest.opacity + 1));
    });
  }

  testWidgets('with several projects open the tabs go to their list before '
      'a bar gives a pixel, and the list keeps its place', (tester) async {
    await pumpAt(tester, 1400);
    for (var i = 0; i < 2; i++) {
      await tester.tap(
        find.byKey(const ValueKey<String>('top-strip-project-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('menu-file-new')));
      await tester.pumpAndSettle();
    }
    expect(inStrip(firstTab), findsOneWidget, reason: '⛔premise: tabs show');
    expect(inStrip(tabList), findsNothing, reason: '⛔premise: all three fit');

    var narrowedSeen = 0;
    await sweep(
      tester,
      from: 1400,
      to: 480,
      at: (width, standing) {
        expect(
          inStrip(firstTab).evaluate().isNotEmpty ||
              inStrip(tabList).evaluate().isNotEmpty,
          isTrue,
          reason: 'a tab or the list — the place is never empty, at $width',
        );
        if (standing != Standing.narrowed) {
          return;
        }
        narrowedSeen++;
        expect(
          inStrip(firstTab),
          findsNothing,
          reason: 'every tab left for the list before a bar narrowed — '
              'at $width',
        );
        expect(inStrip(tabList), findsOneWidget, reason: 'at $width');
        expect(
          widthOf(tester, tabList),
          tabPlace,
          reason: 'and the list stands in a tab\'s place — at $width',
        );
      },
    );
    expect(narrowedSeen, greaterThan(0), reason: '⛔LIVENESS: bars narrowed');
  });

  testWidgets('where one bar\'s writing asks for more than the full bar, '
      'that bar stays at 140 and the other narrows alone', (tester) async {
    // French at 1.1×: 「Taille … 2000.0 px」 no longer fits in 140, 「Opacité
    // … 100%」 still does.
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.fr,
    );
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    await pumpAt(tester, 900);
    expect(
      narrowestOf(tester, sizeBar),
      greaterThan(140),
      reason: '⛔premise: the size bar has nothing to spare',
    );
    expect(
      narrowestOf(tester, opacityBar),
      lessThan(139),
      reason: '⛔premise: the opacity bar has',
    );

    var narrowedSeen = 0;
    final seen = await sweep(
      tester,
      from: 900,
      to: 600,
      at: (width, standing) {
        if (standing != Standing.narrowed) {
          return;
        }
        narrowedSeen++;
        expect(widthOf(tester, sizeBar), 140, reason: 'at $width');
        expect(widthOf(tester, opacityBar), lessThan(140));
      },
    );
    expect(seen, [Standing.full, Standing.narrowed, Standing.button]);
    expect(narrowedSeen, greaterThan(0), reason: '⛔LIVENESS');
  });

  testWidgets('where neither has anything to spare there is nothing to '
      'narrow: the bars stand at 140, then the group is the button', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpAt(tester, 900);
    expect(narrowestOf(tester, sizeBar), greaterThan(140), reason: '⛔premise');
    expect(
      narrowestOf(tester, opacityBar),
      greaterThan(140),
      reason: '⛔premise',
    );

    final seen = await sweep(
      tester,
      from: 900,
      to: 600,
      at: (width, standing) {},
    );
    expect(seen, [Standing.full, Standing.button]);
  });

  group('the one button', () {
    Future<double> narrowToTheButton(WidgetTester tester) async {
      await pumpAt(tester, 900);
      var width = 900.0;
      while (standingOf(tester) != Standing.button && width > 400) {
        width -= 10;
        await narrowTo(tester, width);
      }
      expect(standingOf(tester), Standing.button, reason: '⛔premise');
      expect(tester.takeException(), isNull);
      await tester.tap(inStrip(groupButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return width;
    }

    testWidgets('opens the group under it — the blend, the two bars at '
        'their full width and their pressure curves, inside the window', (
      tester,
    ) async {
      final width = await narrowToTheButton(tester);

      for (final key in const [
        sizeBar,
        opacityBar,
        blendButton,
        ValueKey<String>('brush-tool-pressure-size'),
        ValueKey<String>('brush-tool-pressure-opacity'),
      ]) {
        expect(find.byKey(key), findsOneWidget, reason: '$key');
        final rect = tester.getRect(find.byKey(key));
        expect(rect.left, greaterThanOrEqualTo(0), reason: '$key');
        expect(rect.right, lessThanOrEqualTo(width), reason: '$key');
        expect(
          rect.top,
          greaterThanOrEqualTo(
            tester.getRect(find.byType(EditorTopStrip)).bottom,
          ),
          reason: '$key opens UNDER the strip',
        );
      }
      expect(tester.getSize(find.byKey(sizeBar)).width, 140);
      expect(tester.getSize(find.byKey(opacityBar)).width, 140);
      expect(
        tester.getTopLeft(find.byKey(opacityBar)).dy,
        greaterThan(tester.getTopLeft(find.byKey(sizeBar)).dy),
        reason: 'one over the other — a window this narrow has no width to '
            'lay them side by side in',
      );
    });

    testWidgets('holds the SAME controls: its bar sets the tool\'s size and '
        'its blend list picks the tool\'s blend, and it stays while they do', (
      tester,
    ) async {
      await narrowToTheButton(tester);
      final tool = toolOf(tester);

      final before = tool.value.size;
      final bar = tester.getRect(find.byKey(sizeBar));
      await tester.tapAt(Offset(bar.left + bar.width * 0.8, bar.center.dy));
      await tester.pumpAndSettle();
      expect(tool.value.size, isNot(before));
      expect(find.byKey(sizeBar), findsOneWidget, reason: 'it stays open');

      await tester.tap(find.byKey(blendButton));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('brush-tool-blend-multiply')),
      );
      await tester.pumpAndSettle();
      expect(tool.value.activeBlendMode, BrushBlendMode.multiply);
      expect(
        find.byKey(sizeBar),
        findsOneWidget,
        reason: 'picking from the list under it does not close it',
      );
    });

    testWidgets('closes on the first press outside it', (tester) async {
      await narrowToTheButton(tester);
      expect(find.byKey(sizeBar), findsOneWidget, reason: '⛔premise');

      await tester.tapAt(const Offset(40, 500));
      await tester.pumpAndSettle();

      expect(find.byKey(sizeBar), findsNothing);
      expect(inStrip(groupButton), findsOneWidget);
    });
  });
}
