// 🗣️I-177 (유저 2026-11-17): 「레이어의 불투명도/오디오막대만 추가기능. 막대
// 안에서 더블클릭하면 수동편집가능하게. 아래에 공용 넘버패드ui 열어서 …
// 몇px로 더블클릭하면같은 과거에 몇번이나 문제시했던거 하지말고 막대안에서
// 더블클릭 일어나면. 그러니 더블클릭 일어나고 취소한다던가 하는 동작한다고
// 이전 값으로 되돌리지않음. 더블클릭하더라도 일반클릭이랑 동일하게
// 다른규칙두지말고 값 변경된거」.
//
// The bar's own law ([FieldSlider.typesOnDoubleClick]); which bars say it is
// `a_rail_bar_types_its_number_on_a_double_click_test.dart`.
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart'
    show extentAcross, extentAlong, offsetAlong, sizedAlong;
import 'package:anicel/src/ui/widgets/field_slider.dart';

import '../../helpers/number_pad_keyboard.dart';

void main() {
  /// A bar 200 wide that keeps what it is handed, lying or stood — and
  /// what it handed over, each change and each end.
  Future<({List<double> changes, List<double> ends})> pumpBar(
    WidgetTester tester, {
    bool types = true,
    Axis axis = Axis.horizontal,
  }) async {
    final changes = <double>[];
    final ends = <double>[];
    var value = 0.5;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: sizedAlong(
              axis,
              along: 200,
              across: 24,
              child: StatefulBuilder(
                builder: (context, setState) => FieldSlider.opacity(
                  value: value,
                  axis: axis,
                  typesOnDoubleClick: types,
                  onChanged: (next) => setState(() {
                    value = next;
                    changes.add(next);
                  }),
                  onChangeEnd: ends.add,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return (changes: changes, ends: ends);
  }

  final bar = find.byType(FieldSlider);

  /// Where [along] of the way down the bar is, from its first edge along
  /// [axis] — its left lying, its top stood — across its middle.
  Offset at(WidgetTester tester, double along, {Axis axis = Axis.horizontal}) {
    final box = tester.getRect(bar);
    return box.topLeft +
        offsetAlong(
          axis,
          along: along * extentAlong(axis, box.size),
          across: extentAcross(axis, box.size) / 2,
        );
  }

  Future<void> click(WidgetTester tester, Offset where) async {
    await tester.tapAt(where);
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// The bar as it reads at rest, its number alone.
  int shown(List<double> ends) => (ends.last * 100).round();

  testWidgets('🎯two clicks in the bar: each sets the value where it landed, '
      'and none is taken back — and the number pad opens on the value the '
      'second left', (tester) async {
    final seen = await pumpBar(tester);
    await click(tester, at(tester, 0.3));
    expect(seen.ends, hasLength(1), reason: 'the first click is a click');
    expect(theNumberPadsNumber, findsNothing, reason: 'one click types not');
    await click(tester, at(tester, 0.7));
    await tester.pump();
    expect(seen.ends, hasLength(2), reason: 'so is the second');
    expect(seen.ends.last, greaterThan(seen.ends.first));
    expect(seen.changes.last, seen.ends.last, reason: 'nothing taken back');
    expect(theNumberPadsNumber, findsOneWidget);
    expect(
      tester.widget<Text>(theNumberPadsNumber).data,
      '${shown(seen.ends)}',
    );
  });

  testWidgets('the number typed after a double click is one complete edit, '
      'as the pencil\'s is', (tester) async {
    final seen = await pumpBar(tester);
    await click(tester, at(tester, 0.3));
    await click(tester, at(tester, 0.3));
    await tester.pump();
    await openThePadsKeyboard(tester);
    final field = find.byKey(
      const ValueKey<String>('field-slider-type-input'),
    );
    await tester.enterText(field, '55');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(seen.changes.last, closeTo(0.55, 1e-9));
    expect(seen.ends, hasLength(3));
    expect(seen.ends.last, closeTo(0.55, 1e-9));
  });

  testWidgets('two clicks further apart than a double click\'s time type '
      'nothing — each is a click', (tester) async {
    final seen = await pumpBar(tester);
    await click(tester, at(tester, 0.3));
    await tester.pump(kDoubleTapTimeout);
    await click(tester, at(tester, 0.7));
    await tester.pump(kDoubleTapTimeout);
    expect(seen.ends, hasLength(2));
    expect(theNumberPadsNumber, findsNothing);
  });

  testWidgets('⛔no distance: a second press that slides along the bar and '
      'comes up in it is the second click — the value where it came up', (
    tester,
  ) async {
    final seen = await pumpBar(tester);
    await click(tester, at(tester, 0.3));
    final hand = await tester.startGesture(at(tester, 0.4));
    await tester.pump();
    await hand.moveTo(at(tester, 0.8));
    await tester.pump();
    await hand.up();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(theNumberPadsNumber, findsOneWidget);
    expect(
      tester.widget<Text>(theNumberPadsNumber).data,
      '${shown(seen.ends)}',
    );
    expect(seen.ends.last, greaterThan(0.7));
  });

  testWidgets('a second press let go away from the bar is no click — and the '
      'click after it is a first one', (tester) async {
    final seen = await pumpBar(tester);
    await click(tester, at(tester, 0.3));
    final hand = await tester.startGesture(at(tester, 0.4));
    await tester.pump();
    await hand.moveTo(at(tester, 0.4) + const Offset(0, 200));
    await tester.pump();
    await hand.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(theNumberPadsNumber, findsNothing);
    await click(tester, at(tester, 0.6));
    await tester.pump();
    expect(theNumberPadsNumber, findsNothing);
    expect(seen.ends, isNotEmpty);
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('a STOOD bar types on a double click too — the X-sheet\'s', (
    tester,
  ) async {
    final seen = await pumpBar(tester, axis: Axis.vertical);
    await click(tester, at(tester, 0.3, axis: Axis.vertical));
    await click(tester, at(tester, 0.6, axis: Axis.vertical));
    await tester.pump();
    expect(theNumberPadsNumber, findsOneWidget);
    expect(
      tester.widget<Text>(theNumberPadsNumber).data,
      '${shown(seen.ends)}',
    );
  });

  testWidgets('a bar that does not say so types on no double click — it '
      'clicks twice', (tester) async {
    final seen = await pumpBar(tester, types: false);
    await click(tester, at(tester, 0.3));
    await click(tester, at(tester, 0.7));
    await tester.pump();
    expect(seen.ends, hasLength(2));
    expect(theNumberPadsNumber, findsNothing);
    await tester.pump(kDoubleTapTimeout);
  });
}
