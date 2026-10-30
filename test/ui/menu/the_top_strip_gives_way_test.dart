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
import 'package:flutter/foundation.dart'
    show ValueListenable, precisionErrorTolerance;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/native/device_battery.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/value_hands.dart' show ValuePencil;

import '../../helpers/app_faces.dart';
import '../../helpers/brush_values_on_strip.dart';
import '../../helpers/words_cut_off.dart';

const sizeBar = ValueKey<String>('top-strip-size-bar');
const opacityBar = ValueKey<String>('top-strip-opacity-bar');
const groupButton = ValueKey<String>('top-strip-brush-group-button');
const blendButton = ValueKey<String>('brush-tool-blend-menu-button');
const tabList = ValueKey<String>('project-tab-overflow');
const firstTab = ValueKey<String>('project-tab-0');
const gauge = ValueKey<String>('top-strip-battery');
const opacityCurve = ValueKey<String>('brush-tool-pressure-opacity');

/// What one tab asks of the row, and so what its list button stands in —
/// the tab row's own law (「넘치면 오버플로로 넘긴다」).
const tabPlace = 96.0;

/// What the strip's brush group is at one window width.
enum Standing { full, narrowed, button }

/// The app at [width] — on a device with [battery] where one is handed in —
/// with the brush's values on the strip (I-34: by default the canvas's pill
/// holds them).
Future<void> pumpAt(
  WidgetTester tester,
  double width, {
  ValueListenable<BatteryReading>? battery,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: HomePage(battery: battery)),
  );
  await tester.pumpAndSettle();
  await standBrushValuesOnStrip(tester);
}

Future<void> narrowTo(WidgetTester tester, double width) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  await tester.pumpAndSettle();
}

/// [key] in the strip — found by walking the strip alone.
///
/// ⛔Not `find.descendant(of: find.byType(EditorTopStrip), …)`: that walks
/// the whole app to find the strip each time it is asked, and a sweep asks
/// ten things of each width it stops at — a third of this file's time went
/// to those walks (measured 2026-10-21, heavy-tests-common).
Finder inStrip(Key key) =>
    _InTheStrip((widget) => widget.key == key, 'the $key in the strip');

/// The strip itself, found as [inStrip] finds what is in it.
final Finder theStrip = _InTheStrip(
  (widget) => widget is EditorTopStrip,
  'the strip',
);

/// What [_picks] picks out under the strip's own element — found once and
/// kept while it is mounted, as the app keeps its one strip from a test's
/// first pump to its last.
final class _InTheStrip extends MatchFinder {
  _InTheStrip(this._picks, this._name);

  final bool Function(Widget widget) _picks;
  final String _name;

  static Element? _strip;

  @override
  Iterable<Element> get allCandidates {
    final kept = _strip;
    final strip = kept != null && kept.mounted
        ? kept
        : _strip = find.byType(EditorTopStrip).evaluate().single;
    // The walk leaves out the element it starts from.
    return [
      strip,
    ].followedBy(collectAllElementsFrom(strip, skipOffstage: skipOffstage));
  }

  @override
  bool matches(Element candidate) => _picks(candidate.widget);

  @override
  String get description => _name;
}

double widthOf(WidgetTester tester, Key key) =>
    tester.getSize(inStrip(key)).width;

ValueNotifier<BrushToolState> toolOf(WidgetTester tester) =>
    tester.widget<EditorTopStrip>(find.byType(EditorTopStrip)).brushTool!;

/// A bar at its full width: its track at the 140 it was drawn at, and the
/// pencil after it (tool-settings-panel-tidy, 2026-10-10).
const double fullBar = 140 + ValuePencil.reach;

Standing standingOf(WidgetTester tester) {
  if (inStrip(groupButton).evaluate().isNotEmpty) {
    return Standing.button;
  }
  final narrowed =
      widthOf(tester, sizeBar) < fullBar ||
      widthOf(tester, opacityBar) < fullBar;
  return narrowed ? Standing.narrowed : Standing.full;
}

/// The narrowest a bar of the strip may stand, by the bar's own measure.
double narrowestOf(WidgetTester tester, Key key) => tester
    .widget<FieldSlider>(inStrip(key))
    .narrowestIn(tester.element(inStrip(key)));

/// Narrows the window from [from] to [to], asking [at] of every width it
/// stops at, and returns the standings in the order they came. It stops at
/// every tenth, and at EVERY PIXEL of a tenth the standings change hands in
/// — wherever this language, this text size and this strip put it.
///
/// A tenth whose two ends stand alike is not walked: the group's standing
/// is the room's alone, beside the strip's fixed parts (`_TabsAndBrushGroup`
/// asks `_BrushValueBars.widthsIn` of it), so it cannot change and change
/// back inside one.
///
/// ↩️It walked every pixel of one band in every sweep, 780 down to 690 and
/// two pencils out — where the bars narrow and the button comes in any
/// language (measured 2026-10-07): 140 widths a sweep, and 366s for this
/// file, where the tenths the standings change in are two
/// (2026-10-21, heavy-tests-common).
///
/// ⚠️Never to under 300: at 280 two panel docks are left 24px, less than a
/// tab (`editor_panel_tabs.dart`), and the strip's own fixed parts leave
/// its tabs 83 of the list's 96 (measured 2026-10-15) — and every error at
/// every width is this sweep's to fail on. ↩️It stopped at 480 while the
/// timesheet's pill ran over under 438
/// (`canvas-bottom-bar-overflows-at-437`), at 380 while the timeline's
/// command bar ran over at 360 (`timeline-row-overflows-at-360`), and at
/// 360 while a panel's tab strip ran over at 340 and this strip at 320
/// (`panel-tabs-and-top-strip-overflow-below-360`).
Future<List<Standing>> sweep(
  WidgetTester tester, {
  required double from,
  required double to,
  required void Function(double width, Standing standing) at,
}) async {
  final seen = <Standing>[];
  void stand(double width) {
    expect(tester.takeException(), isNull, reason: 'at $width');
    expect(
      tester.getRect(theStrip).right,
      lessThanOrEqualTo(width),
      reason: 'at $width',
    );
    final standing = standingOf(tester);
    if (seen.isEmpty || seen.last != standing) {
      seen.add(standing);
    }
    at(width, standing);
  }

  for (var width = from; width >= to; width -= 10) {
    await narrowTo(tester, width);
    if (seen.isNotEmpty && standingOf(tester) != seen.last) {
      for (var pixel = width + 9; pixel > width; pixel--) {
        await narrowTo(tester, pixel);
        stand(pixel);
      }
      await narrowTo(tester, width);
    }
    stand(width);
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
        lessThan(fullBar),
        reason: '⛔premise: in the app\'s faces there is something to narrow',
      );
      expect(narrowest.opacity, lessThan(fullBar), reason: '⛔premise');

      var last = (size: fullBar, opacity: fullBar);
      final seen = await sweep(
        tester,
        from: 900,
        to: 300,
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
          // [widthOf] is the bar's own width, which a group the strip draws
          // smaller keeps — 「Where it fits, nothing is scaled」
          // (KeptTailRow). ↩️Without this, full bars held 3px past their
          // room went unseen: the strip drew the group smaller and still
          // fit (2026-10-21, a mutant the sweep let live).
          expect(
            tester.getRect(inStrip(sizeBar)).width,
            closeTo(now.size, 0.01),
            reason: 'the bars are drawn at their own width — at $width',
          );
          expect(now.size, lessThanOrEqualTo(last.size), reason: 'at $width');
          expect(
            now.opacity,
            lessThanOrEqualTo(last.opacity),
            reason: 'a bar never widens as the window narrows — at $width',
          );
          last = now;
          if (standing == Standing.full) {
            expect(
              now,
              (size: fullBar, opacity: fullBar),
              reason: 'at $width',
            );
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
      to: 300,
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
      'that bar stays at its full width and the other narrows alone', (
    tester,
  ) async {
    // French at 1.1×: 「Taille … 2000.0 px」 no longer fits in the full bar,
    // 「Opacité … 100%」 still does.
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.fr,
    );
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    await pumpAt(tester, 900);
    expect(
      narrowestOf(tester, sizeBar),
      greaterThan(fullBar),
      reason: '⛔premise: the size bar has nothing to spare',
    );
    expect(
      narrowestOf(tester, opacityBar),
      lessThan(fullBar - 1),
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
        expect(widthOf(tester, sizeBar), fullBar, reason: 'at $width');
        expect(widthOf(tester, opacityBar), lessThan(fullBar));
      },
    );
    expect(seen, [Standing.full, Standing.narrowed, Standing.button]);
    expect(narrowedSeen, greaterThan(0), reason: '⛔LIVENESS');
  });

  testWidgets('where neither has anything to spare there is nothing to '
      'narrow: the bars stand at their full width, then the group is the '
      'button', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpAt(tester, 900);
    expect(
      narrowestOf(tester, sizeBar),
      greaterThan(fullBar),
      reason: '⛔premise',
    );
    expect(
      narrowestOf(tester, opacityBar),
      greaterThan(fullBar),
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
      expect(tester.getSize(find.byKey(sizeBar)).width, fullBar);
      expect(tester.getSize(find.byKey(opacityBar)).width, fullBar);
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

  // 🗣️I-103-Q1 (유저 2026-10-16): 「띠 오른쪽 끝에 아이콘 + 퍼센트」 — after
  // the brush's group, at the very end; kept to the end as the list
  // button's place is, and costing the group its room: the group becomes
  // the button that much sooner.
  group('the battery', () {
    ValueNotifier<BatteryReading> batteryAt(int percent) {
      final battery = ValueNotifier<BatteryReading>((
        percent: percent,
        charging: false,
      ));
      addTearDown(battery.dispose);
      return battery;
    }

    testWidgets('stands at the very end, after the brush\'s group, at every '
        'width the strip narrows through', (tester) async {
      await pumpAt(tester, 900, battery: batteryAt(87));
      final seen = await sweep(
        tester,
        from: 900,
        to: 300,
        at: (width, standing) {
          expect(inStrip(gauge), findsOneWidget, reason: 'at $width');
          final at = tester.getRect(inStrip(gauge));
          final strip = tester.getRect(theStrip);
          expect(
            strip.right - at.right,
            // A sum of the strip's widths, read as a `RenderFlex` reads its
            // own overflow: 3.000000000000057 at 360 is the end padding.
            lessThanOrEqualTo(3 + precisionErrorTolerance),
            reason: 'nothing stands after it — at $width',
          );
          expect(
            at.left,
            greaterThanOrEqualTo(
              tester
                  .getRect(
                    inStrip(
                      standing == Standing.button ? groupButton : opacityCurve,
                    ),
                  )
                  .right,
            ),
            reason: 'after the group — at $width',
          );
        },
      );
      expect(seen, [Standing.full, Standing.narrowed, Standing.button]);
    });

    testWidgets('costs the brush\'s group its room: the group becomes the '
        'button exactly that much sooner', (tester) async {
      /// The widest whole width at which the group is the button.
      Future<double> buttonFrom(ValueListenable<BatteryReading>? battery) async {
        await pumpAt(tester, 1100, battery: battery);
        expect(standingOf(tester), isNot(Standing.button), reason: '⛔');
        var wide = 1100.0;
        var narrow = 400.0;
        while (wide - narrow > 1) {
          final middle = ((wide + narrow) / 2).floorToDouble();
          await narrowTo(tester, middle);
          if (standingOf(tester) == Standing.button) {
            narrow = middle;
          } else {
            wide = middle;
          }
        }
        await narrowTo(tester, narrow);
        expect(standingOf(tester), Standing.button, reason: '⛔premise');
        return narrow;
      }

      final without = await buttonFrom(null);
      final with_ = await buttonFrom(batteryAt(100));
      final room =
          tester.getRect(inStrip(gauge)).right -
          tester.getRect(inStrip(groupButton)).right;
      expect(room, greaterThan(0), reason: '⛔premise: the gauge takes room');
      expect(with_ - without, closeTo(room, 0.5));
    });

    testWidgets('says the charge in its icon and its percent — the bolt '
        'while on power — and stands at one width whatever it says', (
      tester,
    ) async {
      final battery = batteryAt(100);
      await pumpAt(tester, 1200, battery: battery);
      final place = tester.getRect(inStrip(gauge));
      Finder inGauge(Finder what) =>
          find.descendant(of: inStrip(gauge), matching: what);

      expect(inGauge(find.byIcon(Icons.battery_full)), findsOneWidget);
      expect(inGauge(find.text('100%')), findsOneWidget);
      expect(wordsCutAcross(inStrip(gauge)), isEmpty, reason: 'whole');
      for (final (percent, icon) in const [
        (87, Icons.battery_6_bar),
        (50, Icons.battery_4_bar),
        (7, Icons.battery_0_bar),
      ]) {
        battery.value = (percent: percent, charging: false);
        await tester.pump();
        expect(inGauge(find.byIcon(icon)), findsOneWidget, reason: '$percent');
        expect(inGauge(find.text('$percent%')), findsOneWidget);
        expect(
          tester.getRect(inStrip(gauge)),
          place,
          reason: 'the same place at $percent%',
        );
      }
      battery.value = (percent: 42, charging: true);
      await tester.pump();
      expect(inGauge(find.byIcon(Icons.battery_charging_full)), findsOneWidget);
      expect(inGauge(find.text('42%')), findsOneWidget);
    });

    testWidgets('a device without one keeps no place for it', (tester) async {
      await pumpAt(tester, 1200);
      expect(inStrip(gauge), findsNothing);
    });
  });
}
