// THE NUMBER PAD A VALUE'S PENCIL OPENS (I-134), driven as a user does: the
// number at its top, its keys under it, and the field the top becomes.
//
// 🗣️I-134 (유저 2026-10-27): 「숫자만 입력하는 값이라면 전용 숫자 앵커
// 팝오버창 만들어서 그거로 입력가능하게 … -가 존재하는 숫자라면 -넣고 …
// 선택하지 않은 상태로 두고 숫자 누르면 기존 숫자 지워지고 해당 숫자
// 입력되는느낌. 위에 숫자 텍스트 클릭하면 직접 키보드로 수정할수있게 텍스트
// 선택된상태 들어감 … 대응 불가능한거면 비활성화시키도록」.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/drag_value_label.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/number_pad.dart';

import '../../helpers/ime_draft.dart';
import '../../helpers/number_pad_keyboard.dart';

TextEditingValue _whole(String text) => TextEditingValue(
  text: text,
  selection: TextSelection(baseOffset: 0, extentOffset: text.length),
);

TextEditingValue _caretAtEnd(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);

void main() {
  group('what a key makes of the number', () {
    test('the first key replaces the number the pad opened on whole', () {
      expect(numberPadTyped(_whole('100'), '7').text, '7');
      expect(numberPadTyped(_caretAtEnd('7'), '5').text, '75');
    });

    test('a point is typed once, after a zero where no digit leads it', () {
      expect(numberPadTyped(_caretAtEnd('7'), '.').text, '7.');
      expect(numberPadTyped(_caretAtEnd('7.5'), '.').text, '7.5');
      expect(numberPadTyped(_whole('100'), '.').text, '0.');
      expect(numberPadTyped(_caretAtEnd('-'), '.').text, '-0.');
    });

    test('a lone leading zero gives way to the digit after it', () {
      expect(numberPadTyped(_caretAtEnd('0'), '5').text, '5');
      expect(numberPadTyped(_caretAtEnd('-0'), '5').text, '-5');
      expect(numberPadTyped(_caretAtEnd('0.'), '5').text, '0.5');
    });

    test('the minus starts a number over a whole one, else turns its sign', () {
      expect(numberPadNegated(_whole('12')).text, '-');
      expect(numberPadNegated(_caretAtEnd('12')).text, '-12');
      expect(numberPadNegated(_caretAtEnd('-12')).text, '12');
      expect(
        numberPadNegated(_caretAtEnd('12')).selection,
        const TextSelection.collapsed(offset: 3),
        reason: 'the caret stays after the last digit',
      );
    });

    test('backspace takes the selection, or the character before it', () {
      expect(numberPadErased(_whole('100')).text, '');
      expect(numberPadErased(_caretAtEnd('125')).text, '12');
      expect(numberPadErased(_caretAtEnd('')).text, '');
    });
  });

  /// A number box with its pencil, as the tool settings show one.
  Future<List<String>> pumpBox(
    WidgetTester tester, {
    String text = '100%',
    bool digitsOnly = false,
    bool signed = true,
  }) async {
    final typed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: DragValueLabel.box(
                keyValue: 'value',
                name: 'X',
                text: text,
                digitsOnly: digitsOnly,
                signed: signed,
                onDragDelta: (_) {},
                onEditSubmit: typed.add,
              ),
            ),
          ),
        ),
      ),
    );
    return typed;
  }

  Finder key(String name) => find.byKey(ValueKey<String>('value-pad-$name'));
  final number = find.byKey(const ValueKey<String>('value-pad-number'));
  final field = find.byKey(const ValueKey<String>('value-input'));

  Future<void> openPad(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('value-edit')));
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, String name) async {
    await tester.tap(key(name));
    await tester.pump();
  }

  testWidgets('the pencil opens the pad on the number alone — no field, so '
      'no keyboard rises', (tester) async {
    await pumpBox(tester);
    await openPad(tester);
    expect(tester.widget<Text>(number).data, '100');
    expect(
      find.byType(EditableText),
      findsNothing,
      reason: '「바로 키보드 올라와버리니까 선택하지 않은 상태로 두고」',
    );
  });

  testWidgets('the first digit replaces the number, the rest follow it, and '
      '✓ hands the owner what was typed', (tester) async {
    final typed = await pumpBox(tester);
    await openPad(tester);
    await press(tester, '2');
    await press(tester, '5');
    expect(tester.widget<Text>(number).data, '25');
    await press(tester, 'enter');
    expect(typed, ['25']);
    expect(number, findsNothing, reason: 'the pad is gone');
  });

  testWidgets('erase and ✓ stand two keys tall beside the keys', (
    tester,
  ) async {
    await pumpBox(tester);
    await openPad(tester);
    Rect at(String name) => tester.getRect(key(name));
    expect(
      (at('backspace').top, at('backspace').bottom),
      (at('7').top, at('4').bottom),
    );
    expect(
      (at('enter').top, at('enter').bottom),
      (at('1').top, at('minus').bottom),
    );
  });

  testWidgets('the number on top is the field once pressed: the keyboard '
      'types it, all of it selected, and the keys still type into it', (
    tester,
  ) async {
    final typed = await pumpBox(tester);
    await openPad(tester);
    await press(tester, '4');
    await openThePadsKeyboard(tester);
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(
      editable.controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 1),
      reason: '「텍스트 선택된상태 들어감」',
    );
    expect(editable.focusNode.hasFocus, isTrue, reason: 'the keyboard is up');

    await press(tester, '9');
    expect(editable.controller.text, '9', reason: 'a key types into it');
    expect(field, findsOneWidget, reason: 'and the pad stays open');

    await tester.enterText(field, '90');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(typed, ['90']);
    expect(field, findsNothing);
  });

  testWidgets('with the keyboard up a hardware key is the field\'s alone, '
      'and the keyboard asks for no minus a value cannot take', (
    tester,
  ) async {
    await pumpBox(tester, signed: false);
    await openPad(tester);
    await openThePadsKeyboard(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '100',
      reason: 'the pad types no key the field hears',
    );
    expect(
      tester.widget<TextField>(field).keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
  });

  testWidgets('✓ hands on what an IME still composes, its numerals '
      'half-width', (tester) async {
    final typed = await pumpBox(tester);
    await openPad(tester);
    await openThePadsKeyboard(tester);
    await composeDraft(tester, field, '１２');
    await press(tester, 'enter');
    expect(typed, ['12']);
  });

  testWidgets('a press away commits what was typed, and drops an untouched '
      'number', (tester) async {
    final typed = await pumpBox(tester);
    await openPad(tester);
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(typed, isEmpty, reason: 'nothing was typed');
    expect(number, findsNothing);

    await openPad(tester);
    await press(tester, '3');
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(typed, ['3']);
  });

  testWidgets('a press away with the keyboard up commits once', (
    tester,
  ) async {
    final typed = await pumpBox(tester);
    await openPad(tester);
    await openThePadsKeyboard(tester);
    await tester.enterText(field, '42');
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(typed, ['42']);
    expect(find.byType(DragValueLabel), findsOneWidget, reason: 'one pop');
  });

  testWidgets('Escape abandons, the pad\'s keys or the keyboard\'s', (
    tester,
  ) async {
    final typed = await pumpBox(tester);
    await openPad(tester);
    await press(tester, '3');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(number, findsNothing);

    await openPad(tester);
    await openThePadsKeyboard(tester);
    await tester.enterText(field, '8');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(field, findsNothing);
    expect(typed, isEmpty);
  });

  testWidgets('a hardware keyboard types on the pad as its keys do', (
    tester,
  ) async {
    final typed = await pumpBox(tester);
    await openPad(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
    await tester.pump();
    expect(tester.widget<Text>(number).data, '17');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(typed, ['17']);
  });

  testWidgets('a hardware key that comes full-width types its digit', (
    tester,
  ) async {
    await pumpBox(tester);
    await openPad(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3, character: '３');
    await tester.pump();
    expect(tester.widget<Text>(number).data, '3');
  });

  testWidgets('a key the value cannot take is dark', (tester) async {
    await pumpBox(tester);
    await openPad(tester);
    expect(thePadsLitKeys(tester), (minus: true, point: true));
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();

    await pumpBox(tester, signed: false);
    await openPad(tester);
    expect(
      thePadsLitKeys(tester),
      (minus: false, point: true),
      reason: 'a zoom takes a point and no minus',
    );
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();

    await pumpBox(tester, text: '4', digitsOnly: true);
    await openPad(tester);
    expect(
      thePadsLitKeys(tester),
      (minus: false, point: false),
      reason: 'a count takes neither',
    );
    expect(thePadsKeyIsLit(tester, '0'), isTrue);
  });

  testWidgets('the minus types a negative number', (tester) async {
    final typed = await pumpBox(tester, text: '15°');
    await openPad(tester);
    await press(tester, 'minus');
    await press(tester, '3');
    await press(tester, 'enter');
    expect(typed, ['-3']);
  });

  testWidgets('while its pad is open the box wears the typed frame, its name '
      'and its number where they stood — and rests once it closes', (
    tester,
  ) async {
    await pumpBox(tester);
    final restingRight = tester.getRect(find.text('100%')).right;
    Iterable<Decoration> frames() => tester
        .widgetList<DecoratedBox>(
          find.ancestor(
            of: find.text('100%'),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((decorated) => decorated.decoration);
    Decoration frame({required bool typed}) => FieldSlider.frameOf(
      FieldSlider.defaultHeight,
      enabled: true,
      typed: typed,
    );

    await openPad(tester);
    expect(find.text('X'), findsOneWidget);
    expect(tester.getRect(find.text('100%')).right, restingRight);
    expect(frames(), contains(frame(typed: true)));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(frames(), contains(frame(typed: false)));
  });

  testWidgets('a settings bar\'s pencil opens the same pad: a minus where it '
      'runs below zero, a point where it lands between whole numbers', (
    tester,
  ) async {
    final typed = <double>[];
    Future<void> pumpBar({required double min, required int divisions}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 260,
                  child: FieldSlider(
                    label: 'Offset',
                    value: 0,
                    min: min,
                    max: 10,
                    divisions: divisions,
                    onChanged: typed.add,
                  ),
                ),
              ),
            ),
          ),
        );
    Finder barKey(String name) =>
        find.byKey(ValueKey<String>('field-slider-type-pad-$name'));

    await pumpBar(min: -10, divisions: 20);
    await tester.tap(find.byKey(const ValueKey<String>('field-slider-type')));
    await tester.pump();
    expect(thePadsLitKeys(tester), (minus: true, point: false));
    await tester.tap(barKey('minus'));
    await tester.tap(barKey('4'));
    await tester.tap(barKey('enter'));
    await tester.pump();
    expect(typed.last, -4);

    await pumpBar(min: 0, divisions: 100);
    await tester.tap(find.byKey(const ValueKey<String>('field-slider-type')));
    await tester.pump();
    expect(thePadsLitKeys(tester), (minus: false, point: true));
  });

  testWidgets('a bar resting on a word opens its pad on that word — the '
      'mixed influence of keys that disagree — and the first key replaces '
      'it', (tester) async {
    final typed = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              child: FieldSlider(
                label: 'Influence',
                value: 0.5,
                min: 0.1,
                max: 1,
                divisions: 90,
                displayScale: 100,
                unit: '%',
                restingText: 'Mixed',
                onChanged: typed.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('field-slider-type')));
    await tester.pump();
    expect(tester.widget<Text>(theNumberPadsNumber).data, 'Mixed');
    for (final name in const ['4', '0', 'enter']) {
      await tester.tap(
        find.byKey(ValueKey<String>('field-slider-type-pad-$name')),
      );
      await tester.pump();
    }
    expect(typed.last, closeTo(0.4, 1e-9));
  });

  testWidgets('the keys wear the app\'s one button, edged', (tester) async {
    await pumpBox(tester);
    await openPad(tester);
    for (final name in const ['7', 'minus', 'point', 'backspace', 'enter']) {
      expect(tester.widget<AppIconButtonFace>(key(name)).outlined, isTrue);
    }
  });
}
