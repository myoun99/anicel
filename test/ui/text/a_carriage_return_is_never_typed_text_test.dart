import 'package:anicel/src/ui/text/typed_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pasted_from_the_clipboard.dart';

/// 🐛F-584 (검증/서피스 2026-11-15): a Windows clipboard's line ends in
/// CR LF, and a field kept the CR — a ⊠ where the lines broke.
///
/// ONE LAW, TWO SHAPES (관제 2026-11-15): the CR is dropped first; a field of
/// many lines keeps the LF it leaves, and a one-line field's own filter
/// takes that LF, as it always took a LF typed into it. Every line end a
/// clipboard can hold — CR LF, a lone CR, a LF — into both kinds of field,
/// pasted as a person pastes.
void main() {
  Future<String> pasted(
    WidgetTester tester,
    String text, {
    required bool manyLines,
  }) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            controller: controller,
            maxLines: manyLines ? null : 1,
            inputFormatters: typedText(),
          ),
        ),
      ),
    );
    await pasteInto(tester, find.byType(TextField), text);
    return controller.text;
  }

  for (final (end, name) in [
    ('\r\n', 'CR LF'),
    ('\r', 'a lone CR'),
    ('\n', 'a LF'),
  ]) {
    testWidgets('a one-line field takes two lines ended in $name as one, '
        'with nothing between them', (tester) async {
      expect(await pasted(tester, 'a${end}b', manyLines: false), 'ab');
    });
  }

  testWidgets('a field of many lines takes CR LF as the LF it ends in', (
    tester,
  ) async {
    expect(await pasted(tester, 'a\r\nb\r\nc', manyLines: true), 'a\nb\nc');
  });

  testWidgets('a field of many lines takes a lone CR as nothing — the law '
      'drops a CR wherever it stands', (tester) async {
    expect(await pasted(tester, 'a\rb', manyLines: true), 'ab');
  });

  testWidgets('a field of many lines takes a LF as it is', (tester) async {
    expect(await pasted(tester, 'a\nb', manyLines: true), 'a\nb');
  });

  test('the caret stands after what is kept: a CR dropped before it moves '
      'it back by one', () {
    const before = TextEditingValue.empty;
    final after = typedText().single.formatEditUpdate(
      before,
      const TextEditingValue(
        text: 'a\r\nb',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    expect(after.text, 'a\nb');
    expect(after.selection, const TextSelection.collapsed(offset: 3));
  });

  test("a draft the IME is still composing is the IME's: left as it is, "
      'and formatted once it is committed (F-355)', () {
    const draft = TextEditingValue(
      text: 'a\rb',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 0, end: 3),
    );
    final law = typedText().single;
    expect(law.formatEditUpdate(TextEditingValue.empty, draft), same(draft));
    expect(
      law
          .formatEditUpdate(
            TextEditingValue.empty,
            draft.copyWith(composing: TextRange.empty),
          )
          .text,
      'ab',
    );
  });

  test('a value with no CR is handed back as it came — the law does no work '
      'where it has nothing to drop', () {
    const typed = TextEditingValue(
      text: 'ab',
      selection: TextSelection.collapsed(offset: 2),
    );
    expect(
      typedText().single.formatEditUpdate(TextEditingValue.empty, typed),
      same(typed),
    );
  });

  test("a field's own formatters come after the law", () {
    final own = FilteringTextInputFormatter.digitsOnly;
    expect(typedText([own]), [isA<NoCarriageReturnFormatter>(), same(own)]);
  });
}
