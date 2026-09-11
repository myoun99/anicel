import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/theme/text_on_ground.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/ground_ink_writing.dart';

void main() {
  const sliderKey = ValueKey<String>('field-slider-under-test');

  /// The TRACK, not the widget box. ⚠️A [FieldSlider] is a Row now — the bar
  /// plus the +/− stepper — so the widget's own rect no longer maps to the
  /// value. Position arithmetic has to address the bar, and this is how.
  Finder trackOf(Key key) => find.descendant(
    of: find.byKey(key),
    matching: find.byType(DragVerbClaim),
  );
  const trackWidth = 200.0;

  Widget harness({
    required ValueNotifier<double> value,
    double min = 0,
    double max = 1,
    FieldSliderScale scale = FieldSliderScale.linear,
    int? divisions,
    String? label = 'Test',
    String unit = '',
    double displayScale = 1,
    bool enabled = true,
    List<double>? changeEnds,
  }) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: trackWidth,
            child: ValueListenableBuilder<double>(
              valueListenable: value,
              builder: (context, v, _) => FieldSlider(
                key: sliderKey,
                value: v,
                min: min,
                max: max,
                scale: scale,
                divisions: divisions,
                label: label,
                unit: unit,
                displayScale: displayScale,
                onChanged: enabled ? (next) => value.value = next : null,
                onChangeEnd: changeEnds?.add,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('linear: tap sets value by absolute track position', (
    tester,
  ) async {
    final value = ValueNotifier<double>(0.2);
    await tester.pumpWidget(harness(value: value));
    await tester.tapAt(tester.getCenter(trackOf(sliderKey)));
    await tester.pump();
    expect(value.value, moreOrLessEquals(0.5, epsilon: 0.02));
  });

  testWidgets('linear: drag tracks absolute position and fires onChangeEnd', (
    tester,
  ) async {
    final value = ValueNotifier<double>(0.5);
    final ends = <double>[];
    await tester.pumpWidget(harness(value: value, changeEnds: ends));
    // ⚠️Relative to the MEASURED track: the bar shares its row with the
    // stepper now, so a fixed pixel drag is no longer a fixed fraction.
    final track = tester.getSize(trackOf(sliderKey)).width;
    await tester.drag(trackOf(sliderKey), const Offset(50, 0));
    await tester.pump();
    final expected = 0.5 + 50 / track;
    expect(value.value, moreOrLessEquals(expected, epsilon: 0.02));
    expect(ends, hasLength(1));
    expect(ends.single, moreOrLessEquals(expected, epsilon: 0.02));
  });

  testWidgets('exponential: track center lands on the geometric mean', (
    tester,
  ) async {
    final value = ValueNotifier<double>(1);
    await tester.pumpWidget(
      harness(
        value: value,
        min: 1,
        max: 100,
        scale: FieldSliderScale.exponential,
      ),
    );
    await tester.tapAt(tester.getCenter(trackOf(sliderKey)));
    await tester.pump();
    expect(value.value, moreOrLessEquals(10, epsilon: 0.5));
  });

  testWidgets('shift drag moves at one tenth speed', (tester) async {
    final value = ValueNotifier<double>(0.5);
    await tester.pumpWidget(harness(value: value));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.drag(trackOf(sliderKey), const Offset(100, 0));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(value.value, moreOrLessEquals(0.55, epsilon: 0.01));
  });

  testWidgets('scroll wheel steps by one percent of the track', (tester) async {
    final value = ValueNotifier<double>(0.5);
    await tester.pumpWidget(harness(value: value));
    final center = tester.getCenter(trackOf(sliderKey));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -40)));
    await tester.pump();
    expect(value.value, moreOrLessEquals(0.51, epsilon: 0.001));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
    await tester.pump();
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
    await tester.pump();
    expect(value.value, moreOrLessEquals(0.49, epsilon: 0.001));
  });

  testWidgets('divisions snap dragged values to whole steps', (tester) async {
    final value = ValueNotifier<double>(0);
    await tester.pumpWidget(
      harness(value: value, min: 0, max: 8, divisions: 8),
    );
    await tester.tapAt(
      tester.getTopLeft(trackOf(sliderKey)) + const Offset(55, 12),
    );
    await tester.pump();
    expect(value.value, 2);
  });

  testWidgets('R10 R5: a bar does not TYPE — a double tap is just two taps, '
      'and the second one sets the value like the first', (tester) async {
    final value = ValueNotifier<double>(0.2);
    await tester.pumpWidget(harness(value: value));
    final box = tester.getRect(trackOf(sliderKey));
    final quarter = Offset(box.left + box.width * 0.25, box.center.dy);

    await tester.tapAt(quarter);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(quarter);
    await tester.pump();

    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'the inline editor is gone; the bar answers taps immediately',
    );
    expect(value.value, moreOrLessEquals(0.25, epsilon: 0.02));
  });

  group('F-34: the bar chooses its own digit count, from its own step', () {
    // 유저 확정 2026-09-01 (선택 1): 「슬라이더가 스스로 정한다 — 위젯이
    // 자기 스텝을 보고 자릿수를 고른다」, and 2026-08-31 for why it must not
    // depend on the VALUE: 「소수점이 있는 슬라이더는 처음부터 소수점까지
    // 보여주도록. 없는 UI가 생겨나지 않게 하라는 원칙이 이 경우를 말함」.
    String written(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(of: find.byKey(sliderKey), matching: find.byType(Text)),
        )
        .last
        .data!;

    testWidgets('whole steps write NO decimal', (tester) async {
      final value = ValueNotifier<double>(128);
      addTearDown(value.dispose);
      await tester.pumpWidget(
        harness(value: value, min: 0, max: 255, divisions: 255),
      );
      expect(written(tester), '128');
    });

    testWidgets('a whole-per-cent bar is whole THROUGH its display scale — '
        'a hundred divisions of a 0..1 model', (tester) async {
      final value = ValueNotifier<double>(0.5);
      addTearDown(value.dispose);
      await tester.pumpWidget(
        harness(
          value: value,
          min: 0,
          max: 1,
          divisions: 100,
          displayScale: 100,
          unit: '%',
        ),
      );
      expect(written(tester), '50%');
    });

    testWidgets('a CONTINUOUS bar keeps its decimal at a whole value — this '
        'is the digit that used to appear and disappear', (tester) async {
      final value = ValueNotifier<double>(24);
      addTearDown(value.dispose);
      await tester.pumpWidget(
        harness(value: value, min: 1, max: 100, unit: ' px'),
      );
      expect(written(tester), '24.0 px');

      // …and the same bar mid-drag. The COUNT is what may not change.
      await tester.drag(trackOf(sliderKey), const Offset(7, 0));
      await tester.pump();
      expect(written(tester), matches(r'^\d+\.\d px$'));
    });

    testWidgets('an EXPONENTIAL sweep always can, so it always writes one', (
      tester,
    ) async {
      final value = ValueNotifier<double>(10);
      addTearDown(value.dispose);
      await tester.pumpWidget(
        harness(
          value: value,
          min: 1,
          max: 100,
          scale: FieldSliderScale.exponential,
          unit: ' px',
        ),
      );
      expect(written(tester), '10.0 px');
    });

    testWidgets('a step that is fractional in DISPLAY units keeps the '
        'decimal — 255 stops over 100% is 0.4% apart', (tester) async {
      final value = ValueNotifier<double>(100);
      addTearDown(value.dispose);
      await tester.pumpWidget(
        harness(
          value: value,
          min: 0,
          max: 255,
          divisions: 255,
          displayScale: 100 / 255,
          unit: '%',
        ),
      );
      expect(written(tester), '39.2%');
    });

    testWidgets('🚨the MICRO opacity bar writes the number alone', (
      tester,
    ) async {
      // 유저 2026-09-10: 「타임라인 레이어영역에 있는 슬라이더 미니버전.
      // 미니버전은 텍스트에 % 표기 삭제. 그냥 안보이게」.
      final value = ValueNotifier<double>(0.5);
      addTearDown(value.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: trackWidth,
                child: FieldSlider.opacity(
                  key: sliderKey,
                  value: value.value,
                  height: 18,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('50'), findsOneWidget);
      expect(find.text('50%'), findsNothing);
    });

    testWidgets('⛔and a bar whose label sits BESIDE it keeps its unit — '
        '`label == null` is both kinds, so the rule lives in the opacity '
        'variant and not in the writing', (tester) async {
      // The export bitrate, the autosave minutes and the stage alpha are all
      // label-less bars in roomy rows. `12` with no ` Mb` is not the ask.
      final value = ValueNotifier<double>(12);
      addTearDown(value.dispose);
      await tester.pumpWidget(
        harness(
          value: value,
          label: null,
          min: 0,
          max: 50,
          divisions: 50,
          unit: ' Mb',
        ),
      );
      expect(find.text('12 Mb'), findsOneWidget);
    });
  });

  group('the writing on the bar', () {
    Finder valueTextOf(Key key) => find.descendant(
      of: find.byKey(key),
      matching: find.byType(Text),
    );

    testWidgets('micro variant (no label) centers the value text', (
      tester,
    ) async {
      final value = ValueNotifier<double>(1);
      addTearDown(value.dispose);
      await tester.pumpWidget(
        harness(
          value: value,
          label: null,
          min: 0,
          max: 1,
          divisions: 100,
          displayScale: 100,
        ),
      );
      final text = tester.getCenter(find.text('100'));
      final bar = tester.getCenter(trackOf(sliderKey));
      expect((text.dx - bar.dx).abs(), lessThan(1));
    });

    testWidgets('🚨the NUMBER is set solid — a trailing letter-space is half '
        'a pixel of left bias, and 유저 saw it', (tester) async {
      // 「해당 불투명도 슬라이더의 텍스트가 제대로 중앙정렬이 아닌거같음.
      // 두자리수가 미묘하게 왼쪽에 치우쳐있음」 (2026-09-10). `labelSmall`
      // carries letterSpacing 0.5 and Flutter lays it after the LAST glyph
      // too, so the centred box is wider than the glyphs in it.
      final value = ValueNotifier<double>(0.5);
      addTearDown(value.dispose);
      await tester.pumpWidget(
        harness(
          value: value,
          label: null,
          min: 0,
          max: 1,
          divisions: 100,
          displayScale: 100,
        ),
      );
      final style = tester.widget<Text>(valueTextOf(sliderKey)).style!;
      expect(style.letterSpacing, 0);
      // ⚠️The control: the theme really does carry a spacing to remove.
      expect(
        Typography.material2021().white.labelSmall?.letterSpacing,
        isNot(0),
      );
    });

    testWidgets('🚨H38 again: the ink follows the ground — the fill\'s ink '
        'over the fill, the track\'s over the empty track', (tester) async {
      // 유저 2026-09-11: 「공용 슬라이더 텍스트말인데, 검정색으로 하니 뒤가
      // 비어있으면 안보인다. 그러니까 그냥 저번에 한대로 뒤 색에 따라
      // 하양/검정 바꾸는거 있잖아. 그거대로 하자」.
      final value = ValueNotifier<double>(0.5);
      addTearDown(value.dispose);
      await tester.pumpWidget(harness(value: value));

      final writing = tester.widget<GroundInkWriting>(
        find.descendant(
          of: find.byKey(sliderKey),
          matching: find.byType(GroundInkWriting),
        ),
      );
      expect(writing.runs, [
        (end: 0.5, ink: textOnColor(AppColors.accent)),
        (end: 1.0, ink: textOnColor(AppColors.surface)),
      ]);
      expect(
        {for (final run in writing.runs) run.ink},
        hasLength(2),
        reason: 'premise: the fill and the track really take different inks',
      );
      for (final text in tester.widgetList<Text>(valueTextOf(sliderKey))) {
        expect(
          text.style?.foreground?.shader,
          isNotNull,
          reason: 'label and value alike ride the one writing',
        );
      }
    });

    testWidgets('🚨an EMPTY bar writes with the track\'s ink — 「뒤가 '
        '비어있으면 안보인다」', (tester) async {
      final value = ValueNotifier<double>(0);
      addTearDown(value.dispose);
      await tester.pumpWidget(harness(value: value));

      for (final text in tester.widgetList<Text>(valueTextOf(sliderKey))) {
        expect(text.style?.color, textOnColor(AppColors.surface));
      }
      expect(
        textOnColor(AppColors.surface),
        isNot(const Color(0xFF000000)),
        reason: 'the black H38 fixed was the ink that vanished here',
      );
    });

    testWidgets('⛔no ShaderMask — the ink is the text\'s own paint, never an '
        'offscreen layer per bar', (tester) async {
      final value = ValueNotifier<double>(0.5);
      addTearDown(value.dispose);
      await tester.pumpWidget(harness(value: value));

      expect(
        find.descendant(
          of: find.byKey(sliderKey),
          matching: find.byType(ShaderMask),
        ),
        findsNothing,
      );
    });

    testWidgets('a STOOD-UP bar\'s writing runs DOWN the bar while its fill '
        'grows UP it — the fill\'s ink lands at the writing\'s far end', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: trackWidth,
                child: FieldSlider(
                  key: sliderKey,
                  axis: Axis.vertical,
                  value: 0.25,
                  min: 0,
                  max: 1,
                  height: 18,
                  displayScale: 100,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester
            .widget<GroundInkWriting>(
              find.descendant(
                of: find.byKey(sliderKey),
                matching: find.byType(GroundInkWriting),
              ),
            )
            .runs,
        [
          (end: 0.75, ink: textOnColor(AppColors.surface)),
          (end: 1.0, ink: textOnColor(AppColors.accent)),
        ],
        reason: 'the bottom quarter is filled, and the turned writing ends '
            'at the bottom',
      );
    });

    testWidgets('🚨H40: the +/− pair is kept while nothing it shows changes — '
        'a new value, or a drag frame, does not rebuild it', (tester) async {
      final value = ValueNotifier<double>(0.3);
      addTearDown(value.dispose);
      await tester.pumpWidget(harness(value: value));
      const upKey = ValueKey<String>('field-slider-step-up');
      final up = tester.widget(find.byKey(upKey));

      value.value = 0.7;
      await tester.pump();

      expect(identical(tester.widget(find.byKey(upKey)), up), isTrue);
    });

    testWidgets('and rebuilt when the bar goes dead — its buttons dim with it',
        (tester) async {
      final value = ValueNotifier<double>(0.3);
      addTearDown(value.dispose);
      await tester.pumpWidget(harness(value: value));
      const upKey = ValueKey<String>('field-slider-step-up');
      final up = tester.widget(find.byKey(upKey));

      await tester.pumpWidget(harness(value: value, enabled: false));

      expect(identical(tester.widget(find.byKey(upKey)), up), isFalse);
    });
  });

  testWidgets('disabled slider ignores input and dims', (tester) async {
    final value = ValueNotifier<double>(0.2);
    await tester.pumpWidget(harness(value: value, enabled: false));
    // ⚠️A disabled bar has no drag claim to address, so the dimmed bar
    // itself is the target. The +/− pair is still beside it, dimmed and
    // inert — the row must not change width when the control comes alive.
    final dimmed = find.descendant(
      of: find.byKey(sliderKey),
      matching: find.byType(Opacity),
    );
    await tester.tapAt(tester.getCenter(dimmed));
    await tester.pump();
    expect(value.value, 0.2);
    expect(tester.widget<Opacity>(dimmed).opacity, 0.4);
  });

  // 🚨유저 확정 2026-08-14, ⛔재론 금지: 「**슬라이더위에서 조작하기 시작하면
  // 슬라이더조작하는거고 그 외가 스크롤인거야**」 — and about the very case the
  // old behaviour protected, 「태블릿에서 슬라이더 위에 손가락을 얹고 패널을
  // 스크롤하는게 실제로 쓰겟냐? **절대로안하니까 다신하지마**」.
  //
  // This test used to assert the opposite — that a vertical drag over the bar
  // scrolled the list and rolled the value back. That was never a decision.
  // It was an assumption about how people hold tablets, written down as if it
  // were one, and the bar grew a whole workaround to serve it.
  testWidgets(
    'a drag that STARTS on the bar never reaches the list, whatever direction',
    (tester) async {
      final value = ValueNotifier<double>(0.2);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ListView(
              controller: controller,
              children: [
                const SizedBox(height: 100),
                ValueListenableBuilder<double>(
                  valueListenable: value,
                  builder: (context, v, _) => FieldSlider(
                    key: sliderKey,
                    value: v,
                    min: 0,
                    max: 1,
                    label: 'Test',
                    unit: ' px',
                    onChanged: (next) => value.value = next,
                  ),
                ),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      );
      await tester.drag(find.byKey(sliderKey), const Offset(0, -80));
      await tester.pump();
      expect(
        controller.offset,
        0,
        reason: 'the press landed on the bar, so the list gets nothing',
      );
      // And the press STANDS. `drag` presses the centre, and answering the
      // press is what this bar does (유저: 「상단띠 브러시사이즈 변경처럼
      // 대충눌러도 바뀌도록하고싶음」) — so the value is the centre's. The
      // straight-down travel adds nothing, because down is across this bar's
      // axis; what matters is that it is not TAKEN AWAY afterwards, which is
      // exactly what the retired rollback did.
      expect(
        value.value,
        moreOrLessEquals(0.5, epsilon: 0.02),
        reason: 'the press set it and nothing rolled it back',
      );
    },
  );

  group('R6 #1: the bar keeps what moved along its OWN axis', () {
    // 유저: "상단띠 브러시사이즈 변경처럼 대충눌러도 바뀌도록하고싶음."
    //
    // Every case here is inside a ListView, because that is the ONLY thing
    // that ever made the bar behave differently from the top strip.
    Widget scrolled(
      ValueNotifier<double> value,
      List<double> commits, {
      ScrollController? controller,
    }) => MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ListView(
              controller: controller,
              children: [
                const SizedBox(height: 100),
                ValueListenableBuilder<double>(
                  valueListenable: value,
                  builder: (context, v, _) => FieldSlider(
                    key: sliderKey,
                    value: v,
                    min: 0,
                    max: 1,
                    label: 'Test',
                    unit: ' px',
                    onChanged: (next) => value.value = next,
                    onChangeEnd: commits.add,
                  ),
                ),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        );

    testWidgets('a tap that wobbles ALONG the bar keeps the value — the old '
        '6px tap slop called this a scroll and rolled it back', (tester) async {
      final value = ValueNotifier<double>(0.2);
      addTearDown(value.dispose);
      final commits = <double>[];
      await tester.pumpWidget(scrolled(value, commits));

      final rect = tester.getRect(trackOf(sliderKey));
      final gesture = await tester.startGesture(
        Offset(rect.left + rect.width * 0.75, rect.center.dy),
        kind: PointerDeviceKind.stylus,
      );
      // Well past the retired 6px, nowhere near the 18px a scrollable needs:
      // nothing took this gesture, so nothing may roll it back.
      await gesture.moveBy(const Offset(10, 4));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(value.value, moreOrLessEquals(0.75, epsilon: 0.02));
      expect(commits, isNotEmpty);
      expect(commits.last, moreOrLessEquals(0.75, epsilon: 0.02));
    });

    testWidgets('a tap that wobbles ACROSS the bar — but less than the scroll '
        'threshold — also keeps it', (tester) async {
      final value = ValueNotifier<double>(0.2);
      addTearDown(value.dispose);
      final commits = <double>[];
      await tester.pumpWidget(scrolled(value, commits));

      final rect = tester.getRect(trackOf(sliderKey));
      final gesture = await tester.startGesture(
        Offset(rect.left + rect.width * 0.4, rect.center.dy),
        kind: PointerDeviceKind.stylus,
      );
      await gesture.moveBy(const Offset(1, 9));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        value.value,
        moreOrLessEquals(0.4, epsilon: 0.02),
        reason: 'a scrollable that never claimed the gesture cannot undo it',
      );
    });

    testWidgets('a sideways lead-in then a long vertical pull still never '
        'reaches the list', (tester) async {
      final value = ValueNotifier<double>(0.2);
      addTearDown(value.dispose);
      final commits = <double>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        scrolled(value, commits, controller: controller),
      );

      final rect = tester.getRect(trackOf(sliderKey));
      final gesture = await tester.startGesture(
        Offset(rect.left + rect.width * 0.75, rect.center.dy),
        kind: PointerDeviceKind.stylus,
      );
      await gesture.moveBy(const Offset(10, 0));
      // 60px of pure vertical after the lead-in — far past any scroll slop.
      // Under the retired law this was the case that handed the gesture over
      // and rolled the value back; under this one the first movement already
      // settled ownership and the direction afterwards is not a vote.
      await gesture.moveBy(const Offset(0, -25));
      await gesture.moveBy(const Offset(0, -35));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        controller.offset,
        0,
        reason: 'the bar took the gesture on the first movement and kept it',
      );
      expect(
        value.value,
        greaterThan(0.2),
        reason: 'the sideways lead-in is a real edit and it stands',
      );
      expect(commits, isNotEmpty, reason: 'and it commits like any drag');
    });

    testWidgets('a STOOD-UP bar keeps its gesture from a horizontal list the '
        'same way', (tester) async {
      final value = ValueNotifier<double>(0.5);
      addTearDown(value.dispose);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ListView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              children: [
                const SizedBox(width: 100),
                SizedBox(
                  height: trackWidth,
                  child: ValueListenableBuilder<double>(
                    valueListenable: value,
                    builder: (context, v, _) => FieldSlider(
                      key: sliderKey,
                      axis: Axis.vertical,
                      value: v,
                      min: 0,
                      max: 1,
                      height: 18,
                      displayScale: 100,
                      onChanged: (next) => value.value = next,
                    ),
                  ),
                ),
                const SizedBox(width: 1200),
              ],
            ),
          ),
        ),
      );

      // 🚨Started OFF-CENTRE on purpose. Pressed at the middle, the
      // pointer-down value and the resting value are the same number, so
      // the assertion below could not tell a bar that answered the press
      // from one that did nothing at all.
      final rect = tester.getRect(trackOf(sliderKey));
      await tester.dragFrom(
        Offset(rect.center.dx, rect.bottom - rect.height / 4),
        const Offset(-80, 0),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pumpAndSettle();

      expect(
        controller.offset,
        0,
        reason: 'the press landed on the bar, so the row gets nothing',
      );
      // Sideways is ACROSS a stood-up bar, so the value follows the press
      // and not the travel: the bar answered the down at a quarter up from
      // the bottom and holds it. The point is that it holds it rather than
      // handing the gesture to the row and rolling back.
      expect(
        value.value,
        moreOrLessEquals(0.25, epsilon: 0.02),
        reason: 'the bar answered its own press and kept the pointer',
      );
    });
  });

  testWidgets('a TAP inside that same scrollable sets the value and keeps it', (
    tester,
  ) async {
    // The other half of the rule above, and where three bugs lived: the
    // drag recognizer is rejected in BOTH cases and cannot tell them
    // apart, so the bar used to roll a tap back like a scroll. A pen tap
    // in the tool settings did nothing while a MOUSE tap worked (a
    // desktop Scrollable only contests touch and stylus), and the
    // layer-opacity bar failed for both. 유저: "싹 통일하고싶어".
    final value = ValueNotifier<double>(0.2);
    final commits = <double>[];
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: [
              const SizedBox(height: 100),
              ValueListenableBuilder<double>(
                valueListenable: value,
                builder: (context, v, _) => FieldSlider(
                  key: sliderKey,
                  value: v,
                  min: 0,
                  max: 1,
                  label: 'Test',
                  unit: ' px',
                  onChanged: (next) => value.value = next,
                  onChangeEnd: commits.add,
                ),
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    );

    final rect = tester.getRect(trackOf(sliderKey));
    await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pumpAndSettle();

    expect(value.value, moreOrLessEquals(0.75, epsilon: 0.02));
    expect(
      commits.last,
      moreOrLessEquals(0.75, epsilon: 0.02),
      reason:
          'commit-on-release hosts must be told too, or the live '
          'preview is all the tap ever produces',
    );
    expect(controller.offset, 0, reason: 'a tap is not a scroll');
  });

  testWidgets('a tap sets the value from a STYLUS too — the device must not '
      'decide whether a tap counts', (tester) async {
    final value = ValueNotifier<double>(0.2);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: [
              const SizedBox(height: 100),
              ValueListenableBuilder<double>(
                valueListenable: value,
                builder: (context, v, _) => FieldSlider(
                  key: sliderKey,
                  value: v,
                  min: 0,
                  max: 1,
                  label: 'Test',
                  unit: ' px',
                  onChanged: (next) => value.value = next,
                ),
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    );

    final rect = tester.getRect(trackOf(sliderKey));
    final at = Offset(rect.left + rect.width * 0.4, rect.center.dy);
    final gesture = await tester.startGesture(
      at,
      kind: PointerDeviceKind.stylus,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(value.value, moreOrLessEquals(0.4, epsilon: 0.02));
  });

  group('stood up (the x-sheet rail)', () {
    Widget verticalHarness(ValueNotifier<double> value) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            height: trackWidth,
            child: ValueListenableBuilder<double>(
              valueListenable: value,
              // The x-sheet's own bar: an opacity fader stood up.
              builder: (context, v, _) => FieldSlider.opacity(
                key: sliderKey,
                axis: Axis.vertical,
                value: v,
                height: 18,
                onChanged: (next) => value.value = next,
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('a tap sets the value from the BOTTOM — a fader fills up', (
      tester,
    ) async {
      final value = ValueNotifier<double>(0.2);
      addTearDown(value.dispose);
      await tester.pumpWidget(verticalHarness(value));

      final rect = tester.getRect(trackOf(sliderKey));
      // A quarter up from the bottom.
      await tester.tapAt(Offset(rect.center.dx, rect.bottom - rect.height / 4));
      await tester.pump();
      expect(value.value, moreOrLessEquals(0.25, epsilon: 0.02));
    });

    testWidgets('an UP drag raises the value', (tester) async {
      final value = ValueNotifier<double>(0.5);
      addTearDown(value.dispose);
      await tester.pumpWidget(verticalHarness(value));

      final rect = tester.getRect(trackOf(sliderKey));
      await tester.tapAt(rect.center);
      await tester.pump();
      expect(value.value, moreOrLessEquals(0.5, epsilon: 0.02));

      // A RotatedBox could not do this: the horizontal recognizer judges by
      // the pointer's global delta direction, so a turned slider would
      // never receive an on-screen vertical drag at all.
      await tester.drag(find.byKey(sliderKey), const Offset(0, -50));
      await tester.pump();
      expect(value.value, greaterThan(0.6));
    });

    testWidgets('🚨the readout LIES DOWN — 세로쓰기 세로표기', (tester) async {
      // 유저 2026-09-10: 「x시트의 불투명도바는 세로쓰기 세로표기로 바꾸자」
      // — the reading they named on 2026-08-24 (F-27, 「se블록의 이름이
      // 세로쓰기세로표기 인거같은데, 가로쓰기 세로표기가 되도록」), where
      // the before state was the glyphs LYING DOWN along the column.
      final value = ValueNotifier<double>(1);
      addTearDown(value.dispose);
      await tester.pumpWidget(verticalHarness(value));

      expect(
        find.descendant(
          of: find.byKey(sliderKey),
          matching: find.byType(RotatedBox),
        ),
        findsOneWidget,
        reason: 'one quarter turn, and the whole readout takes it',
      );
      expect(
        tester
            .widget<RotatedBox>(
              find.descendant(
                of: find.byKey(sliderKey),
                matching: find.byType(RotatedBox),
              ),
            )
            .quarterTurns,
        1,
        reason: 'clockwise — the same way the vertical table turns a glyph',
      );
      // ⛔NOT the vertical-writing table any more: it set `100%` as
      // three-digit 縦中横, a HORIZONTAL number inside a vertical column,
      // which is the 가로쓰기 the user is asking away from.
      expect(find.byType(VerticalWritingText), findsNothing);
      // And it is still the MICRO variant, so no per cent (2026-09-10).
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('the turned readout does not shorten the bar — the SLOT '
        'gives the track its length', (tester) async {
      final value = ValueNotifier<double>(1);
      addTearDown(value.dispose);
      await tester.pumpWidget(verticalHarness(value));

      // The x-sheet gives this column 42px and the drag math measures the
      // slot (`_trackExtent = constraints.maxHeight`), so a readout that
      // sized the bar would put the fill and the finger on two scales.
      expect(tester.getSize(trackOf(sliderKey)).height, trackWidth);
    });
  });
}
