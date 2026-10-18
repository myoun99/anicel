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
    expect(
      text.content.paragraphs,
      List.filled(
        2,
        const CelTextParagraph(align: TextCelAlign.left, lineHeight: 1.2),
      ),
      reason: 'CLIP STUDIO\'s own spacing where the text names none',
    );
    expect(text.content.anchor.x, 15);
    expect(
      text.content.anchor.y,
      closeTo(27 - (1.2 - 1) * 24 / 2, 1e-9),
      reason: 'the line\'s top, half its leading over the letters\' box',
    );
    expect(text.content.wrapWidth, isNull, reason: 'it breaks where typed');
    expect(
      (
        text.content.rotationDegrees,
        text.content.vertical,
        text.content.letterWidth,
      ),
      (0, false, 1),
      reason: 'upright, across, its letters as wide as they are',
    );
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

  group('each paragraph is set as most of its letters say', () {
    List<(TextCelAlign, double)> setOf(
      String text,
      List<ClipTextFlagSpec> aligns, {
      List<({int start, int length, double spacing})> spacings = const [],
      int? textAlign,
    }) => [
      for (final paragraph in read(
        textLayer([
          lettering(
            text,
            clipTextAttributesBytes(
              aligns: aligns,
              spacings: spacings,
              textAlign: textAlign,
            ),
          ),
        ]),
      ).texts.single.content.paragraphs)
        (paragraph.align, paragraph.lineHeight),
    ];

    test('a paragraph runs from one break to the next, its break with it — '
        'a CR LF one break, and a CR or an LF alone one', () {
      expect(
        setOf(
          'a\r\nbc\rde\nf',
          [
            // The letter is centred, its CR LF right: two units to one.
            (start: 0, length: 1, value: 2),
            (start: 1, length: 2, value: 1),
            (start: 3, length: 3, value: 2),
            (start: 6, length: 3, value: 0),
            (start: 9, length: 1, value: 1),
          ],
          spacings: [
            (start: 0, length: 3, spacing: 100),
            (start: 3, length: 3, spacing: 150),
            (start: 6, length: 3, spacing: 200),
            (start: 9, length: 1, spacing: 250),
          ],
        ),
        [
          (TextCelAlign.right, 1.0),
          (TextCelAlign.center, 1.5),
          (TextCelAlign.left, 2.0),
          (TextCelAlign.right, 2.5),
        ],
      );
    });

    test('of two, the one most of its letters take; of two alike, the '
        'smaller', () {
      expect(
        setOf('abcd', [
          (start: 0, length: 3, value: 2),
          (start: 3, length: 1, value: 1),
        ]).single.$1,
        TextCelAlign.center,
      );
      expect(
        setOf('abcd', [
          (start: 0, length: 2, value: 1),
          (start: 2, length: 2, value: 2),
        ]).single.$1,
        TextCelAlign.right,
        reason: '1 is the smaller of the two values',
      );
      expect(
        setOf(
          'abcd',
          const [],
          spacings: [
            (start: 0, length: 1, spacing: 200),
            (start: 1, length: 3, spacing: 100),
          ],
        ).single.$2,
        1.0,
      );
    });

    test('one no stretch covers is aligned as the text says, at CLIP '
        'STUDIO\'s own spacing', () {
      expect(
        setOf(
          'ab\r\ncd',
          [(start: 0, length: 4, value: 2)],
          spacings: [(start: 0, length: 4, spacing: 150)],
          textAlign: 1,
        ),
        [(TextCelAlign.center, 1.5), (TextCelAlign.right, 1.2)],
      );
    });

    test('a last one with no letters is set as the one before it', () {
      expect(
        setOf(
          'ab\r\n',
          [(start: 0, length: 4, value: 2)],
          spacings: [(start: 0, length: 4, spacing: 150)],
          textAlign: 1,
        ),
        List.filled(2, (TextCelAlign.center, 1.5)),
      );
    });
  });

  group('it stands by its first paragraph where its box does', () {
    ({double x, double y}) anchorOf(
      List<ClipTextFlagSpec> aligns, {
      List<({int start, int length, double spacing})> spacings = const [],
    }) {
      final anchor = read(
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
      ).texts.single.content.anchor;
      return (x: anchor.x, y: anchor.y);
    }

    test('centred about the box\'s middle, right at its right end — as its '
        'first paragraph is, whatever the next', () {
      expect(
        anchorOf([
          (start: 0, length: 5, value: 2),
          (start: 5, length: 3, value: 1),
        ]),
        (x: 130.0, y: 50 - (1.2 - 1) * 24 / 2),
      );
      expect(
        anchorOf([
          (start: 0, length: 5, value: 1),
          (start: 5, length: 3, value: 0),
        ]).x,
        160.0,
      );
    });

    test('a spacing is the pitch, and its leading stands half above', () {
      expect(
        anchorOf(
          const [],
          spacings: [
            (start: 0, length: 5, spacing: 150),
            (start: 5, length: 3, spacing: 300),
          ],
        ).y,
        50 - 0.5 * 24 / 2,
      );
    });
  });

  test('🎯what the app cannot set is said by the layer\'s name, once a layer '
      'however many of its texts it is true of — two alignments or two '
      'spacings in one paragraph, a frame not square', () {
    // Its top edge runs straight across, and its left edge leans.
    final slanted = [0, 0, 1000, 0, 1200, 1000, 200, 1000];
    final result = read(
      textLayer([
        for (var i = 0; i < 2; i += 1)
          lettering(
            // Two in the first paragraph, one in the second.
            'abcd\r\nef',
            clipTextAttributesBytes(
              aligns: [
                (start: 0, length: 2, value: 0),
                (start: 2, length: 4, value: 2),
                (start: 6, length: 2, value: 1),
              ],
              spacings: [
                (start: 0, length: 2, spacing: 120),
                (start: 2, length: 4, spacing: 140),
                (start: 6, length: 2, spacing: 200),
              ],
              corners: slanted,
            ),
          ),
      ]),
    );

    expect(keysOf(result.warnings), [
      'clipTextAlign',
      'clipTextSpacing',
      'clipTextDistorted',
    ]);
    expect({for (final w in result.warnings) w.values['name']}, {'words'});
    expect(result.texts, hasLength(2), reason: 'both still come in');
  });

  test('a frame flipped is not square; one only turned is', () {
    List<String> keysFor(List<int> corners) => keysOf(
      read(
        textLayer([
          lettering('a', clipTextAttributesBytes(corners: corners)),
        ]),
      ).warnings,
    );

    expect(keysFor([1000, 0, 0, 0, 0, 1000, 1000, 1000]), [
      'clipTextDistorted',
    ]);
    expect(keysFor([0, 0, 1000, 500, 500, 1500, -500, 1000]), isEmpty);
  });

  test('⛔what the file writes as set to nothing, or as the same, is not '
      'said — an underline of 0, one alignment, an even spacing that differs '
      'in its last bits, a width of 100, and two paragraphs each aligned '
      'and spaced its own way', () {
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
        lettering(
          'ab\r\ncd',
          clipTextAttributesBytes(
            aligns: [
              (start: 0, length: 4, value: 2),
              (start: 4, length: 2, value: 1),
            ],
            spacings: [
              (start: 0, length: 4, spacing: 120),
              (start: 4, length: 2, spacing: 200),
            ],
          ),
        ),
        // A last paragraph with no letters is set as the one before it, so
        // what the text says it is aligned is never read.
        lettering(
          'ab\r\n',
          clipTextAttributesBytes(
            aligns: [(start: 0, length: 4, value: 2)],
            textAlign: 3,
          ),
        ),
      ]),
    );

    expect(result.warnings, isEmpty);
    expect(
      [
        for (final span in result.texts.first.content.spans)
          (span.style.underline, span.style.strikethrough),
      ],
      [(false, false)],
    );
  });

  test('🎯what CLIP STUDIO sets the app now sets too — letters leaning, '
      'lined under and through, drawn narrower — and says nothing of it', () {
    final result = read(
      textLayer([
        lettering(
          'abcd',
          clipTextAttributesBytes(
            runs: [
              (
                start: 0,
                length: 2,
                bold: false,
                italic: true,
                colour: null,
                scale: null,
                face: '',
              ),
            ],
            underlines: [(start: 1, length: 2, value: 1)],
            strikes: [(start: 2, length: 2, value: 1)],
            across: 99.48,
          ),
        ),
      ]),
    );

    final content = result.texts.single.content;
    expect(
      [
        for (final span in content.spans)
          (
            span.text,
            span.style.italic,
            span.style.underline,
            span.style.strikethrough,
          ),
      ],
      [
        ('a', true, false, false),
        ('b', true, true, false),
        ('c', false, true, true),
        ('d', false, false, true),
      ],
    );
    expect(content.letterWidth, closeTo(0.9948, 1e-12));
    expect(result.warnings, isEmpty);
  });

  test('an alignment of a kind the app does not know is said, and set '
      'left — its paragraph\'s, or the text\'s where none covers it', () {
    for (final attributes in [
      clipTextAttributesBytes(aligns: [(start: 0, length: 2, value: 3)]),
      clipTextAttributesBytes(textAlign: 3),
    ]) {
      final result = read(textLayer([lettering('ab', attributes)]));

      expect(keysOf(result.warnings), ['clipTextAlign']);
      expect(
        result.texts.single.content.paragraphs.single.align,
        TextCelAlign.left,
      );
    }
  });

  test('a run or a line that runs past the text\'s ends sets only the '
      'letters it covers', () {
    final spans = read(
      textLayer([
        lettering(
          'ab',
          clipTextAttributesBytes(
            runs: [
              (
                start: -1,
                length: 2,
                bold: true,
                italic: false,
                colour: null,
                scale: null,
                face: '',
              ),
            ],
            underlines: [(start: 1, length: 9, value: 1)],
          ),
        ),
      ]),
    ).texts.single.content.spans;

    expect(
      [
        for (final span in spans)
          (span.text, span.style.bold, span.style.underline),
      ],
      [('a', true, false), ('b', false, true)],
    );
  });

  test('a parameter shorter than its numbers is read as one not there — '
      'corners too few stand the text upright at its box', () {
    final text = read(
      textLayer([
        lettering(
          'a',
          Uint8List.fromList([
            ...clipTextAttributesBytes(
              box: (x0: 10, y0: 20, x1: 40, y1: 44),
              withCorners: false,
            ),
            // Parameter 64, sixteen bytes long: four of its eight numbers.
            ...[64, 0, 0, 0, 16, 0, 0, 0],
            ...List.filled(16, 1),
          ]),
        ),
      ]),
    );

    expect(text.warnings, isEmpty);
    expect(
      (
        text.texts.single.content.anchor.x,
        text.texts.single.content.rotationDegrees,
      ),
      (10, 0),
    );
  });

  test('a width is a share of the letters\' own — and one that is none, '
      'their own', () {
    double widthOf(double across) => read(
      textLayer([lettering('a', clipTextAttributesBytes(across: across))]),
    ).texts.single.content.letterWidth;

    expect(widthOf(150), 1.5);
    expect(widthOf(0), 1);
    expect(widthOf(-20), 1);
    expect(widthOf(double.nan), 1);
    expect(widthOf(double.infinity), 1);
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

  group('🎯turned and in columns it stands where CLIP STUDIO set it — '
      'pinned to the person\'s sample (F-370-Q4, 10-18; its numbers only: '
      'where each picture stands is where the sample\'s PNG shows it)', () {
    // 15 pt at 144 dpi: 30 px letters, a 3 px half-leading at 120 %.
    ClipCelText textOf({
      required ({int x0, int y0, int x1, int y1}) box,
      required ({int width, int height}) boxSize,
      required List<int> corners,
      required (int, int)? offset,
      required List<ClipPictureSource> pictures,
      int align = 0,
      int textFlags = 0,
    }) => read(
      textLayer(
        [
          lettering(
            'ab\r\ncd',
            clipTextAttributesBytes(
              box: box,
              boxSize: boxSize,
              points: 15,
              corners: corners,
              pictureOffset: offset,
              aligns: [(start: 0, length: 6, value: align)],
              textFlags: textFlags,
            ),
          ),
        ],
        pictures: pictures,
      ),
      resolution: 144,
    ).texts.single;

    void expectStands(
      ClipCelText text, {
      required String picture,
      required (int, int) at,
      required (double, double) anchor,
      required double turn,
      required bool vertical,
    }) {
      expect(text.picture?.blocksId, picture);
      expect((text.left, text.top), at);
      expect(text.content.anchor.x, closeTo(anchor.$1, 1e-6));
      expect(text.content.anchor.y, closeTo(anchor.$2, 1e-6));
      expect(text.content.rotationDegrees, closeTo(turn, 1e-6));
      expect(text.content.vertical, vertical);
    }

    const acrossBox = (x0: 402, y0: 259, x1: 512, y1: 325);
    const acrossSize = (width: 110, height: 70);
    const turnedAcross = [-185, 354, 9569, 5439, 6518, 11292, -3236, 6207];
    const columnsBox = (x0: 402, y0: 259, x1: 469, y1: 416);
    const columnsSize = (width: 67, height: 157);
    const turnedColumns = [-5521, -3618, 83, 54, -8522, 13186, -14126, 9514];

    test('across, upright: at its box, the line\'s top half the leading '
        'above it', () {
      expectStands(
        textOf(
          box: acrossBox,
          boxSize: acrossSize,
          corners: const [0, 400, 11000, 400, 11000, 7000, 0, 7000],
          offset: (0, -4),
          pictures: [pictureOf(111, 71, 'upright')],
        ),
        picture: 'upright',
        at: (402, 259),
        anchor: (402, 256),
        turn: 0,
        vertical: false,
      );
    });

    test('across, turned: its picture where the frame\'s origin says, and '
        'its anchor turned with the frame — left, centred or right', () {
      for (final (align, anchor) in [
        (0, (424.537723, 233.886736)),
        (2, (473.308178, 259.311973)),
        (1, (522.078633, 284.737210)),
      ]) {
        expectStands(
          textOf(
            box: acrossBox,
            boxSize: acrossSize,
            corners: turnedAcross,
            offset: (35, -4),
            pictures: [pictureOf(131, 113, 'turned')],
            align: align,
          ),
          picture: 'turned',
          at: (390, 237),
          anchor: anchor,
          turn: 27.534139,
          vertical: false,
        );
      }
      expectStands(
        textOf(
          box: (x0: 402, y0: 259, x1: 513, y1: 325),
          boxSize: (width: 111, height: 70),
          corners: const [-185, 354, 9657, 5485, 6607, 11338, -3236, 6207],
          offset: (35, -4),
          pictures: [pictureOf(132, 114, 'leaning')],
          align: 1,
        ),
        picture: 'leaning',
        at: (391, 237),
        anchor: (523.964854, 285.200453),
        turn: 27.534704,
        vertical: false,
      );
    });

    test('in columns: at its first column\'s right, half the leading past '
        'its letters — at its head, middle or foot, upright or turned', () {
      for (final (align, upright, turned) in [
        (0, (471.0, 259.0), (508.509298, 290.644208)),
        (2, (471.0, 337.5), (465.485845, 356.304185)),
        (1, (471.0, 416.0), (422.462392, 421.964161)),
      ]) {
        expectStands(
          textOf(
            box: columnsBox,
            boxSize: columnsSize,
            corners: const [-6600, 0, 100, 0, 100, 15700, -6600, 15700],
            offset: (66, 0),
            pictures: [pictureOf(68, 158, 'upright')],
            align: align,
            textFlags: 16,
          ),
          picture: 'upright',
          at: (402, 259),
          anchor: upright,
          turn: 0,
          vertical: true,
        );
        expectStands(
          textOf(
            box: columnsBox,
            boxSize: columnsSize,
            corners: turnedColumns,
            offset: (142, 36),
            pictures: [pictureOf(144, 169, 'turned')],
            align: align,
            textFlags: 16,
          ),
          picture: 'turned',
          at: (364, 253),
          anchor: turned,
          turn: 33.234671,
          vertical: true,
        );
      }
    });

    test('parameter 33 writes it in columns by its 16 — its 1 and 2 are '
        'bold and italic', () {
      bool verticalOf(int flags) => textOf(
        box: acrossBox,
        boxSize: acrossSize,
        corners: const [0, 400, 11000, 400, 11000, 7000, 0, 7000],
        offset: null,
        pictures: const [],
        textFlags: flags,
      ).content.vertical;

      expect(verticalOf(1 | 2), isFalse);
      expect(verticalOf(16 | 1 | 2), isTrue);
    });

    test('a turned text\'s picture is the one nearest its box turned, '
        'within a pixel and a half', () {
      String? pictureAmong(List<ClipPictureSource> pictures) => textOf(
        box: acrossBox,
        boxSize: acrossSize,
        corners: turnedAcross,
        offset: (35, -4),
        pictures: pictures,
      ).picture?.blocksId;

      // Its box turned is 130.90 × 113.92: 'nearer' is 0.92 off, 'farther'
      // 1.10 — whichever the file holds first.
      expect(
        pictureAmong([
          pictureOf(111, 71, 'the box upright'),
          pictureOf(133, 113, 'two off'),
          pictureOf(132, 115, 'farther'),
          pictureOf(131, 113, 'nearer'),
        ]),
        'nearer',
      );
      expect(
        pictureAmong([
          pictureOf(131, 113, 'nearer'),
          pictureOf(132, 115, 'farther'),
        ]),
        'nearer',
      );
      expect(pictureAmong([pictureOf(131, 116, 'two off')]), isNull);
    });

    test('one that does not say where its picture stands is set by the '
        'app — its picture taken out all the same, and not another\'s', () {
      final attributes = [
        for (final offset in [null, (35, -4)])
          clipTextAttributesBytes(
            box: acrossBox,
            boxSize: acrossSize,
            points: 15,
            corners: turnedAcross,
            pictureOffset: offset,
          ),
      ];
      final result = read(
        textLayer(
          [
            lettering('a', attributes.first),
            lettering('b', attributes.last),
          ],
          pictures: [
            pictureOf(131, 113, 'first'),
            pictureOf(131, 113, 'second'),
          ],
        ),
        resolution: 144,
      );

      expect(
        [for (final text in result.texts) text.picture?.blocksId],
        [null, 'second'],
      );
    });

    test('upright, it stands at its box wherever its frame\'s origin is — '
        'one that names no offset, or no corners, too', () {
      for (final (corners, withCorners) in [
        (const [0, 400, 11000, 400, 11000, 7000, 0, 7000], true),
        // The box's own square, measured from the canvas's top-left.
        (null, true),
        (null, false),
      ]) {
        final text = read(
          textLayer(
            [
              lettering(
                'a',
                clipTextAttributesBytes(
                  box: acrossBox,
                  boxSize: acrossSize,
                  points: 15,
                  corners: corners,
                  withCorners: withCorners,
                ),
              ),
            ],
            pictures: [pictureOf(111, 71, 'upright')],
          ),
          resolution: 144,
        ).texts.single;
        expect(
          (text.picture?.blocksId, text.left, text.top),
          ('upright', 402, 259),
        );
        expect(text.content.anchor.x, 402);
        expect(text.content.anchor.y, closeTo(256, 1e-9));
      }
    });
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
