import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/import/import_warning.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/import/clip_document.dart';
import 'package:anicel/src/services/import/clip_lettering.dart';

import 'clip_test_builder.dart';

/// F-370-Q3 (유저 2026-10-17: 「이제 들인다(앱의 글자로)」): a CLIP STUDIO
/// text layer's texts as the app's own, read from their attribute
/// parameters the way the format notes lay them out (memory
/// `csp-clip-format-notes` 6-1 §13 — the samples are work files and stay
/// out of the repository).
void main() {
  ClipLayer textLayer(
    List<ClipLettering> texts, {
    List<ClipPictureSource> pictures = const [],
    int offsetX = 0,
    int offsetY = 0,
  }) => ClipLayer(
    id: 7,
    name: 'words',
    kind: ClipLayerKind.lettering,
    visibility: 1,
    opacity: 256,
    composite: 0,
    folderFlags: 0,
    isAnimationFolder: false,
    uuid: 'uuid7',
    left: 0,
    top: 0,
    offsetX: offsetX,
    offsetY: offsetY,
    render: null,
    original: null,
    originalTransform: null,
    texts: texts,
    textPictures: pictures,
    children: const [],
  );

  ClipLettering lettering(String text, Uint8List attributes) =>
      (text: text, attributes: attributes);

  ({List<ClipCelText> texts, List<ImportWarning> warnings}) read(
    ClipLayer layer, {
    double resolution = 72,
    double alpha = 1,
  }) {
    final warnings = <ImportWarning>[];
    final texts = clipCelTextsOf(
      layer,
      resolution: resolution,
      name: 'words',
      warnings: warnings,
      alpha: alpha,
    );
    return (texts: texts, warnings: warnings);
  }

  List<String> keysOf(List<ImportWarning> warnings) => [
    for (final warning in warnings) warning.key,
  ];

  ClipPictureSource pictureOf(int width, int height, String blocks) =>
      ClipPictureSource(
        attribute: offscreenAttributeBytes(
          width: width,
          height: height,
          columns: 1,
          rows: 1,
        ),
        blocksId: blocks,
      );

  test('🎯a text comes in as the app\'s own — what it says, a CR LF one '
      'break, in its face, at its size on THIS canvas and in its colour, '
      'standing where its box does on the layer', () {
    final result = read(
      textLayer([
        lettering(
          'Hi\r\nyo',
          clipTextAttributesBytes(
            box: (x0: 10, y0: 20, x1: 110, y1: 44),
            points: 12,
            colour: (200, 0, 0),
          ),
        ),
      ], offsetX: 5, offsetY: 7),
      // Two pixels a point.
      resolution: 144,
    );

    final text = result.texts.single;
    expect(text.content.text, 'Hi\nyo');
    expect(text.content.spans.single.style, const TextLetterStyle(
      fontFamily: 'Face',
      fontSize: 24,
      color: 0xFFC80000,
    ));
    expect((text.left, text.top), (15, 27), reason: 'box + layer offset');
    expect(text.content.align, TextCelAlign.left);
    expect(
      text.content.lineHeight,
      1.2,
      reason: 'CLIP STUDIO\'s own spacing where the text names none',
    );
    expect(text.content.anchor.x, 15);
    expect(
      text.content.anchor.y,
      closeTo(27 - (1.2 - 1) * 24 / 2, 1e-9),
      reason: 'the line\'s top, half its leading over the letters\' box',
    );
    expect(text.content.wrapWidth, isNull, reason: 'it breaks where typed');
    expect(text.picture, isNull, reason: 'the layer holds none');
    expect(result.warnings, isEmpty);
  });

  test('a run wears its own weight, colour, scale and face — and a letter '
      'outside the first plane is not split where a run ends', () {
    final result = read(
      textLayer([
        lettering(
          'ab\u{1F600}c',
          clipTextAttributesBytes(
            runs: [
              // 'b' and the FIRST unit of the face: two units, three letters.
              (
                start: 1,
                length: 2,
                bold: true,
                italic: false,
                colour: (0, 0, 255),
                scale: 50,
                face: 'Other',
              ),
            ],
          ),
        ),
      ]),
    );

    const base = TextLetterStyle(fontFamily: 'Face', fontSize: 12);
    const run = TextLetterStyle(
      fontFamily: 'Other',
      fontSize: 6,
      bold: true,
      color: 0xFF0000FF,
    );
    expect(
      [
        for (final span in result.texts.single.content.spans)
          (span.text, span.style),
      ],
      [('a', base), ('b\u{1F600}', run), ('c', base)],
    );
  });

  test('each of a text\'s runs is read where the one before it ends', () {
    final result = read(
      textLayer([
        lettering(
          'abcd',
          clipTextAttributesBytes(
            runs: [
              (
                start: 0,
                length: 1,
                bold: true,
                italic: false,
                colour: null,
                scale: null,
                face: 'One',
              ),
              (
                start: 2,
                length: 2,
                bold: false,
                italic: false,
                colour: (255, 0, 0),
                scale: null,
                face: 'Second',
              ),
            ],
          ),
        ),
      ]),
    );

    expect(
      [
        for (final span in result.texts.single.content.spans)
          (span.text, span.style),
      ],
      [
        (
          'a',
          const TextLetterStyle(fontFamily: 'One', fontSize: 12, bold: true),
        ),
        ('b', const TextLetterStyle(fontFamily: 'Face', fontSize: 12)),
        (
          'cd',
          const TextLetterStyle(
            fontFamily: 'Second',
            fontSize: 12,
            color: 0xFFFF0000,
          ),
        ),
      ],
    );
  });

  test('a run with no colour, scale or face of its own takes the text\'s', () {
    final result = read(
      textLayer([
        lettering(
          'xy',
          clipTextAttributesBytes(
            colour: (0, 128, 0),
            runs: [
              (
                start: 0,
                length: 1,
                bold: true,
                italic: false,
                colour: null,
                scale: null,
                face: '',
              ),
            ],
          ),
        ),
      ]),
    );

    expect(result.texts.single.content.spans.first.style, const TextLetterStyle(
      fontFamily: 'Face',
      fontSize: 12,
      bold: true,
      color: 0xFF008000,
    ));
  });

  group('its lines stand as most of its letters say', () {
    ({double x, double y, TextCelAlign align, double lineHeight}) standOf(
      List<ClipTextFlagSpec> aligns, {
      List<({int start, int length, double spacing})> spacings = const [],
    }) {
      final content = read(
        textLayer([
          lettering(
            'one\r\ntwo',
            clipTextAttributesBytes(
              box: (x0: 100, y0: 50, x1: 160, y1: 74),
              points: 24,
              aligns: aligns,
              spacings: spacings,
            ),
          ),
        ]),
      ).texts.single.content;
      return (
        x: content.anchor.x,
        y: content.anchor.y,
        align: content.align,
        lineHeight: content.lineHeight,
      );
    }

    test('centred about the box\'s middle, right at its right end', () {
      expect(standOf([(start: 0, length: 8, value: 2)]), (
        x: 130.0,
        y: 50 - (1.2 - 1) * 24 / 2,
        align: TextCelAlign.center,
        lineHeight: 1.2,
      ));
      final right = standOf([(start: 0, length: 8, value: 1)]);
      expect((right.x, right.align), (160.0, TextCelAlign.right));
    });

    test('a spacing is the pitch, and its leading stands half above', () {
      final stand = standOf(
        const [],
        spacings: [(start: 0, length: 8, spacing: 150)],
      );
      expect((stand.lineHeight, stand.y), (1.5, 50 - 0.5 * 24 / 2));
    });

    test('of two, the one most letters take; of two alike, the smaller', () {
      expect(
        standOf([
          (start: 0, length: 5, value: 2),
          (start: 5, length: 3, value: 1),
        ]).align,
        TextCelAlign.center,
      );
      expect(
        standOf([
          (start: 0, length: 4, value: 1),
          (start: 4, length: 4, value: 2),
        ]).align,
        TextCelAlign.right,
        reason: '1 is the smaller of the two values',
      );
      expect(
        standOf(
          const [],
          spacings: [
            (start: 0, length: 2, spacing: 200),
            (start: 2, length: 6, spacing: 100),
          ],
        ).lineHeight,
        1.0,
      );
    });
  });

  test('🎯what the app cannot set is said by the layer\'s name, once a layer '
      'however many of its texts it is true of', () {
    final turned = [0, 0, 1000, 500, 500, 1500, -500, 1000];
    final result = read(
      textLayer([
        for (var i = 0; i < 2; i += 1)
          lettering(
            'abcd',
            clipTextAttributesBytes(
              runs: [
                (
                  start: 0,
                  length: 1,
                  bold: false,
                  italic: true,
                  colour: null,
                  scale: null,
                  face: '',
                ),
              ],
              underlines: [(start: 0, length: 4, value: 1)],
              strikes: [(start: 0, length: 4, value: 1)],
              aligns: [
                (start: 0, length: 2, value: 0),
                (start: 2, length: 2, value: 2),
              ],
              spacings: [
                (start: 0, length: 2, spacing: 120),
                (start: 2, length: 2, spacing: 140),
              ],
              across: 99.48,
              corners: turned,
            ),
          ),
      ]),
    );

    expect(keysOf(result.warnings), [
      'clipTextItalic',
      'clipTextUnderline',
      'clipTextStrike',
      'clipTextAlign',
      'clipTextSpacing',
      'clipTextAcross',
      'clipTextTurned',
    ]);
    expect({for (final w in result.warnings) w.values['name']}, {'words'});
    expect(
      result.warnings
          .singleWhere((w) => w.key == 'clipTextAcross')
          .values['percent'],
      '99.48',
    );
    expect(result.texts, hasLength(2), reason: 'both still come in');
  });

  test('⛔what the file writes as set to nothing, or as the same, is not '
      'said — an underline of 0, one alignment, an even spacing that differs '
      'in its last bits, a width of 100', () {
    final result = read(
      textLayer([
        lettering(
          'abcd',
          clipTextAttributesBytes(
            underlines: [(start: 0, length: 4, value: 0)],
            strikes: [(start: 0, length: 4, value: 0)],
            aligns: [
              (start: 0, length: 2, value: 2),
              (start: 2, length: 2, value: 2),
            ],
            spacings: [
              (start: 0, length: 2, spacing: 120),
              (start: 2, length: 2, spacing: 119.99999999999993),
            ],
          ),
        ),
      ]),
    );

    expect(result.warnings, isEmpty);
  });

  test('an alignment of a kind the app does not know is said, and set '
      'left', () {
    final result = read(
      textLayer([
        lettering(
          'ab',
          clipTextAttributesBytes(aligns: [(start: 0, length: 2, value: 3)]),
        ),
      ]),
    );

    expect(keysOf(result.warnings), ['clipTextAlign']);
    expect(result.texts.single.content.align, TextCelAlign.left);
  });

  test('a width\'s percent is said to two places, its trailing zeros '
      'dropped', () {
    String percentOf(double across) => read(
      textLayer([lettering('a', clipTextAttributesBytes(across: across))]),
    ).warnings.single.values['percent']!;

    expect(percentOf(100.5), '100.5');
    expect(percentOf(150), '150');
    expect(percentOf(99.484), '99.48');
  });

  test('a text whose setting does not read is said and left out; one that '
      'says nothing is left out quietly', () {
    final whole = clipTextAttributesBytes();
    final result = read(
      textLayer([
        // A parameter that runs past the end.
        lettering('a', Uint8List.sublistView(whole, 0, whole.length - 3)),
        lettering('b', clipTextAttributesBytes(box: null)),
        lettering('c', clipTextAttributesBytes(points: 0)),
        lettering('', clipTextAttributesBytes()),
        lettering('d', clipTextAttributesBytes()),
      ]),
    );

    expect(keysOf(result.warnings), ['clipTextUnread']);
    expect([for (final text in result.texts) text.content.text], ['d']);
  });

  test('🎯its picture is the one a pixel more each way than its box — each '
      'text its own, in the file\'s order', () {
    final attributes = clipTextAttributesBytes(
      box: (x0: 0, y0: 0, x1: 30, y1: 40),
      boxSize: (width: 30, height: 40),
    );
    final result = read(
      textLayer(
        [
          lettering('a', attributes),
          lettering('b', attributes),
          lettering('c', attributes),
        ],
        pictures: [
          pictureOf(31, 41, 'first'),
          pictureOf(30, 40, 'the box itself'),
          ClipPictureSource(
            attribute: Uint8List.fromList(utf8.encode('no picture')),
            blocksId: 'unreadable',
          ),
          pictureOf(31, 99, 'as wide, and taller'),
          pictureOf(99, 41, 'as tall, and wider'),
          pictureOf(31, 41, 'second'),
        ],
      ),
    );

    expect(
      [for (final text in result.texts) text.picture?.blocksId],
      ['first', 'second', null],
    );
  });

  test('at an opacity, every letter\'s colour is that faint', () {
    final result = read(
      textLayer([
        lettering(
          'ab',
          clipTextAttributesBytes(
            colour: (0, 0, 0),
            runs: [
              (
                start: 1,
                length: 1,
                bold: false,
                italic: false,
                colour: (255, 255, 255),
                scale: null,
                face: '',
              ),
            ],
          ),
        ),
      ]),
      alpha: 0.5,
    );

    expect(
      [
        for (final span in result.texts.single.content.spans)
          span.style.color,
      ],
      [0x80000000, 0x80FFFFFF],
    );
  });

  test('CelTextContent keeps what reads alike as one run', () {
    final result = read(
      textLayer([lettering('plain', clipTextAttributesBytes())]),
    );

    expect(result.texts.single.content.spans, [
      const CelTextSpan(
        text: 'plain',
        style: TextLetterStyle(fontFamily: 'Face', fontSize: 12),
      ),
    ]);
  });
}
