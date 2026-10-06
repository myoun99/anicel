import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_editing_controller.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// R9-rest (the text tool): THE LETTERS OF A TEXT WHILE IT IS TYPED INTO —
/// what a keyboard leaves in the field, kept as the text's own runs, and
/// the steps back a visit to the letters keeps for itself.
///
/// A keyboard hands over the text it LEFT, never the edit it made, so every
/// test here speaks as a keyboard does ([leave]): the whole text, where the
/// caret stands, and what an IME is still composing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const plain = TextLetterStyle(fontSize: 8);
  const red = TextLetterStyle(fontSize: 8, color: 0xFFFF0000);

  CelTextSpan run(String words, [TextLetterStyle style = plain]) =>
      CelTextSpan(text: words, style: style);

  CelTextContent said(List<CelTextSpan> spans) =>
      CelTextContent(spans: spans, anchor: CanvasPoint(x: 0, y: 0));

  CelTextEditingController on(List<CelTextSpan> spans) {
    final controller = CelTextEditingController(
      content: said(spans),
      nextLetterStyle: plain,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  /// The keyboard leaves [text] in the field, the caret at [caret] — its
  /// end unless said — and [composing] still under way.
  void leave(
    CelTextEditingController letters,
    String text, {
    int? caret,
    TextRange composing = TextRange.empty,
  }) {
    letters.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret ?? text.length),
      composing: composing,
    );
  }

  /// [text] typed a letter at a time, each after the last.
  void type(CelTextEditingController letters, String text) {
    final from = letters.text;
    for (var i = 1; i <= text.length; i += 1) {
      leave(letters, from + text.substring(0, i));
    }
  }

  void caretTo(CelTextEditingController letters, int offset) =>
      letters.selection = TextSelection.collapsed(offset: offset);

  /// The IME commits what it was composing, where it stands.
  void commit(CelTextEditingController letters) =>
      leave(letters, letters.text, caret: letters.selection.extentOffset);

  group('the field\'s letters are the text\'s runs', () {
    test('it starts as the text, the caret at its end', () {
      final letters = on([run('ab', red), run('cd')]);

      expect(letters.text, 'abcd');
      expect(letters.selection, const TextSelection.collapsed(offset: 4));
      expect(letters.content, said([run('ab', red), run('cd')]));
      expect(letters.canUndo, isFalse);
      expect(letters.canRedo, isFalse);
    });

    test('a letter typed BETWEEN letters wears the one before it', () {
      final letters = on([run('ab', red), run('cd')]);
      caretTo(letters, 2);

      leave(letters, 'abXcd', caret: 3);

      expect(letters.content, said([run('abX', red), run('cd')]));
    });

    test('at the very start it wears the first', () {
      final letters = on([run('ab', red), run('cd')]);
      caretTo(letters, 0);

      leave(letters, 'Xabcd', caret: 1);

      expect(letters.content, said([run('Xab', red), run('cd')]));
    });

    test('typed OVER selected letters it wears the first it replaces', () {
      final letters = on([run('ab', red), run('cd')]);
      letters.selection = const TextSelection(baseOffset: 2, extentOffset: 4);

      leave(letters, 'abZ');

      expect(letters.content, said([run('ab', red), run('Z')]));
    });

    test('🚨typed into a run of the SAME letter, the new one is the one at '
        'the caret — the keyboard does not say which', () {
      final letters = on([run('aa', red), run('aa')]);
      caretTo(letters, 2);

      leave(letters, 'aaaaa', caret: 3);

      expect(letters.content, said([run('aaa', red), run('aa')]));
    });

    test('into a text with no letters, the first wears what the tool sets '
        'next', () {
      final letters = CelTextEditingController(
        content: said(const []),
        nextLetterStyle: red,
      );
      addTearDown(letters.dispose);

      leave(letters, 'a');

      expect(letters.content, said([run('a', red)]));
    });

    test('the last letter taken out leaves how it was set for the next '
        'one typed', () {
      final letters = on([run('a', red), run('b')]);

      leave(letters, '');

      expect(letters.content.isEmpty, isTrue);
      expect(letters.nextLetterStyle, red, reason: 'the FIRST one\'s');

      leave(letters, 'c');

      expect(letters.content, said([run('c', red)]));
    });
  });

  group('a step back is one run of typing', () {
    test('a word typed letter by letter is ONE step, and the caret goes '
        'back with it', () {
      final letters = on(const []);

      type(letters, 'abc');

      expect(letters.canUndo, isTrue);

      letters.undo();

      expect(letters.text, '');
      expect(letters.selection, const TextSelection.collapsed(offset: 0));
      expect(letters.canUndo, isFalse);

      letters.redo();

      expect(letters.text, 'abc');
      expect(letters.selection, const TextSelection.collapsed(offset: 3));
      expect(letters.canRedo, isFalse);
    });

    test('a space is a step of its own, and the word after it another', () {
      final letters = on(const []);
      type(letters, 'ab cd');

      letters.undo();
      expect(letters.text, 'ab ');
      letters.undo();
      expect(letters.text, 'ab');
      letters.undo();
      expect(letters.text, '');
    });

    test('a break is one too', () {
      final letters = on(const []);
      type(letters, 'ab\ncd');

      letters.undo();
      expect(letters.text, 'ab\n');
      letters.undo();
      expect(letters.text, 'ab');
    });

    test('a caret moved ends the run, even moved back to where it was', () {
      final letters = on(const []);
      type(letters, 'ab');
      caretTo(letters, 0);
      caretTo(letters, 2);

      type(letters, 'c');
      letters.undo();

      expect(letters.text, 'ab');
    });

    test('a letter taken out is a step of its own', () {
      final letters = on(const []);
      type(letters, 'abc');

      leave(letters, 'ab');
      letters.undo();

      expect(letters.text, 'abc');

      letters.undo();

      expect(letters.text, '');
    });

    test('letters that arrive together — a paste — are a step of their '
        'own', () {
      final letters = on(const []);
      type(letters, 'ab');

      leave(letters, 'abXYZ');
      type(letters, 'c');
      letters.undo();

      expect(letters.text, 'abXYZ', reason: 'the letter after a paste');

      letters.undo();

      expect(letters.text, 'ab');
    });

    test('a new edit forgets the steps forward', () {
      final letters = on(const []);
      type(letters, 'a');
      letters.undo();
      expect(letters.canRedo, isTrue, reason: '⛔fixture');

      type(letters, 'b');

      expect(letters.canRedo, isFalse);
    });

    test('the last two hundred are kept, and the oldest let go', () {
      final letters = on(const []);
      // A space is a step of its own: 205 of them, 205 steps.
      for (var i = 1; i <= 205; i += 1) {
        leave(letters, ' ' * i);
      }

      var taken = 0;
      while (letters.canUndo) {
        letters.undo();
        taken += 1;
      }

      expect(taken, 200);
      expect(letters.text, ' ' * 5);
    });

    test('with none to take, a step back does nothing', () {
      final letters = on([run('ab')]);

      letters
        ..undo()
        ..redo();

      expect(letters.text, 'ab');
    });
  });

  group('typed through an IME', () {
    test('a syllable growing is the same typing: the IME setting its '
        'letters again is no step', () {
      final letters = on(const []);

      leave(letters, 'ㅎ', composing: const TextRange(start: 0, end: 1));
      leave(letters, '하', composing: const TextRange(start: 0, end: 1));
      leave(letters, '한', composing: const TextRange(start: 0, end: 1));
      letters.undo();

      expect(letters.text, '');
      expect(letters.canUndo, isFalse);
    });

    test('🚨a composition COMMITTED ends the run: a line typed through an '
        'IME is not one step', () {
      final letters = on(const []);
      leave(letters, 'ㅎ', composing: const TextRange(start: 0, end: 1));
      leave(letters, '한', composing: const TextRange(start: 0, end: 1));
      commit(letters);
      leave(letters, '한ㄱ', composing: const TextRange(start: 1, end: 2));
      leave(letters, '한글', composing: const TextRange(start: 1, end: 2));

      letters.undo();

      expect(letters.text, '한');

      letters.undo();

      expect(letters.text, '');
    });

    test('committed by the very edit that sets its letters again — a '
        'consonant moving on to the next syllable — it still ends the run', () {
      final letters = on(const []);
      leave(letters, 'ㄱ', composing: const TextRange(start: 0, end: 1));
      leave(letters, '간', composing: const TextRange(start: 0, end: 1));
      // 「ㅏ」: the IME commits 「가」 and goes on composing 「나」.
      leave(letters, '가');
      leave(letters, '가나', composing: const TextRange(start: 1, end: 2));

      letters.undo();

      expect(letters.text, '가');

      letters.undo();

      expect(letters.text, '');
    });

    test('a clause converted is the same typing, however many letters the '
        'IME rewrote — and the next clause is another step', () {
      final letters = on(const []);
      leave(letters, 'か', composing: const TextRange(start: 0, end: 1));
      leave(letters, 'かん', composing: const TextRange(start: 0, end: 2));
      leave(letters, 'かんじ', composing: const TextRange(start: 0, end: 3));
      leave(letters, '漢字', composing: const TextRange(start: 0, end: 2));
      commit(letters);
      leave(letters, '漢字を', composing: const TextRange(start: 2, end: 3));

      letters.undo();

      expect(letters.text, '漢字');

      letters.undo();

      expect(letters.text, '');
    });

    test('a step back leaves nothing composing', () {
      final letters = on(const []);
      leave(letters, 'ㅎ', composing: const TextRange(start: 0, end: 1));
      commit(letters);
      leave(letters, 'ㅎㄱ', composing: const TextRange(start: 1, end: 2));

      letters
        ..undo()
        ..redo();

      expect(letters.text, 'ㅎㄱ');
      expect(letters.value.composing, TextRange.empty);
    });
  });

  group('a step back puts back the RUNS, not letters typed again', () {
    test('🚨a red word taken out and brought back is red', () {
      final letters = on([run('ab', red), run('cd')]);
      letters.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
      leave(letters, 'cd', caret: 0);
      expect(letters.content, said([run('cd')]), reason: '⛔fixture');

      letters.undo();

      expect(letters.content, said([run('ab', red), run('cd')]));
      expect(
        letters.selection,
        const TextSelection(baseOffset: 0, extentOffset: 2),
        reason: 'and the letters that were selected are selected',
      );
    });

    test('the letter the tool sets next comes back with them', () {
      final letters = on([run('a', red)]);
      leave(letters, '');
      expect(letters.nextLetterStyle, red, reason: '⛔fixture');

      letters.undo();

      expect(letters.nextLetterStyle, plain);
      expect(letters.content, said([run('a', red)]));
    });

    test('whoever listens is told once for a step taken', () {
      final letters = on(const []);
      type(letters, 'ab');
      var told = 0;
      letters.addListener(() => told += 1);

      letters.undo();

      expect(told, 1);
    });
  });

  group('a setting changed while the letters are held', () {
    test('sets the runs differently with every letter and the caret where '
        'it is — one step back, and forward again', () {
      final letters = on([run('ab')]);
      caretTo(letters, 1);

      letters.restyle(said([run('ab', red)]));

      expect(letters.content, said([run('ab', red)]));
      expect(letters.text, 'ab');
      expect(letters.selection, const TextSelection.collapsed(offset: 1));

      letters.undo();

      expect(letters.content, said([run('ab')]));

      letters.redo();

      expect(letters.content, said([run('ab', red)]));
    });

    test('🚨a step that changed only how letters are set still tells whoever '
        'listens — the field itself has nothing new to say', () {
      final letters = on([run('ab')]);
      letters.restyle(said([run('ab', red)]));
      var told = 0;
      letters.addListener(() => told += 1);

      letters.undo();

      expect(told, 1);
    });

    test('a value still being dragged is the same step as the one before '
        'it: a slider drawn across its track is one step back', () {
      final letters = on([run('ab')]);
      CelTextContent sized(double size) =>
          said([run('ab', TextLetterStyle(fontSize: size))]);

      letters
        ..restyle(sized(9))
        ..restyle(sized(10), goesOn: true)
        ..restyle(sized(11), goesOn: true)
        ..undo();

      expect(letters.content, said([run('ab')]));
      expect(letters.canUndo, isFalse);
    });

    test('set as it already is, it is no step', () {
      final letters = on([run('ab')]);

      letters.restyle(said([run('ab')]));

      expect(letters.canUndo, isFalse);
    });

    test('a text with no letters takes the letter about to be typed', () {
      final letters = on(const []);

      letters.restyle(said(const []), nextLetterStyle: red);

      expect(letters.nextLetterStyle, red);

      letters.undo();

      expect(letters.nextLetterStyle, plain);
    });

    test('ends the run of typing before it, and is not part of the one '
        'after', () {
      final letters = on(const []);
      type(letters, 'ab');
      letters.restyle(said([run('ab', red)]));
      type(letters, 'c');

      letters.undo();
      expect(letters.content, said([run('ab', red)]));
      letters.undo();
      expect(letters.content, said([run('ab')]));
      letters.undo();
      expect(letters.text, '');
    });

    test('forgets the steps forward, as an edit does', () {
      final letters = on(const []);
      type(letters, 'ab');
      letters.undo();
      type(letters, 'cd');
      letters.undo();
      expect(letters.canRedo, isTrue, reason: '⛔fixture');

      letters.restyle(said(const []), nextLetterStyle: red);

      expect(letters.canRedo, isFalse);
    });
  });

  testWidgets('the field sets the letters as the canvas does — the very '
      'spans, and nothing of its own for what is being composed', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (built) {
          context = built;
          return const SizedBox();
        },
      ),
    );
    final letters = on([run('ab', red), run('cd')]);
    letters.value = letters.value.copyWith(
      composing: const TextRange(start: 2, end: 4),
    );

    final span = letters.buildTextSpan(context: context, withComposing: true);

    expect(span.toPlainText(), 'abcd');
    expect(
      span,
      celTextFieldSpan(
        said([run('ab', red), run('cd')]),
        nextLetterStyle: plain,
      ),
    );
  });
}
