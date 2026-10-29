import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/ui/panels/onion_skin_panel.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

import '../helpers/vertical_text_finder.dart';

/// The onion panel's light-table graph: every peg on screen at once, the
/// bars that carry the opacity, the order numbers that switch them, zero as
/// the only off, and the two mode pickers above the strip.
void main() {
  Future<OnionSkinSettings Function()> pumpPanel(
    WidgetTester tester, {
    OnionSkinSettings initial = const OnionSkinSettings(),
    double width = 260,
  }) async {
    var settings = initial;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 300,
              child: StatefulBuilder(
                builder: (context, setState) => OnionSkinPanel(
                  settings: settings,
                  currentColorOf: () => 0xFF000000,
                  onChanged: (next) => setState(() => settings = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return () => settings;
  }

  /// The NUMBER under a bar — the peg's order, and its switch since F-461.
  Finder pegSwitch(String side, int index) =>
      find.byKey(ValueKey<String>('onion-peg-switch-$side-$index'));

  Finder peg(String side, int index) =>
      find.byKey(ValueKey<String>('onion-peg-$side-$index'));

  /// The bar a peg column stands — the app's one slider.
  FieldSlider barOf(WidgetTester tester, String side, int index) =>
      tester.widget<FieldSlider>(
        find.descendant(
          of: peg(side, index),
          matching: find.byType(FieldSlider),
        ),
      );

  testWidgets('all 8 pegs a side are on screen from the start, each bar the '
      'shared slider stood up across the strip', (tester) async {
    await pumpPanel(tester);

    for (var index = 1; index <= OnionSkinSettings.maxPegs; index += 1) {
      for (final side in ['before', 'after']) {
        expect(peg(side, index), findsOneWidget);
        final bar = barOf(tester, side, index);
        expect(bar.axis, Axis.vertical, reason: '$side $index');
        expect(bar.upright, isTrue, reason: '$side $index');
      }
    }
    expect(peg('before', OnionSkinSettings.maxPegs + 1), findsNothing);

    // Pixels, not model values: a bar that lays out to zero is exactly how
    // this panel shipped invisible once.
    final column = tester.getSize(peg('before', 1));
    expect(column.height, 72);
    expect(column.width, greaterThan(4));
  });

  testWidgets('the default ghosts one drawing each way and leaves the rest '
      'at zero — every bar writes its number, the order under it', (
    tester,
  ) async {
    final read = await pumpPanel(tester);

    expect(read().beforePegs.first.opacity, 0.4);
    expect(read().afterPegs.first.opacity, 0.3);
    expect(read().beforePegs.skip(1).every((peg) => !peg.shows), isTrue);
    expect(barOf(tester, 'before', 1).value, 0.4);
    expect(barOf(tester, 'before', 2).value, 0);

    // Percentages: 40, 30 and fourteen zeroes, all written standing.
    expect(findVerticalText('40'), findsOneWidget);
    expect(findVerticalText('30'), findsOneWidget);
    expect(
      findVerticalText('0'),
      findsNWidgets(2 * OnionSkinSettings.maxPegs - 2),
    );

    // ... and the order row underneath.
    expect(find.text('8'), findsNWidgets(2));
    expect(find.text('●'), findsOneWidget);
  });

  /// [side]'s bar [index] filling its track, as drawn on a canvas.
  void Function(Canvas canvas) fillOf(
    WidgetTester tester,
    String side,
    int index,
  ) {
    final track = find.descendant(
      of: peg(side, index),
      matching: find.byType(FieldSliderTrack),
    );
    final fill = tester.widget<FieldSliderTrack>(track).fill;
    final size = tester.getSize(track);
    return (canvas) => fill.paint(canvas, size);
  }

  // 🗣️F-474 (유저 2026-10-26): 「막대 편집할때만 앱 강조색 되어있음 … 지정된
  // 색으로 유지되도록 색 안바뀌게」.
  testWidgets('🚨each side\'s bars fill in that side\'s tint — at rest and '
      'while dragged alike', (tester) async {
    await pumpPanel(
      tester,
      initial: const OnionSkinSettings(
        tintBefore: 0xFF112233,
        tintAfter: 0xFF445566,
      ),
    );
    expect(
      fillOf(tester, 'before', 1),
      paints..rect(color: const Color(0xFF112233)),
    );
    expect(
      fillOf(tester, 'after', 1),
      paints..rect(color: const Color(0xFF445566)),
    );

    final bar = tester.getRect(peg('before', 1));
    final hand = await tester.startGesture(bar.center);
    await hand.moveBy(const Offset(0, -10));
    await tester.pump();
    await hand.moveBy(const Offset(0, -10));
    await tester.pump();
    expect(
      fillOf(tester, 'before', 1),
      paints..rect(color: const Color(0xFF112233)),
      reason: 'dragged',
    );
    await hand.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a vertical drag sets THAT peg\'s opacity, and dragging to '
      'the floor turns it off (0 is a legal value)', (tester) async {
    final read = await pumpPanel(tester);

    final bar = tester.getRect(peg('before', 3));
    await tester.dragFrom(
      bar.bottomCenter - const Offset(0, 20),
      const Offset(0, -20),
    );
    await tester.pumpAndSettle();
    expect(read().beforePegs[2].opacity, greaterThan(0.4));
    expect(read().beforePegs[0].opacity, 0.4, reason: 'one bar, not a side');

    // All the way back down to the floor.
    await tester.dragFrom(
      tester.getRect(peg('before', 3)).topCenter + const Offset(0, 2),
      const Offset(0, 100),
    );
    await tester.pumpAndSettle();
    expect(read().beforePegs[2].opacity, 0);
  });

  /// 🚨★★★**F-461 — THE ORDER NUMBER UNDER THE BAR IS THE SWITCH.**
  ///
  /// > 「슬라이더쪽의 숫자 누르면 꺼지고 켜지는데, 그게 아니라 1번 2번 등
  /// > 슬라이더 아래의 순서 숫자를 버튼으로서 누르면 on/off말한것임」
  /// > (유저 2026-10-23)
  ///
  /// ↩️F-150 ③ had put the switch on the percentage at the bar's floor.
  testWidgets('the order NUMBER is the switch: it silences the peg, and the '
      'next press brings the same falloff back', (tester) async {
    final read = await pumpPanel(tester);

    await tester.tap(pegSwitch('before', 1));
    await tester.pumpAndSettle();
    expect(read().beforePegs[0].opacity, 0);
    expect(read().beforePegs[1].opacity, 0, reason: 'that peg, not a side');

    await tester.tap(pegSwitch('before', 1));
    await tester.pumpAndSettle();
    expect(
      read().beforePegs[0].opacity,
      0.4,
      reason: 'the second press brings the value it had, not a guess',
    );

    // A peg that never had a value comes back at the house default.
    await tester.tap(pegSwitch('after', 5));
    await tester.pumpAndSettle();
    expect(read().afterPegs[4].opacity, 0.3);
  });

  testWidgets('the switch sits under its own bar', (tester) async {
    await pumpPanel(tester);

    const columns = [('before', 8), ('before', 1), ('after', 8)];
    for (final (side, index) in columns) {
      final bar = tester.getRect(peg(side, index));
      final number = tester.getRect(pegSwitch(side, index));
      expect(number.center.dx, closeTo(bar.center.dx, 0.5), reason: side);
      expect(number.top, greaterThanOrEqualTo(bar.bottom), reason: side);
    }
  });

  testWidgets('before pegs stand left of the current drawing and after pegs '
      'right, peg 1 nearest it', (tester) async {
    await pumpPanel(tester);

    double x(Finder finder) => tester.getRect(finder).center.dx;
    final current = x(find.byKey(const ValueKey<String>('onion-peg-current')));
    expect(x(peg('before', 8)), lessThan(x(peg('before', 1))));
    expect(x(peg('before', 1)), lessThan(current));
    expect(x(peg('after', 1)), greaterThan(current));
    expect(x(peg('after', 8)), greaterThan(x(peg('after', 1))));
  });

  testWidgets('a number reads whether its peg shows by its colour alone', (
    tester,
  ) async {
    await pumpPanel(tester);

    Color? inkOf(String side, int index) => tester
        .widget<Text>(
          find.descendant(
            of: pegSwitch(side, index),
            matching: find.byType(Text),
          ),
        )
        .style
        ?.color;
    expect(inkOf('before', 1), AppColors.text);
    expect(inkOf('before', 2), AppColors.textDim);

    await tester.tap(pegSwitch('before', 1));
    await tester.pumpAndSettle();
    expect(inkOf('before', 1), AppColors.textDim);
  });

  testWidgets('the step picker switches between drawing blocks and raw '
      'frames without touching the falloff', (tester) async {
    final read = await pumpPanel(tester);
    expect(read().step, OnionSkinStep.blocks);
    expect(find.text('Blocks'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('onion-step-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('onion-step-frames')));
    await tester.pumpAndSettle();

    expect(read().step, OnionSkinStep.frames);
    expect(find.text('Frames'), findsOneWidget);
    expect(read().beforePegs.first.opacity, 0.4);
  });

  testWidgets('the color mode picker rides beside it', (tester) async {
    final read = await pumpPanel(tester);

    await tester.tap(find.byKey(const ValueKey<String>('onion-mode-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('onion-mode-images')));
    await tester.pumpAndSettle();

    expect(read().mode, OnionSkinMode.images);
    expect(find.text('Images'), findsOneWidget);
  });

  testWidgets('where the ghosts lie is picked beside them — on top of the '
      'frame or in place (onion-ghosts-in-place)', (tester) async {
    final read = await pumpPanel(tester);
    expect(read().placement, OnionSkinPlacement.inPlace);
    expect(find.text('In place'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('onion-placement-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('onion-placement-onTop')),
    );
    await tester.pumpAndSettle();

    expect(read().placement, OnionSkinPlacement.onTop);
    expect(find.text('On top'), findsOneWidget);
    expect(read().beforePegs.first.opacity, 0.4, reason: 'the falloff stays');
  });

  // onion-panel-speaks-english (관제 10-28): the pickers and the pegs'
  // tooltips were English words in every language — 「한국어 · 일본어
  // 화면에서도」.
  testWidgets('the pickers and the pegs speak the program\'s language', (
    tester,
  ) async {
    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ko,
      notationLanguage: AppLanguage.ko,
    );
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    await pumpPanel(tester);

    expect(find.text('블록'), findsOneWidget);
    expect(find.text('색'), findsOneWidget);
    expect(find.text('제자리'), findsOneWidget);
    final peg1 = find.byKey(const ValueKey<String>('onion-peg-before-1'));
    expect(tester.widget<AppTooltip>(peg1).message, '이전 1');
    await tester.tap(pegSwitch('before', 1));
    await tester.pumpAndSettle();
    expect(tester.widget<AppTooltip>(peg1).message, '이전 1 · 끔');

    await tester.tap(find.byKey(const ValueKey<String>('onion-step-button')));
    await tester.pumpAndSettle();
    expect(find.text('블록(그림)'), findsOneWidget);
    expect(find.text('프레임'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('onion-step-frames')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('onion-mode-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('onion-mode-images')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('onion-placement-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('onion-placement-onTop')),
    );
    await tester.pumpAndSettle();
    expect(find.text('프레임'), findsOneWidget);
    expect(find.text('그림'), findsOneWidget);
    expect(find.text('맨 위'), findsOneWidget);
    expect(find.text('이후 1'), findsNothing, reason: 'a tooltip, not text');
    expect(
      tester
          .widget<AppTooltip>(
            find.byKey(const ValueKey<String>('onion-peg-after-1')),
          )
          .message,
      '이후 1',
    );
  });

  testWidgets('at the minimum dock width the strip still lays out — the '
      'bars stand their digits one to a cell, so none step aside', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      // EditorPanelLayoutModel clamps a dock no narrower than this.
      width: 160,
    );

    expect(peg('before', OnionSkinSettings.maxPegs), findsOneWidget);
    expect(findVerticalText('40'), findsOneWidget);
    expect(pegSwitch('after', OnionSkinSettings.maxPegs), findsOneWidget);
    expect(find.text('8'), findsNWidgets(2), reason: 'the order row remains');
    expect(tester.takeException(), isNull);
  });
}
