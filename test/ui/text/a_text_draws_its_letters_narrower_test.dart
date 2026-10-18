import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter/painting.dart' show TextPosition;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_faces.dart';

/// text-letters-lean-and-underline ⑥ (Q1, 유저 2026-10-17 「일곱 전부」: 「글자
/// 폭(%) — 클튜처럼 글 전체에 하나(상자의 값)」): a text's letters DRAWN
/// narrower or wider — 장평, [CelTextContent.letterWidth].
///
/// Only their width changes. A line of them is that much shorter or longer
/// and stands about its anchor as its alignment says; its height and the
/// pitch of its lines stay; a box keeps its width and holds more or fewer
/// of them a line; and the caret, a selection and a press are where the
/// letters are DRAWN.
///
/// ⚠️The numbers are the TEST FONT's: every glyph a box one letter-size
/// wide and tall, so 「abc」 at size 20 with a line pitch of 1 is 60 by 20.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CelTextContent said(
    String words, {
    double width = 1,
    TextCelAlign align = TextCelAlign.left,
    double? wrapWidth,
    double x = 0,
    double y = 0,
    TextLetterStyle style = const TextLetterStyle(fontSize: 20),
  }) => CelTextContent(
    spans: [CelTextSpan(text: words, style: style)],
    anchor: CanvasPoint(x: x, y: y),
    wrapWidth: wrapWidth,
    align: align,
    lineHeight: 1,
    letterWidth: width,
  );

  CelTextLayout set(CelTextContent content) {
    final layout = layoutCelText(content);
    addTearDown(layout.dispose);
    return layout;
  }

  group('a text that grows', () {
    test('is as wide as its letters are DRAWN, about its anchor as its '
        'alignment says', () {
      for (final (align, left) in [
        (TextCelAlign.left, 0.0),
        (TextCelAlign.center, -15.0),
        (TextCelAlign.right, -30.0),
      ]) {
        expect(
          set(said('abc', width: 0.5, align: align)).block,
          ui.Rect.fromLTWH(left, 0, 30, 20),
          reason: align.name,
        );
      }
      expect(
        set(said('abc', width: 1.5)).block,
        const ui.Rect.fromLTWH(0, 0, 90, 20),
      );
    });

    test('only their WIDTH changes: a line is as tall, and the next one as '
        'far down', () {
      final half = set(said('ab\ncde', width: 0.5));

      expect(half.block, const ui.Rect.fromLTWH(0, 0, 30, 40));
      expect(
        half.caretRect(const TextPosition(offset: 3)),
        const ui.Rect.fromLTWH(0, 20, 0, 20),
      );
    });
  });

  group('a text in a box', () {
    test('keeps the box\'s width and holds MORE letters a line', () {
      // 「ab cd ef gh」 in a box 115 wide: at its letters' own width it
      // breaks after 「cd 」; at half of it the whole — 110 — is one line.
      final whole = set(said('ab cd ef gh', wrapWidth: 115));
      final half = set(said('ab cd ef gh', wrapWidth: 115, width: 0.5));

      expect(whole.wrapPlaces, [6], reason: '⛔control');
      expect(half.wrapPlaces, isEmpty);
      expect(half.block, const ui.Rect.fromLTWH(0, 0, 115, 20));
    });

    test('and FEWER where they are drawn wider', () {
      // At twice their width the box is 57.5 of their own: two letters.
      final wide = set(said('abc', wrapWidth: 115, width: 2));

      expect(wide.wrapPlaces, [2]);
      expect(wide.block, const ui.Rect.fromLTWH(0, 0, 115, 40));
    });
  });

  group('the caret, a selection and a press', () {
    test('are where the letters are DRAWN', () {
      final half = set(said('abc', width: 0.5, x: 10, y: 5));

      expect(
        half.caretRect(const TextPosition(offset: 2)),
        const ui.Rect.fromLTWH(20, 0, 0, 20),
      );
      expect(half.selectionRects(0, 2), [const ui.Rect.fromLTWH(0, 0, 20, 20)]);
      // The letters stand 10 wide from x 10: a press goes to the nearest
      // place between two of them.
      expect(half.positionAt(const ui.Offset(14, 15)).offset, 0);
      expect(half.positionAt(const ui.Offset(16, 15)).offset, 1);
      expect(half.positionAt(const ui.Offset(31, 15)).offset, 2);
    });

    test('of a centred text', () {
      // 「abc」 drawn 30 wide about x 50: from 35 to 65.
      final half = set(
        said('abc', width: 0.5, x: 50, align: TextCelAlign.center),
      );

      expect(half.caretRect(const TextPosition(offset: 1)).left, -5);
      expect(half.positionAt(const ui.Offset(36, 10)).offset, 0);
      expect(half.positionAt(const ui.Offset(64, 10)).offset, 3);
    });
  });

  // 🗣️Q3 (유저 2026-10-18): 「글자만 좁아지고 열 간격은 그대로」.
  group('🚨written in COLUMNS: each letter narrower IN ITS PLACE, the '
      'columns where they stand', () {
    // 「X」 and 「Y」 a column each, lying down it — solid boxes in the test
    // font, where 「あ」 is a hollow one — at 20: the first from 80 to 100,
    // the second from 60 to 80; each letter, at half its width, 10 wide
    // about its column's middle.
    CelTextContent columns(
      String words, {
      double width = 1,
      TextLetterStyle style = const TextLetterStyle(fontSize: 20),
    }) => CelTextContent(
      spans: [CelTextSpan(text: words, style: style)],
      anchor: CanvasPoint(x: 100, y: 10),
      lineHeight: 1,
      vertical: true,
      letterWidth: width,
    );

    /// The columns of pixels [content] inks on the row [y].
    Future<List<int>> inkedAcross(CelTextContent content, int y) async {
      final recorder = ui.PictureRecorder();
      set(content).paint(ui.Canvas(recorder));
      final picture = recorder.endRecording();
      final image = await picture.toImage(120, 60);
      picture.dispose();
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      image.dispose();
      return [
        for (var x = 0; x < 120; x += 1)
          if (bytes[(y * 120 + x) * 4 + 3] > 128) x,
      ];
    }

    List<int> from(int left, int right) => [
      for (var x = left; x < right; x += 1) x,
    ];

    test('drawn', () async {
      expect(await inkedAcross(columns('X\nY', width: 0.5), 20), [
        ...from(65, 75),
        ...from(85, 95),
      ]);
      expect(
        await inkedAcross(columns('X\nY'), 20),
        from(60, 100),
        reason: '⛔control: at their own width they fill their columns',
      );
    });

    test('nothing else moves: the block, a letter\'s place, the caret', () {
      final narrow = set(columns('あい\nう', width: 0.5));
      final own = set(columns('あい\nう'));

      expect(narrow.block, own.block);
      expect(narrow.selectionRects(1, 2), own.selectionRects(1, 2));
      expect(
        narrow.caretRect(const TextPosition(offset: 3)),
        own.caretRect(const TextPosition(offset: 3)),
      );
    });

    test('a line beside the letters hugs them as they are drawn', () async {
      // 「X」 at half its width runs to 95: its side line from there.
      final lined = await inkedAcross(
        columns(
          'X',
          width: 0.5,
          style: const TextLetterStyle(fontSize: 20, underline: true),
        ),
        20,
      );

      expect(lined, [...from(85, 95), 95]);
    });

    test('🚨a press between two digits set side by side finds them where '
        'they are drawn', () {
      // 「12」 is one cell: 40 set, fitted to its column at half — so half a
      // letter tall, 10 to 20 — and drawn half as wide again: 10 wide about
      // 90. Three before its middle is nearer its start than its middle; at
      // its own width it was not.
      int pressedAt(double width) => set(
        columns('12', width: width),
      ).positionAt(const ui.Offset(87, 15)).offset;

      expect(pressedAt(0.5), 0);
      expect(pressedAt(1), 1, reason: '⛔control');
    });
  });

  group('what is drawn', () {
    const width = 400;
    const height = 120;

    setUpAll(() async {
      await loadTheAppFaces();
    });

    Future<Uint8List> drawn(void Function(ui.Canvas canvas) paint) async {
      final recorder = ui.PictureRecorder();
      paint(ui.Canvas(recorder));
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      picture.dispose();
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      image.dispose();
      return bytes;
    }

    /// [content] drawn as its letters are set ([CelTextLayout.paint]).
    Future<Uint8List> asSet(CelTextContent content) =>
        drawn(set(content).paint);

    /// [content] at its letters' OWN width, drawn through a canvas squeezed
    /// to [letterWidth] about its anchor — and a box [letterWidth] times as
    /// wide as its own, so that it breaks its lines where [content] does.
    Future<Uint8List> squeezed(CelTextContent content) {
      final own = content.copyWith(
        letterWidth: 1,
        wrapWidth: content.wrapWidth == null
            ? null
            : content.wrapWidth! / content.letterWidth,
      );
      return drawn((canvas) {
        final anchor = content.anchor;
        canvas
          ..translate(anchor.x, anchor.y)
          ..scale(content.letterWidth, 1)
          ..translate(-anchor.x, -anchor.y);
        set(own).paint(canvas);
      });
    }

    // The letters with lines under and through them, one run of them hard:
    // every pass a text has, lines in each.
    const lined = TextLetterStyle(
      fontFamily: 'BIZ UDPGothic',
      fontSize: 28,
      color: 0xFFC80A14,
      underline: true,
      strikethrough: true,
    );
    final mixed = [
      const CelTextSpan(text: 'Abg 가나', style: lined),
      CelTextSpan(
        text: ' 漢字',
        style: lined.copyWith(color: 0xFF0A14C8, antialias: false),
      ),
    ];

    for (final width in [0.5, 1.5]) {
      for (final align in TextCelAlign.values) {
        for (final wrapWidth in [null, 230.0]) {
          final named =
              '${width * 100}%, ${align.name}, '
              '${wrapWidth == null ? 'growing' : 'in a box'}';

          test('🚨the letters and their lines, smooth and hard, are what the '
              'text at their own width draws through a canvas squeezed to '
              'that width about its anchor ($named)', () async {
            final content = CelTextContent(
              spans: mixed,
              anchor: CanvasPoint(x: 200.25, y: 20.5),
              wrapWidth: wrapWidth,
              align: align,
              lineHeight: 1.2,
              letterWidth: width,
            );

            final narrowed = await asSet(content);
            final control = await asSet(content.copyWith(letterWidth: 1));

            expect(narrowed, await squeezed(content));
            expect(
              narrowed,
              isNot(control),
              reason: '⛔control: at its own width it draws otherwise',
            );
          });
        }
      }
    }

    test('🚨nothing is drawn past where its pixels can be, drawn four times '
        'as wide', () async {
      // An outline wider than the letter: it reaches past the letter's box
      // farther than the letter is tall once it is drawn four times as wide.
      final content = CelTextContent(
        spans: [
          CelTextSpan(
            text: 'W',
            style: lined.copyWith(
              italic: true,
              outlineColor: 0xFF000000,
              outlineWidth: 40,
            ),
          ),
        ],
        anchor: CanvasPoint(x: 100, y: 40),
        lineHeight: 1.2,
        letterWidth: 4,
      );
      final layout = set(content);
      final bytes = await drawn(layout.paint);
      final room = layout.inkBounds;

      var inked = 0;
      for (var at = 0; at < bytes.length; at += 4) {
        if (bytes[at + 3] == 0) {
          continue;
        }
        inked += 1;
        final x = (at ~/ 4) % width;
        final y = (at ~/ 4) ~/ width;
        expect(
          room.contains(ui.Offset(x + 0.5, y + 0.5)),
          isTrue,
          reason: '($x, $y) is outside $room',
        );
      }
      expect(inked, greaterThan(0), reason: '⛔fixture: it draws');
    });
  });

  group('🚨a hard pass', () {
    test('is cut two units clear of what its letters can draw IN THE '
        'CANVAS\'S PIXELS at every width: the letters are narrowed inside '
        'the cut, not the cut with them', () {
      CelTextLayout ab(double width) => set(
        said(
          'ab',
          width: width,
          style: const TextLetterStyle(
            fontSize: 10,
            antialias: false,
            outlineColor: 0xFF0000FF,
            outlineWidth: 4,
          ),
        ),
      );
      // ⚠️Read off the letters at their own width, not the test font's
      // numbers: the faces [loadTheAppFaces] brought in above stay for the
      // rest of the file, and the default face is one of them by now.
      final own = ab(1).block;

      for (final (width, reach) in [(0.5, 10.0 + 2), (1.5, (10.0 + 2) * 1.5)]) {
        final layout = ab(width);
        final canvas = _CutsWhereTheyFall();
        layout.paint(canvas);

        expect(
          layout.block,
          ui.Rect.fromLTRB(0, 0, own.right * width, own.bottom),
        );
        expect(canvas.cuts, hasLength(2), reason: 'the outline, the fill');
        expect(
          canvas.cuts.toSet(),
          {layout.block.inflate(reach).inflate(2)},
          reason: '${width * 100}%',
        );
      }
    });
  });
}

/// A canvas that keeps the rects it was cut at WHERE THEY FALL on it —
/// through the widths it was scaled by along x, the one turn a text in
/// lines makes of its own frame here — and draws nothing.
class _CutsWhereTheyFall implements ui.Canvas {
  final List<double> _widths = [1];
  final List<ui.Rect> cuts = [];

  @override
  void save() => _widths.add(_widths.last);

  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) => _widths.add(_widths.last);

  @override
  void restore() => _widths.removeLast();

  @override
  void scale(double sx, [double? sy]) =>
      _widths[_widths.length - 1] = _widths.last * sx;

  @override
  void clipRect(
    ui.Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) {
    final width = _widths.last;
    cuts.add(
      ui.Rect.fromLTRB(
        rect.left * width,
        rect.top,
        rect.right * width,
        rect.bottom,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
