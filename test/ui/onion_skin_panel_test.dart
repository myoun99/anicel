import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/ui/panels/onion_skin_panel.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../helpers/library_source.dart';

/// The onion panel's light-table graph: every peg on screen at once, the
/// bars that carry the opacity, zero as the only off, and the two mode
/// pickers above the strip.
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

  /// The NUMBER at a column's floor — the switch, since F-150 ③. It is a
  /// SIBLING of the bar layer, not a descendant, because a button cannot
  /// live inside the slider's claim.
  Finder pegSwitch(String side, int index) =>
      find.byKey(ValueKey<String>('onion-peg-switch-$side-$index'));

  Finder peg(String side, int index) =>
      find.byKey(ValueKey<String>('onion-peg-$side-$index'));

  /// The painted bar inside a peg column (absent while the peg is at 0).
  Finder barOf(Finder column) =>
      find.descendant(of: column, matching: find.byType(DecoratedBox));

  testWidgets('all 8 pegs a side are on screen from the start, and the bars '
      'occupy real pixels', (tester) async {
    await pumpPanel(tester);

    for (var index = 1; index <= OnionSkinSettings.maxPegs; index += 1) {
      expect(peg('before', index), findsOneWidget);
      expect(peg('after', index), findsOneWidget);
    }
    expect(peg('before', OnionSkinSettings.maxPegs + 1), findsNothing);

    // The column fills the strip's interior; the bar is 40% of it.
    // (Pixels, not model values: a bar that lays out to zero is exactly
    // how this panel shipped invisible once.)
    final column = tester.getSize(peg('before', 1));
    expect(column.height, 70);
    // The column's own DecoratedBox (side wash) plus the bar's.
    final bar = tester.getSize(barOf(peg('before', 1)).last);
    expect(bar.width, greaterThan(4));
    expect(bar.height, closeTo(0.4 * 70, 0.5));
  });

  testWidgets('the default ghosts one drawing each way and leaves the rest '
      'at zero — a silent peg draws no bar but still reads its 0', (
    tester,
  ) async {
    final read = await pumpPanel(tester);

    expect(read().beforePegs.first.opacity, 0.4);
    expect(read().afterPegs.first.opacity, 0.3);
    expect(read().beforePegs.skip(1).every((peg) => !peg.shows), isTrue);

    // Peg 2 has only its side wash — no bar box inside it.
    expect(barOf(peg('before', 2)), findsOneWidget);
    expect(barOf(peg('before', 1)), findsNWidgets(2));

    // Percentages: 40, 30 and fourteen zeroes, all printed.
    expect(find.text('40'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(2 * OnionSkinSettings.maxPegs - 2));

    // ... and the index row underneath.
    expect(find.text('8'), findsNWidgets(2));
    expect(find.text('●'), findsOneWidget);
  });

  testWidgets('the percentage sits on the strip floor, not on top of its '
      'bar — the readout keeps one baseline', (tester) async {
    await pumpPanel(tester);

    final strip = tester.getRect(peg('before', 1));
    final tall = tester.getRect(find.text('40'));
    final flat = tester.getRect(find.text('0').first);
    expect(tall.bottom, closeTo(flat.bottom, 0.5));
    expect(strip.bottom - tall.bottom, lessThan(4));
  });

  testWidgets('a vertical drag sets THAT peg\'s opacity, and dragging to '
      'the floor turns it off (0 is a legal value)', (tester) async {
    final read = await pumpPanel(tester);

    final bar = tester.getRect(peg('before', 3));
    // ⚠️NOT from the very floor any more: the bottom of each column is the
    // NUMBER now (F-150 ③), and it is a button. The slider is everything
    // above it. Starting 20px up is the same drag — the strip edits the peg
    // the press LANDED on, wherever in the column that was.
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

  /// 🚨★★★**F-150 ②③ — THE BAR IS A SLIDER AND THE NUMBER IS THE SWITCH.**
  ///
  /// > 「그래프? 바 쪽 지금 클릭하면 on off인데 **그런거 없애고, 공용슬라이더
  /// > 사용해서 통일화**. 버튼 on off는 **숫자 써있는곳 버튼으로만들어서 그거
  /// > 누르면 on off 전환**되도록」 (유저 2026-09-16)
  ///
  /// ↩️A tap on the COLUMN used to silence the peg and a second tap brought
  /// it back. That reading is gone: one place cannot be both a slider and a
  /// switch, and the user said which half goes where.
  testWidgets('a tap on the BAR changes nothing — it is a slider now', (
    tester,
  ) async {
    final read = await pumpPanel(tester);
    expect(read().beforePegs[0].opacity, 0.4, reason: 'the fixture premise');

    await tester.tap(peg('before', 1));
    await tester.pumpAndSettle();

    expect(
      read().beforePegs[0].opacity,
      0.4,
      reason: '유저: 「바 쪽 지금 클릭하면 on off인데 그런거 없애고」',
    );
  });

  testWidgets('and the NUMBER is the switch: it silences the peg, and the '
      'next press brings the same falloff back', (tester) async {
    final read = await pumpPanel(tester);

    // The number written at the floor of that column — 40 for the first
    // before-peg, which is the one the fixture ghosts.
    await tester.tap(
      pegSwitch('before', 1),
    );
    await tester.pumpAndSettle();
    expect(read().beforePegs[0].opacity, 0);

    await tester.tap(
      pegSwitch('before', 1),
    );
    await tester.pumpAndSettle();
    expect(
      read().beforePegs[0].opacity,
      0.4,
      reason: 'the second press brings the value it had, not a guess',
    );

    // A peg that never had a value comes back at the house default.
    await tester.tap(
      pegSwitch('after', 5),
    );
    await tester.pumpAndSettle();
    expect(read().afterPegs[4].opacity, greaterThan(0));
  });

  /// ⛔**AND THE STRIP'S DRAG IS THE SLIDER'S.** 🧪The behaviour is hard to
  /// tell apart in a test — both a plain `GestureDetector` and this pass a
  /// simple drag — and the difference only shows on a real panel that
  /// SCROLLS, where the ancestor takes a drag the strip waited a slop for.
  /// So it is read from the source, the way the app reads every other
  /// 「this press is the control's」 law.
  test('the strip rides the shared slider\'s gesture, not its own', () {
    final source = librarySource('lib/src/ui/panels/onion_skin_panel.dart');
    expect(
      source,
      contains('OwningVerticalDragGestureRecognizer'),
      reason:
          '유저: 「공용슬라이더 사용해서 통일화」 — the recogniser FieldSlider '
          'rides, which takes the arena on the first movement',
    );
    expect(
      source,
      contains('DragVerbClaim('),
      reason:
          '⛔the one claim the slider, the splitter and the swipe column '
          'share. ⚠️WITH THE PAREN: the doc comment above names it too, and '
          'a mutant that deleted the WIDGET survived a check that counted '
          'the word',
    );
    expect(
      source,
      isNot(contains('onVerticalDragStart:')),
      reason:
          '⛔the plain detector waits for the device slop, and the panel it '
          'sits in scrolls',
    );
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

  testWidgets('at the minimum dock width the strip still lays out — the '
      'percentages step aside, the index row stays', (tester) async {
    await pumpPanel(
      tester,
      // EditorPanelLayoutModel clamps a dock no narrower than this.
      width: 160,
    );

    expect(peg('before', OnionSkinSettings.maxPegs), findsOneWidget);
    expect(find.text('40'), findsNothing, reason: 'no room for two digits');
    expect(find.text('8'), findsNWidgets(2), reason: 'the index row remains');
    expect(tester.takeException(), isNull);
  });
}
