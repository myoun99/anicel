import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cel_text_fixture.dart';

/// R9-rest (the text tool): what a text on a cel is made of — runs of
/// letters in a letter style, the values of the whole box, and the plate.
void main() {
  const red = TextLetterStyle(color: 0xFFFF0000);
  const big = TextLetterStyle(fontSize: 96);

  CelTextContent contentOf(List<CelTextSpan> spans) =>
      CelTextContent(spans: spans, anchor: CanvasPoint(x: 10, y: 20));

  group('a content keeps its runs settled', () {
    test('neighbours in one style are one run', () {
      final content = contentOf(const [
        CelTextSpan(text: 'ab', style: red),
        CelTextSpan(text: 'cd', style: red),
        CelTextSpan(text: 'ef', style: big),
      ]);

      expect(content.spans, const [
        CelTextSpan(text: 'abcd', style: red),
        CelTextSpan(text: 'ef', style: big),
      ]);
      expect(content.text, 'abcdef');
    });

    test('a run with no letters is not kept — and its neighbours meet', () {
      final content = contentOf(const [
        CelTextSpan(text: 'ab', style: red),
        CelTextSpan(text: '', style: big),
        CelTextSpan(text: 'cd', style: red),
      ]);

      expect(content.spans, const [CelTextSpan(text: 'abcd', style: red)]);
    });

    test('two contents that read and look alike are equal, however they '
        'were cut into runs', () {
      final whole = contentOf(const [CelTextSpan(text: 'abcd', style: red)]);
      final pieces = contentOf(const [
        CelTextSpan(text: 'a', style: red),
        CelTextSpan(text: 'bcd', style: red),
      ]);

      expect(pieces, whole);
      expect(pieces.hashCode, whole.hashCode);
    });

    test('a content with no letters is empty', () {
      expect(contentOf(const []).isEmpty, isTrue);
      expect(contentOf(const [CelTextSpan(text: '', style: red)]).isEmpty, isTrue);
      expect(contentOf(const [CelTextSpan(text: 'a', style: red)]).isEmpty, isFalse);
    });
  });

  group('every value of a content is part of what it is', () {
    final base = CelTextContent(
      spans: const [CelTextSpan(text: 'ab', style: red)],
      anchor: CanvasPoint(x: 10, y: 20),
    );

    final changes = <String, CelTextContent>{
      'the letters': base.copyWith(
        spans: const [CelTextSpan(text: 'ac', style: red)],
      ),
      'the style of a run': base.copyWith(
        spans: const [CelTextSpan(text: 'ab', style: big)],
      ),
      'the anchor': base.copyWith(anchor: CanvasPoint(x: 11, y: 20)),
      'the wrap width': base.copyWith(wrapWidth: 200.5),
      'the turn': base.copyWith(rotationDegrees: 30),
      'the alignment': base.copyWith(align: TextCelAlign.right),
      'the line height': base.copyWith(lineHeight: 2),
      'the box behind it': base.copyWith(backgroundColor: 0xFFFFFF00),
      'the way it is written': base.copyWith(vertical: true),
    };

    for (final entry in changes.entries) {
      test('${entry.key} — changed, it is another content; written and '
          'read back, the same one', () {
        expect(entry.value, isNot(base));
        expect(
          CelTextContent.fromJson(throughJson(entry.value.toJson())),
          entry.value,
        );
      });
    }

    test('a content with nothing changed reads back as itself', () {
      expect(CelTextContent.fromJson(throughJson(base.toJson())), base);
    });

    test('🚨a text written in LINES writes no word of it: what a file '
        'written before a text could be set in columns says is a text in '
        'lines', () {
      expect(base.vertical, isFalse);
      expect(base.toJson().containsKey('vertical'), isFalse);
      expect(base.copyWith(vertical: true).toJson()['vertical'], isTrue);
    });

    test('a text in columns stays one through a change of anything else, '
        'and is turned back', () {
      final columns = base.copyWith(vertical: true);

      expect(columns.copyWith(lineHeight: 2).vertical, isTrue);
      expect(columns.copyWith(vertical: false), base);
      expect(columns.hashCode, isNot(base.hashCode));
    });

    // The parameter is untyped so that null can mean 「take it off」, and a
    // whole number written with no decimal point arrives as an int.
    test('a width written as a whole number is that width', () {
      expect(base.copyWith(wrapWidth: 200).wrapWidth, 200.0);
    });

    test('a wrap width and a box can be taken off again', () {
      final boxed = base.copyWith(wrapWidth: 200, backgroundColor: 0xFF00FF00);

      expect(boxed.copyWith(wrapWidth: null).wrapWidth, isNull);
      expect(boxed.copyWith(wrapWidth: null).backgroundColor, 0xFF00FF00);
      expect(boxed.copyWith(backgroundColor: null).backgroundColor, isNull);
      expect(boxed.copyWith(backgroundColor: null).wrapWidth, 200);
    });

    // F-317: 「위아래 크기지정도 처음에 사각형 만들때 살린다」.
    test('how tall a box is at least is part of what it is: changed, it is '
        'another content; written and read back, the same one — and a box '
        'with none writes no word of it', () {
      final boxed = base.copyWith(wrapWidth: 200);
      final tall = boxed.copyWith(minHeight: 40.5);

      expect(tall, isNot(boxed));
      expect(tall.hashCode, isNot(boxed.hashCode));
      expect(CelTextContent.fromJson(throughJson(tall.toJson())), tall);
      expect(boxed.toJson().containsKey('minHeight'), isFalse);
      expect(boxed.copyWith(minHeight: 40).minHeight, 40.0);
      expect(tall.copyWith(minHeight: null).minHeight, isNull);
      expect(tall.copyWith(lineHeight: 2).minHeight, 40.5);
    });

    test('🚨a text that GROWS has no box to be tall: a least height without '
        'a width is refused, and so is taking the width off a box that '
        'has one', () {
      final tall = base.copyWith(wrapWidth: 200, minHeight: 40);

      expect(() => base.copyWith(minHeight: 40), throwsArgumentError);
      expect(() => tall.copyWith(wrapWidth: null), throwsArgumentError);
      expect(
        tall.copyWith(wrapWidth: null, minHeight: null).wrapWidth,
        isNull,
      );
    });

    test('🚨a box of no width, a pitch of nothing and a turn that is not a '
        'number are refused where the content is MADE — not set, baked and '
        'kept', () {
      for (final width in [0.0, -1.0, double.infinity, double.nan]) {
        expect(
          () => base.copyWith(wrapWidth: width),
          throwsArgumentError,
          reason: 'a box $width wide',
        );
      }
      for (final least in [0.0, -1.0, double.infinity, double.nan]) {
        expect(
          () => base.copyWith(wrapWidth: 200, minHeight: least),
          throwsArgumentError,
          reason: 'a box $least tall at least',
        );
      }
      for (final pitch in [0.0, -1.25, double.infinity, double.nan]) {
        expect(
          () => base.copyWith(lineHeight: pitch),
          throwsArgumentError,
          reason: 'lines $pitch apart',
        );
      }
      for (final turn in [double.infinity, double.nan]) {
        expect(
          () => base.copyWith(rotationDegrees: turn),
          throwsArgumentError,
          reason: 'turned by $turn',
        );
      }
      expect(base.copyWith(wrapWidth: 0.5).wrapWidth, 0.5);
      expect(base.copyWith(wrapWidth: 1, minHeight: 0.5).minHeight, 0.5);
      expect(base.copyWith(lineHeight: 0.5).lineHeight, 0.5);
      expect(base.copyWith(rotationDegrees: -725).rotationDegrees, -725);
    });
  });

  group('a letter style', () {
    test('is black, at the size the canvas text has always started at', () {
      // 유저 2026-10-06: 「기본값은 검정이고 텍스트편집툴 프로들 다
      // 이렇게하잖아」.
      const style = TextLetterStyle();

      expect(style.color, 0xFF000000);
      expect(style.fontSize, 48);
      expect(style.outlineColor, isNull);
      expect(style.antialias, isTrue, reason: 'smooth until said otherwise');
    });

    test('🚨a smooth letter writes NO word of its edges: what a file written '
        'before the switch says of a letter is what a smooth one says', () {
      expect(
        const TextLetterStyle().toJson().containsKey('antialias'),
        isFalse,
      );
      expect(const TextLetterStyle(antialias: false).toJson(), {
        'fontSize': 48.0,
        'color': 0xFF000000,
        'antialias': false,
      });
    });

    test('a hard letter stays hard through a change of anything else', () {
      const hard = TextLetterStyle(antialias: false);

      expect(hard.copyWith(fontSize: 12).antialias, isFalse);
      expect(hard.copyWith(antialias: true), const TextLetterStyle());
      expect(hard.hashCode, isNot(const TextLetterStyle().hashCode));
    });

    final changes = <String, TextLetterStyle>{
      'the face': const TextLetterStyle(fontFamily: 'Nanum Gothic'),
      'the size': const TextLetterStyle(fontSize: 12),
      'the weight': const TextLetterStyle(bold: true),
      'the tracking': const TextLetterStyle(letterSpacing: 3),
      'the colour': const TextLetterStyle(color: 0xFF112233),
      'the outline colour': const TextLetterStyle(outlineColor: 0xFFFFFFFF),
      'the outline width': const TextLetterStyle(outlineWidth: 2),
      'the smoothing': const TextLetterStyle(antialias: false),
      'the lean': const TextLetterStyle(italic: true),
      'the line under': const TextLetterStyle(underline: true),
      'the line through': const TextLetterStyle(strikethrough: true),
    };

    test('🚨an upright, bare letter writes NO word of its lean or its lines: '
        'what a file written before them says of a letter is what an '
        'upright, bare one says', () {
      final json = const TextLetterStyle().toJson();
      for (final word in ['italic', 'underline', 'strikethrough']) {
        expect(json.containsKey(word), isFalse, reason: word);
      }
      expect(
        const TextLetterStyle(
          italic: true,
          underline: true,
          strikethrough: true,
        ).toJson(),
        {
          'fontSize': 48.0,
          'italic': true,
          'underline': true,
          'strikethrough': true,
          'color': 0xFF000000,
        },
      );
    });

    test('a leaning, lined letter stays so through a change of anything '
        'else', () {
      const lined = TextLetterStyle(
        italic: true,
        underline: true,
        strikethrough: true,
      );
      final bigger = lined.copyWith(fontSize: 12, bold: true);

      expect(
        (bigger.italic, bigger.underline, bigger.strikethrough),
        (true, true, true),
      );
      expect(
        lined.copyWith(italic: false, underline: false, strikethrough: false),
        const TextLetterStyle(),
      );
    });

    for (final entry in changes.entries) {
      test('${entry.key} — changed, it is another style; written and read '
          'back, the same one', () {
        expect(entry.value, isNot(const TextLetterStyle()));
        expect(
          TextLetterStyle.fromJson(throughJson(entry.value.toJson())),
          entry.value,
        );
      });
    }

    test('an SE tag style that happens to write the same letters is still '
        'not it — a tag style says more', () {
      const letters = TextLetterStyle(color: 0xFF202020);
      const tag = TextCelStyle();

      expect(tag.sameLettersAs(letters), isTrue, reason: 'fixture');
      expect(letters == tag, isFalse);
      expect(tag == letters, isFalse);
    });

    test('an SE tag style still starts at its own colour and keeps its '
        'block values through a change of its letters', () {
      const tag = TextCelStyle(
        align: TextCelAlign.right,
        backgroundColor: 0xFFAA0000,
      );

      expect(tag.color, 0xFF202020);
      final bigger = tag.copyWith(fontSize: 72);
      expect(bigger.fontSize, 72);
      expect(bigger.align, TextCelAlign.right);
      expect(bigger.backgroundColor, 0xFFAA0000);
    });

    test('🚨an SE tag style IS a letter style: it carries the smoothing of '
        'its letters through a copy and through a file', () {
      const hard = TextCelStyle(antialias: false);

      expect(hard, isNot(const TextCelStyle()));
      expect(hard.copyWith(fontSize: 72).antialias, isFalse);
      expect(hard.copyWith(antialias: true), const TextCelStyle());
      expect(TextCelStyle.fromJson(throughJson(hard.toJson())), hard);
      expect(
        const TextCelStyle().toJson().containsKey('antialias'),
        isFalse,
      );
    });

    test('🚨an SE tag style carries its letters\' lean and lines through a '
        'copy and through a file, as it carries their weight', () {
      const plain = TextCelStyle();
      for (final (lined, turned) in [
        (
          const TextCelStyle(italic: true),
          (TextCelStyle style, bool on) => style.copyWith(italic: on),
        ),
        (
          const TextCelStyle(underline: true),
          (TextCelStyle style, bool on) => style.copyWith(underline: on),
        ),
        (
          const TextCelStyle(strikethrough: true),
          (TextCelStyle style, bool on) => style.copyWith(strikethrough: on),
        ),
      ]) {
        expect(lined, isNot(plain));
        expect(
          lined.copyWith(fontSize: 72).copyWith(fontSize: lined.fontSize),
          lined,
        );
        expect(turned(plain, true), lined, reason: 'a copy turns it on');
        expect(turned(lined, false), plain, reason: 'and off');
        expect(TextCelStyle.fromJson(throughJson(lined.toJson())), lined);
        expect(lined.hashCode, isNot(plain.hashCode));
      }
      final json = plain.toJson();
      for (final word in ['italic', 'underline', 'strikethrough']) {
        expect(json.containsKey(word), isFalse, reason: word);
      }
    });
  });

  group('a text', () {
    final coord = TileCoord(x: 1, y: 2);
    final plate = {
      coord: tileOf({
        (0, 0): [10, 20, 30, 255],
      }),
    };

    test('keeps its id through a change of what it says or its plate', () {
      final text = textOf(7, plate: plate);

      expect(text.copyWith(content: textOf(1, words: 'other').content).id, 7);
      expect(text.copyWith(plate: const {}).id, 7);
    });

    test('is its id, what it says and its pixels', () {
      final text = textOf(7, words: 'a', plate: plate);

      expect(textOf(7, words: 'a', plate: plate), text);
      expect(textOf(8, words: 'a', plate: plate), isNot(text));
      expect(textOf(7, words: 'b', plate: plate), isNot(text));
      expect(
        textOf(
          7,
          words: 'a',
          plate: {
            coord: tileOf({
              (0, 0): [10, 20, 31, 255],
            }),
          },
        ),
        isNot(text),
      );
      expect(textOf(7, words: 'a'), isNot(text));
    });

    test('reads back from JSON with its plate', () {
      final text = textOf(7, words: 'a', plate: plate);

      expect(CelText.fromJson(throughJson(text.toJson())), text);
    });

    test('the next id is one past the largest there is', () {
      expect(nextCelTextId(const []), 1);
      expect(nextCelTextId([textOf(4), textOf(2)]), 5);
    });
  });
}
