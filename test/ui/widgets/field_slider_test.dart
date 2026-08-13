import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/text/vertical_writing.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

void main() {
  const sliderKey = ValueKey<String>('field-slider-under-test');
  const trackWidth = 200.0;

  Widget harness({
    required ValueNotifier<double> value,
    double min = 0,
    double max = 1,
    FieldSliderScale scale = FieldSliderScale.linear,
    int? divisions,
    String? label = 'Test',
    bool enabled = true,
    List<double>? changeEnds,
    String Function(double)? format,
  }) {
    final fmt = format ?? (v) => v.toStringAsFixed(2);
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
                valueText: fmt(v),
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
    await tester.tapAt(tester.getCenter(find.byKey(sliderKey)));
    await tester.pump();
    expect(value.value, moreOrLessEquals(0.5, epsilon: 0.02));
  });

  testWidgets('linear: drag tracks absolute position and fires onChangeEnd', (
    tester,
  ) async {
    final value = ValueNotifier<double>(0.5);
    final ends = <double>[];
    await tester.pumpWidget(harness(value: value, changeEnds: ends));
    await tester.drag(find.byKey(sliderKey), const Offset(50, 0));
    await tester.pump();
    expect(value.value, moreOrLessEquals(0.75, epsilon: 0.02));
    expect(ends, hasLength(1));
    expect(ends.single, moreOrLessEquals(0.75, epsilon: 0.02));
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
    await tester.tapAt(tester.getCenter(find.byKey(sliderKey)));
    await tester.pump();
    expect(value.value, moreOrLessEquals(10, epsilon: 0.5));
  });

  testWidgets('shift drag moves at one tenth speed', (tester) async {
    final value = ValueNotifier<double>(0.5);
    await tester.pumpWidget(harness(value: value));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.drag(find.byKey(sliderKey), const Offset(100, 0));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(value.value, moreOrLessEquals(0.55, epsilon: 0.01));
  });

  testWidgets('scroll wheel steps by one percent of the track', (tester) async {
    final value = ValueNotifier<double>(0.5);
    await tester.pumpWidget(harness(value: value));
    final center = tester.getCenter(find.byKey(sliderKey));
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
      tester.getTopLeft(find.byKey(sliderKey)) + const Offset(55, 12),
    );
    await tester.pump();
    expect(value.value, 2);
  });

  testWidgets('R10 R5: a bar does not TYPE — a double tap is just two taps, '
      'and the second one sets the value like the first', (tester) async {
    final value = ValueNotifier<double>(0.2);
    await tester.pumpWidget(harness(value: value));
    final box = tester.getRect(find.byKey(sliderKey));
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

  testWidgets('micro variant (no label) centers the value text', (
    tester,
  ) async {
    final value = ValueNotifier<double>(1);
    await tester.pumpWidget(
      harness(value: value, label: null, format: (v) => '100%'),
    );
    final text = tester.getCenter(find.text('100%'));
    final bar = tester.getCenter(find.byKey(sliderKey));
    expect((text.dx - bar.dx).abs(), lessThan(1));
  });

  testWidgets('disabled slider ignores input and dims', (tester) async {
    final value = ValueNotifier<double>(0.2);
    await tester.pumpWidget(harness(value: value, enabled: false));
    await tester.tapAt(tester.getCenter(find.byKey(sliderKey)));
    await tester.pump();
    expect(value.value, 0.2);
    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(sliderKey),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, 0.4);
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
                    valueText: v.toStringAsFixed(2),
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
                    valueText: v.toStringAsFixed(2),
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

      final rect = tester.getRect(find.byKey(sliderKey));
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

      final rect = tester.getRect(find.byKey(sliderKey));
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

      final rect = tester.getRect(find.byKey(sliderKey));
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
                      valueText: '${(v * 100).round()}%',
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
      final rect = tester.getRect(find.byKey(sliderKey));
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
                  valueText: v.toStringAsFixed(2),
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

    final rect = tester.getRect(find.byKey(sliderKey));
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
                  valueText: v.toStringAsFixed(2),
                  onChanged: (next) => value.value = next,
                ),
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byKey(sliderKey));
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
              builder: (context, v, _) => FieldSlider(
                key: sliderKey,
                axis: Axis.vertical,
                value: v,
                min: 0,
                max: 1,
                height: 18,
                valueText: '${(v * 100).round()}%',
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

      final rect = tester.getRect(find.byKey(sliderKey));
      // A quarter up from the bottom.
      await tester.tapAt(Offset(rect.center.dx, rect.bottom - rect.height / 4));
      await tester.pump();
      expect(value.value, moreOrLessEquals(0.25, epsilon: 0.02));
    });

    testWidgets('an UP drag raises the value', (tester) async {
      final value = ValueNotifier<double>(0.5);
      addTearDown(value.dispose);
      await tester.pumpWidget(verticalHarness(value));

      final rect = tester.getRect(find.byKey(sliderKey));
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

    testWidgets('the readout stands up, and 100% costs two cells', (
      tester,
    ) async {
      final value = ValueNotifier<double>(1);
      addTearDown(value.dispose);
      await tester.pumpWidget(verticalHarness(value));

      final written = tester.widget<VerticalWritingText>(
        find.byType(VerticalWritingText),
      );
      expect(written.text, '100%');
      // Three-digit 縦中横: `100` in one cell, `%` in the next.
      expect(
        verticalTextCells(
          written.text,
          tateChuYokoDigits: written.tateChuYokoDigits,
        ),
        hasLength(2),
      );
    });
  });
}
