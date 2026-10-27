import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';

/// 🗣️I-135 (유저 2026-10-27): the brush pill's bars — 「슬라이더 막대엔 텍스트
/// 없애고, 연필버튼도 여기선 대체되니 없애고 … 막대 옆에 <20.0 … 이 위젯은
/// 버튼이라 클릭가능. 클릭하면 연필버튼이랑 똑같은 동작으로 텍스트 직접
/// 편집」. The link between a bar and its bubble ([FieldSliderBubble]) as any
/// host holds it; the pill's own pins are in
/// `the_brush_pill_writes_its_numbers_in_bubbles_test`.
void main() {
  FieldSlider barWith(FieldSliderBubble bubble) => FieldSlider(
    key: const ValueKey<String>('bar'),
    label: 'Size',
    nameInside: false,
    value: 10,
    min: 1,
    max: 100,
    axis: Axis.vertical,
    height: 20,
    bubble: bubble,
    onChanged: (_) {},
  );

  /// A bar led by [leads] — none where it is null — beside the bubble that
  /// [follows].
  Future<void> pumpBarAndBubble(
    WidgetTester tester, {
    required FieldSliderBubble? leads,
    required FieldSliderBubble follows,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                height: 160,
                child: leads == null ? null : barWith(leads),
              ),
              SizedBox(
                width: 80,
                height: 200,
                child: Stack(
                  children: [
                    FieldSliderValueBubble(
                      keyValue: 'bubble',
                      bar: barWith(follows),
                      width: 40,
                      reach: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  final typing = find.byKey(const ValueKey<String>('field-slider-type-input'));
  final bubble = find.byKey(const ValueKey<String>('bubble'));

  testWidgets('a bar handed another bubble answers that one\'s press', (
    tester,
  ) async {
    final first = FieldSliderBubble();
    final second = FieldSliderBubble();
    await pumpBarAndBubble(tester, leads: first, follows: first);
    await tester.tap(bubble);
    await tester.pumpAndSettle();
    expect(typing, findsOneWidget, reason: '⛔premise: its first one types');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(typing, findsNothing, reason: '⛔premise: the field closed');

    await pumpBarAndBubble(tester, leads: second, follows: second);
    await tester.tap(bubble);
    await tester.pumpAndSettle();
    expect(typing, findsOneWidget);
  });

  testWidgets('a bubble takes the keyboard\'s press as its pencil did: '
      'Enter on it types into its bar', (tester) async {
    final link = FieldSliderBubble();
    await pumpBarAndBubble(tester, leads: link, follows: link);
    final plate = find.descendant(
      of: bubble,
      matching: find.byType(RailPlateButton),
    );
    Focus.of(tester.element(plate)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(typing, findsOneWidget);
  });

  testWidgets('a bubble its bar has left is dead: its press — even the '
      'keyboard\'s, which reaches a bubble no bar leads — types into '
      'nothing, and nothing breaks', (tester) async {
    final link = FieldSliderBubble();
    await pumpBarAndBubble(tester, leads: link, follows: link);
    await pumpBarAndBubble(tester, leads: null, follows: link);
    expect(find.byKey(const ValueKey<String>('bar')), findsNothing);

    Focus.of(tester.element(find.byType(RailPlateButton))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(typing, findsNothing);
  });

  testWidgets('a bubble is as wide as the widest word its bar can say, '
      'whatever the bar says now — 「그냥 고정크기로하자」', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (built) {
            context = built;
            return const SizedBox();
          },
        ),
      ),
    );
    double widthAt(double value) => FieldSliderValueBubble.widthIn(context, [
      FieldSlider(
        label: 'Size',
        nameInside: false,
        value: value,
        min: 1,
        max: 100,
        axis: Axis.vertical,
        height: 20,
        bubble: FieldSliderBubble(),
        onChanged: (_) {},
      ),
    ]);

    final widest = widthAt(100);
    expect(widthAt(10), widest, reason: '「10.0」 says less than 「100.0」');
    expect(widthAt(1), widest);
  });

  testWidgets('a bubble bar asks no room of its track — its number is in '
      'its bubble — and the run its number would stand in is the column '
      'an upright bar measures', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (built) {
            context = built;
            return const SizedBox();
          },
        ),
      ),
    );
    final bubbled = barWith(FieldSliderBubble());
    expect(bubbled.narrowestIn(context), FieldSlider.bubbleHandsReach);

    final upright = FieldSlider(
      label: 'Size',
      nameInside: false,
      value: 10,
      min: 1,
      max: 100,
      axis: Axis.vertical,
      height: 20,
      upright: true,
      onChanged: (_) {},
    );
    expect(
      bubbled.standingRunIn(context),
      upright.narrowestIn(context) - FieldSlider.handsReach,
    );
  });
}
