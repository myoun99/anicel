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
    });

    final changes = <String, TextLetterStyle>{
      'the face': const TextLetterStyle(fontFamily: 'Nanum Gothic'),
      'the size': const TextLetterStyle(fontSize: 12),
      'the weight': const TextLetterStyle(bold: true),
      'the tracking': const TextLetterStyle(letterSpacing: 3),
      'the colour': const TextLetterStyle(color: 0xFF112233),
      'the outline colour': const TextLetterStyle(outlineColor: 0xFFFFFFFF),
      'the outline width': const TextLetterStyle(outlineWidth: 2),
    };

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
