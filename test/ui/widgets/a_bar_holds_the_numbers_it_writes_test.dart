// 🗣️F-488 (유저 2026-10-27): 「브러시 크기 사이즈 슬라이더, 0.1대에서
// 슬라이더 움직이는데 0.1인채로 유지되는데 설마 0.1 밑의 소수점자리도
// 존재하는건가? 왜 슬라이더가 움직이는거지? 만약 그런거라면 소수점한자리까지만
// 존재하도록하고 아니면 조정가능한 값만 조정되도록. 슬라이더를 전부 그렇게.」
//
// A BAR HOLDS THE NUMBERS IT WRITES: whatever it hands over — by drag, tap,
// step or typing — is a number it writes, and its fill moves when its
// number does. The canvas's size drag holds the size bar's numbers too
// (`a_snapped_size_drag_lands_on_the_rack_test`).
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

import '../../helpers/number_pad_keyboard.dart';

/// [value] as a number with [digits] digits after the point.
double written(double value, int digits) {
  final per = math.pow(10, digits);
  return (value * per).round() / per;
}

void main() {
  final track = find.byType(FieldSliderTrack);

  /// A bar the test holds the value of — handed back every change, as a
  /// host does — and every value it handed over.
  Future<List<double>> pumpBar(
    WidgetTester tester, {
    required double value,
    required double min,
    required double max,
    FieldSliderScale scale = FieldSliderScale.linear,
    double displayScale = 1,
  }) async {
    final handed = <double>[];
    final shown = ValueNotifier(value);
    addTearDown(shown.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 42,
              child: ValueListenableBuilder<double>(
                valueListenable: shown,
                builder: (context, now, _) => FieldSlider(
                  label: 'Size',
                  value: now,
                  min: min,
                  max: max,
                  scale: scale,
                  displayScale: displayScale,
                  onChanged: (next) {
                    handed.add(next);
                    shown.value = next;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return handed;
  }

  testWidgets('up an exponential bar from its floor, a drag hands over only '
      'the numbers the bar writes — 0.1 until it writes 0.2 — and the fill '
      'stands still until the number moves', (tester) async {
    final handed = await pumpBar(
      tester,
      value: 0.1,
      min: 0.1,
      max: 2000,
      scale: FieldSliderScale.exponential,
    );
    CustomPainter fill() => tester.widget<FieldSliderTrack>(track).fill;
    final start = tester.getRect(track).centerLeft + const Offset(0.5, 0);
    final gesture = await tester.startGesture(start);
    await tester.pump();
    final atFloor = fill();
    for (var step = 1; step <= 40; step++) {
      await gesture.moveTo(start + Offset(step.toDouble(), 0));
      await tester.pump();
      if (handed.last == 0.1) {
        expect(
          fill().shouldRepaint(atFloor),
          isFalse,
          reason: '${step}px: the number still says 0.1',
        );
      }
    }
    await gesture.up();
    await tester.pump();

    for (final value in handed) {
      expect(value, written(value, 1), reason: '$value is a written number');
    }
    expect(handed.first, 0.1);
    expect(handed.where((value) => value > 0.1).first, 0.2);
    expect(handed.last, greaterThan(0.2), reason: '⛔premise: it moved on');
  });

  testWidgets('a bar that writes per cent to a tenth hands over tenths of a '
      'per cent', (tester) async {
    final handed = await pumpBar(
      tester,
      value: 0.5,
      min: 0,
      max: 1,
      displayScale: 100,
    );
    final start = tester.getRect(track).center;
    final gesture = await tester.startGesture(start);
    for (var step = 1; step <= 12; step++) {
      await gesture.moveTo(start + Offset(step * 0.37, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(handed.toSet().length, greaterThan(1), reason: '⛔premise: moved');
    for (final value in handed) {
      expect(value, written(value, 3), reason: '$value is a written number');
    }
  });

  testWidgets('a step that would write the number the bar already writes '
      'moves its last digit — + and the wheel from 0.1 to 0.2, − back',
      (tester) async {
    final handed = await pumpBar(
      tester,
      value: 0.1,
      min: 0.1,
      max: 2000,
      scale: FieldSliderScale.exponential,
    );
    await tester.tap(find.byKey(const ValueKey<String>('field-slider-step-up')));
    await tester.pump();
    expect(handed.last, 0.2);

    await tester.tap(
      find.byKey(const ValueKey<String>('field-slider-step-down')),
    );
    await tester.pump();
    expect(handed.last, 0.1);

    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(wheel.hover(tester.getCenter(track)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -20)));
    await tester.pump();
    expect(handed.last, 0.2);
  });

  testWidgets('a typed number lands on the numbers the bar writes', (
    tester,
  ) async {
    final handed = await pumpBar(
      tester,
      value: 10,
      min: 0.1,
      max: 2000,
      scale: FieldSliderScale.exponential,
    );
    await tester.tap(find.byKey(const ValueKey<String>('field-slider-type')));
    await tester.pumpAndSettle();
    await openThePadsKeyboard(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('field-slider-type-input')),
      '12.34',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(handed.last, 12.3);
  });
}
