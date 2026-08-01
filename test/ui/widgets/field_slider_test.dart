import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets(
    'vertical scroll over the bar scrolls the list and rolls the value back',
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
      expect(controller.offset, greaterThan(0));
      expect(value.value, moreOrLessEquals(0.2, epsilon: 0.001));
    },
  );
}
