import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/text/canvas_letter_faces.dart';
import 'package:anicel/src/ui/text/canvas_letter_lines.dart';
import 'package:anicel/src/ui/text/canvas_letter_passes.dart';
import 'package:anicel/src/ui/text/canvas_letter_style.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:anicel/src/ui/text/text_cel_render.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_faces.dart';

/// text-letters-lean-and-underline (유저 2026-10-17: 「기울임/밑줄같은것도 어차피
/// 넣어야할 기능이니까 넣도록」, Q1 「일곱 전부」): a letter LEANS, and wears a
/// line under it or through it — set in the app's own faces, drawn as the
/// canvas draws it (`CelTextLayout.paint`, what a cel's plate is baked from).
///
/// 🚨THE LINES ARE NOT THE ENGINE'S. Its own decoration is drawn a face at a
/// time — so it stepped under the Hangul BIZ UDPGothic lacks — and is
/// neither outlined nor hard. Here a line is drawn where the engine would
/// draw it for the face that was ASKED FOR, all the way along
/// (`canvasLetterLinesOf`), in the letters' own passes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const red = 0xFFC80A14;
  const blue = 0xFF0A14C8;
  const width = 900;
  const height = 240;
  final anchor = CanvasPoint(x: 20.25, y: 20.5);

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

  CelTextContent said(
    List<CelTextSpan> spans, {
    bool vertical = false,
    double? wrapWidth,
    CanvasPoint? at,
  }) => CelTextContent(
    spans: spans,
    anchor: at ?? anchor,
    lineHeight: 1.2,
    vertical: vertical,
    wrapWidth: wrapWidth,
  );

  Future<Uint8List> textDrawn(CelTextContent content) async {
    final layout = layoutCelText(content);
    try {
      return await drawn(layout.paint);
    } finally {
      layout.dispose();
    }
  }

  /// The engine's own paragraph of [words] in [letters], WITH its own
  /// [decoration], drawn where a text in lines at [anchor] draws its
  /// letters.
  Future<Uint8List> engineDrawn(
    String words,
    TextLetterStyle letters,
    TextDecoration decoration,
  ) async {
    final painter = TextPainter(
      text: TextSpan(
        text: words,
        style: canvasLetterTextStyle(
          letters,
          lineHeight: 1.2,
        ).copyWith(decoration: decoration),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    try {
      return await drawn(
        (canvas) => painter.paint(canvas, ui.Offset(anchor.x, anchor.y)),
      );
    } finally {
      painter.dispose();
    }
  }

  /// The pixels [a] and [b] differ at, as `(x, y)`.
  Set<(int, int)> apart(Uint8List a, Uint8List b) => {
    for (var at = 0; at < a.length; at += 4)
      if (a[at] != b[at] ||
          a[at + 1] != b[at + 1] ||
          a[at + 2] != b[at + 2] ||
          a[at + 3] != b[at + 3])
        ((at ~/ 4) % width, (at ~/ 4) ~/ width),
  };

  /// The rows of [pixels] in the column [x].
  List<int> rowsAt(Set<(int, int)> pixels, int x) =>
      [
        for (final (px, py) in pixels)
          if (px == x) py,
      ]..sort();

  /// The ARGB of the pixel at ([x], [y]).
  int pixelAt(Uint8List bytes, int x, int y) {
    final at = (y * width + x) * 4;
    return bytes[at + 3] << 24 |
        bytes[at] << 16 |
        bytes[at + 1] << 8 |
        bytes[at + 2];
  }

  /// The middle of the letter at [index] of [words] in [letters], across a
  /// text in lines drawn at [anchor].
  int middleOf(String words, TextLetterStyle letters, int index) {
    final painter = TextPainter(
      text: TextSpan(
        text: words,
        style: canvasLetterTextStyle(letters, lineHeight: 1.2),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = painter.getBoxesForSelection(
      TextSelection(baseOffset: index, extentOffset: index + 1),
    ).single;
    painter.dispose();
    return (anchor.x + (box.left + box.right) / 2).floor();
  }

  CelTextSpan run(String words, TextLetterStyle letters) =>
      CelTextSpan(text: words, style: letters);

  group('a run whose face holds every one of its letters', () {
    for (final (face, words) in [
      (null, 'Abd'),
      (AppTypography.bundledFallback.single, '가나다'),
    ]) {
      for (final (name, decoration, letters) in [
        (
          'under',
          TextDecoration.underline,
          TextLetterStyle(fontFamily: face, fontSize: 64, underline: true),
        ),
        (
          'through',
          TextDecoration.lineThrough,
          TextLetterStyle(fontFamily: face, fontSize: 64, strikethrough: true),
        ),
      ]) {
        testWidgets('🚨in ${face ?? 'the app\'s first face'} wears the line '
            '$name it the engine itself would draw — to the pixel', (
          tester,
        ) async {
          await tester.runAsync(() async {
            final bare = await textDrawn(
              said([
                run(words, TextLetterStyle(fontFamily: face, fontSize: 64)),
              ]),
            );
            final ours = await textDrawn(said([run(words, letters)]));
            final engines = await engineDrawn(
              words,
              TextLetterStyle(fontFamily: face, fontSize: 64),
              decoration,
            );

            expect(apart(ours, bare), isNotEmpty, reason: 'it IS drawn');
            expect(apart(ours, engines), isEmpty);
          });
        });
      }
    }
  });

  group('🚨a run whose letters two faces set', () {
    const words = 'あア漢 가나다 Abd';
    const letters = TextLetterStyle(fontSize: 64);

    for (final (name, decoration, lined) in [
      ('under', TextDecoration.underline, letters.copyWith(underline: true)),
      (
        'through',
        TextDecoration.lineThrough,
        letters.copyWith(strikethrough: true),
      ),
    ]) {
      testWidgets('wears ONE line $name it, the face\'s it asked for, all the '
          'way along', (tester) async {
        await tester.runAsync(() async {
          final bare = await textDrawn(said([run(words, letters)]));
          final line = apart(await textDrawn(said([run(words, lined)])), bare);
          final kana = rowsAt(line, middleOf(words, letters, 0));
          final hangul = rowsAt(line, middleOf(words, letters, 4));
          final latin = rowsAt(line, middleOf(words, letters, 8));

          expect(kana, isNotEmpty);
          expect(hangul, kana);
          expect(latin, kana);

          // ⛔CONTROL: the engine's own line steps under the Hangul.
          final engines = apart(
            await engineDrawn(words, letters, decoration),
            bare,
          );
          expect(
            rowsAt(engines, middleOf(words, letters, 4)),
            isNot(rowsAt(engines, middleOf(words, letters, 0))),
            reason: '⛔fixture',
          );
        });
      });
    }
  });

  for (final (align, share) in [
    (TextCelAlign.center, 0.5),
    (TextCelAlign.right, 1.0),
  ]) {
    testWidgets('a text set to the ${align.name} wears its lines under its '
        'letters, as one set from the left does', (tester) async {
      await tester.runAsync(() async {
        const lined = TextLetterStyle(
          fontSize: 64,
          underline: true,
          strikethrough: true,
        );
        final left = said([run('Abd', lined)]);
        final layout = layoutCelText(left);
        final along = layout.block.width;
        layout.dispose();
        CelTextContent setAt(TextLetterStyle letters) => CelTextContent(
          spans: [run('Abd', letters)],
          anchor: CanvasPoint(x: anchor.x + along * share, y: anchor.y),
          lineHeight: 1.2,
          align: align,
        );
        const bare = TextLetterStyle(fontSize: 64);
        final set = await textDrawn(setAt(lined));

        expect(
          apart(set, await textDrawn(setAt(bare))),
          isNotEmpty,
          reason: 'they ARE drawn',
        );
        expect(apart(set, await textDrawn(left)), isEmpty);
      });
    });
  }

  testWidgets('🚨an outlined letter\'s line is outlined with it — outline '
      'over and under its fill', (tester) async {
    await tester.runAsync(() async {
      const letters = TextLetterStyle(
        fontSize: 64,
        color: red,
        outlineColor: blue,
        outlineWidth: 6,
      );
      const words = 'あア';
      final bare = await textDrawn(said([run(words, letters)]));
      final ours = await textDrawn(
        said([run(words, letters.copyWith(underline: true))]),
      );
      final x = middleOf(words, letters, 0);
      final down = [
        for (final y in rowsAt(apart(ours, bare), x)) pixelAt(ours, x, y),
      ];
      final fill = down.indexOf(red);

      expect(fill, isNot(-1), reason: 'its fill');
      expect(down.take(fill), contains(blue), reason: 'outlined over it');
      expect(
        down.skip(down.lastIndexOf(red)),
        contains(blue),
        reason: 'outlined under it',
      );
    });
  });

  group('a text in columns', () {
    const size = 64.0;
    final columnRight = CanvasPoint(x: 300, y: 20);
    // The column's middle, and its letters' square's right edge: a column
    // is as wide as its pitch, and the letters stand centred across it.
    const middle = 300 - size * 1.2 / 2;
    const squareRight = middle + size / 2;

    testWidgets('🚨wears its line under the letters on their RIGHT, outside '
        'their square, as thick as their face says, down the column as far '
        'as they run', (tester) async {
      await tester.runAsync(() async {
        // 나눔고딕: its underline is thinner than its strikethrough.
        final face = AppTypography.bundledFallback.single;
        final letters = TextLetterStyle(fontFamily: face, fontSize: size);
        final bare = await textDrawn(
          said([run('가나', letters)], vertical: true, at: columnRight),
        );
        final line = apart(
          await textDrawn(
            said(
              [run('가나', letters.copyWith(underline: true))],
              vertical: true,
              at: columnRight,
            ),
          ),
          bare,
        );
        final thickness =
            CanvasLetterFaces.appFaceLines[face]!.underlineThickness * size;
        final xs = {for (final (x, _) in line) x};
        final ys = {for (final (_, y) in line) y};

        expect(xs, isNotEmpty);
        expect(xs.reduce((a, b) => a < b ? a : b), squareRight.floor());
        expect(
          xs.reduce((a, b) => a > b ? a : b),
          (squareRight + thickness).ceil() - 1,
        );
        // Down both letters' places, no further.
        expect(ys.reduce((a, b) => a < b ? a : b), columnRight.y.floor());
        expect(
          ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b),
          greaterThan(size * 1.5),
        );
      });
    });

    testWidgets('wears its line through the letters down the column\'s '
        'middle', (tester) async {
      await tester.runAsync(() async {
        const letters = TextLetterStyle(fontSize: size);
        final bare = await textDrawn(
          said([run('あい', letters)], vertical: true, at: columnRight),
        );
        final line = apart(
          await textDrawn(
            said(
              [run('あい', letters.copyWith(strikethrough: true))],
              vertical: true,
              at: columnRight,
            ),
          ),
          bare,
        );
        final half =
            CanvasLetterFaces.appFaceLines[AppTypography.bundledFamily]!
                .strikethroughThickness *
            size /
            2;
        final xs = {for (final (x, _) in line) x};

        expect(xs, isNotEmpty);
        expect(
          xs.every((x) => x >= (middle - half).floor() && x < middle + half),
          isTrue,
          reason: '$xs about $middle',
        );
      });
    });

    testWidgets('leaves bare the white space a column ends with, as a line '
        'leaves it', (tester) async {
      await tester.runAsync(() async {
        const letters = TextLetterStyle(fontSize: size, underline: true);
        final one = apart(
          await textDrawn(
            said([run('あ', letters)], vertical: true, at: columnRight),
          ),
          await textDrawn(
            said(
              [run('あ', letters.copyWith(underline: false))],
              vertical: true,
              at: columnRight,
            ),
          ),
        );
        final trailed = apart(
          await textDrawn(
            said([run('あ　', letters)], vertical: true, at: columnRight),
          ),
          await textDrawn(
            said(
              [run('あ　', letters.copyWith(underline: false))],
              vertical: true,
              at: columnRight,
            ),
          ),
        );

        expect(one, isNotEmpty);
        expect(trailed, one);
      });
    });

    testWidgets('🚨its line is ONE down the column — no paler seam where one '
        'letter\'s place meets the next\'s between two pixels', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final between = CanvasPoint(x: 300, y: 20.5);
        const letters = TextLetterStyle(fontSize: size, underline: true);
        final content = said(
          [run('あいう', letters)],
          vertical: true,
          at: between,
        );
        final layout = layoutCelText(content);
        final meet = between.y + layout.selectionRects(0, 1).single.bottom;
        layout.dispose();
        expect(meet - meet.floor(), inInclusiveRange(0.1, 0.9), reason: 'premise');
        final ours = await textDrawn(content);
        final thickness =
            CanvasLetterFaces.appFaceLines[AppTypography.bundledFamily]!
                .underlineThickness *
            size;
        // The column of pixels down the line's middle.
        final x = (squareRight + thickness / 2).floor();

        expect(pixelAt(ours, x, meet.floor()) >>> 24, 0xFF);
        expect(pixelAt(ours, x, meet.floor() - 3) >>> 24, 0xFF, reason: 'fixture');
      });
    });
  });

  testWidgets('🚨a line is ONE along its letters where they turn bold — no '
      'paler seam where one run meets the next between two pixels', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const plain = TextLetterStyle(fontSize: 64, underline: true);
      final content = said([
        run('ab', plain),
        run('cd', plain.copyWith(bold: true)),
      ]);
      final layout = layoutCelText(content);
      final meet = anchor.x + layout.selectionRects(0, 2).single.right;
      layout.dispose();
      expect(meet - meet.floor(), inInclusiveRange(0.1, 0.9), reason: 'premise');
      final ours = await textDrawn(content);
      final bare = await textDrawn(
        said([
          run('ab', plain.copyWith(underline: false)),
          run('cd', plain.copyWith(underline: false, bold: true)),
        ]),
      );
      // A row the line covers whole, under 「a」.
      final under = middleOf('ab', plain, 0);
      final row = rowsAt(apart(ours, bare), under).firstWhere(
        (y) => pixelAt(ours, under, y) >>> 24 == 0xFF,
      );

      expect(pixelAt(ours, meet.floor(), row) >>> 24, 0xFF);
    });
  });

  testWidgets('🚨lines set closer than their letters are tall each wear their '
      'OWN line — the second\'s is under the second', (tester) async {
    await tester.runAsync(() async {
      const letters = TextLetterStyle(fontSize: 64, underline: true);
      CelTextContent closeSet(TextLetterStyle style) => CelTextContent(
        spans: [run('あ\nあ', style)],
        anchor: anchor,
        lineHeight: 0.5,
      );
      final line = apart(
        await textDrawn(closeSet(letters)),
        await textDrawn(closeSet(letters.copyWith(underline: false))),
      );
      final rows = rowsAt(line, middleOf('あ', letters, 0));
      // Two bands of rows, one pitch apart.
      final second = rows.firstWhere((y) => y > rows.first + 8);

      expect(second - rows.first, closeTo(64 * 0.5, 1));
    });
  });

  testWidgets('a line leaves bare the white space it ends with — where it '
      'breaks for want of room', (tester) async {
    await tester.runAsync(() async {
      const letters = TextLetterStyle(fontSize: 64, underline: true);
      const bare = TextLetterStyle(fontSize: 64);
      // Wide enough for 「あい」 and its space, too narrow for 「う」 too:
      // the space hangs at the first line's end.
      final room = TextPainter(
        text: TextSpan(
          text: 'あい ',
          style: canvasLetterTextStyle(bare, lineHeight: 1.2),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final wrapWidth = room.width + 4;
      room.dispose();
      Future<Set<(int, int)>> lineOf(String words) async => apart(
        await textDrawn(said([run(words, letters)], wrapWidth: wrapWidth)),
        await textDrawn(said([run(words, bare)], wrapWidth: wrapWidth)),
      );
      final wrapped = await lineOf('あい うえ');
      final firstLine = {
        for (final (x, y) in wrapped)
          if (y < anchor.y + 64 * 1.2) x,
      };
      final unwrapped = {for (final (x, _) in await lineOf('あい')) x};

      expect(firstLine, unwrapped);
    });
  });

  testWidgets('a hard letter\'s line is hard: its colour, whole, or '
      'nothing — turned and between pixels', (tester) async {
    await tester.runAsync(() async {
      const letters = TextLetterStyle(
        fontSize: 40,
        color: red,
        antialias: false,
        underline: true,
        strikethrough: true,
      );
      final content = CelTextContent(
        spans: [run('あア', letters)],
        anchor: anchor,
        rotationDegrees: 25,
      );
      final ours = await textDrawn(content);
      final colours = {
        for (var at = 0; at < ours.length; at += 4)
          if (ours[at + 3] != 0)
            ours[at + 3] << 24 | ours[at] << 16 | ours[at + 1] << 8 | ours[at + 2],
      };
      final bare = await textDrawn(
        CelTextContent(
          spans: [
            run(
              'あア',
              letters.copyWith(underline: false, strikethrough: false),
            ),
          ],
          anchor: anchor,
          rotationDegrees: 25,
        ),
      );

      expect(apart(ours, bare), isNotEmpty, reason: 'it IS drawn');
      expect(colours, {red});
    });
  });

  testWidgets('🚨the SE name tag wears its letters\' line, at the size it '
      'is drawn', (tester) async {
    await tester.runAsync(() async {
      Future<Uint8List> tagDrawn(TextCelStyle style) async {
        final layout = layoutTextCel(
          content: TextCelContent(
            text: 'S1 太郎',
            style: style,
            position: const ui.Offset(300, 40),
          ),
          canvas: const CanvasSize(width: width, height: height),
        );
        try {
          return await drawn(layout.paint);
        } finally {
          layout.dispose();
        }
      }

      const style = TextCelStyle(fontSize: 48);
      final line = apart(
        await tagDrawn(style.copyWith(underline: true)),
        await tagDrawn(style),
      );

      expect(line, isNotEmpty);

      // Shrunk to half its width, a tag of 48 is drawn at 24 — and so is
      // its line: as a tag of 24 wears it.
      final whole = layoutTextCel(
        content: const TextCelContent(
          text: 'S1 太郎',
          style: style,
          position: ui.Offset(300, 40),
        ),
        canvas: const CanvasSize(width: width, height: height),
      );
      final half = whole.textSize.width / 2;
      whole.dispose();
      Future<Set<(int, int)>> lineOf(TextCelStyle style, {double? fit}) async {
        Future<Uint8List> at(TextCelStyle style) async {
          final layout = layoutTextCel(
            content: TextCelContent(
              text: 'S1 太郎',
              style: style,
              position: const ui.Offset(300, 40),
            ),
            canvas: const CanvasSize(width: width, height: height),
            maxWidth: fit,
          );
          try {
            return await drawn(layout.paint);
          } finally {
            layout.dispose();
          }
        }

        return apart(await at(style.copyWith(underline: true)), await at(style));
      }

      final shrunk = await lineOf(style, fit: half);
      expect(shrunk, isNotEmpty);
      expect(shrunk, await lineOf(style.copyWith(fontSize: 24)));
    });
  });

  group('a leaning letter', () {
    /// Where the ink of [bytes] begins, at its top row and its bottom row.
    ({int top, int bottom}) leanOf(Uint8List bytes) {
      int? firstInk(int y) {
        for (var x = 0; x < width; x += 1) {
          if (bytes[(y * width + x) * 4 + 3] > 127) {
            return x;
          }
        }
        return null;
      }

      final rows = [
        for (var y = 0; y < height; y += 1)
          if (firstInk(y) != null) y,
      ];
      return (top: firstInk(rows.first)!, bottom: firstInk(rows.last)!);
    }

    for (final vertical in [false, true]) {
      testWidgets('leans — its top to the right of where it stood — in '
          '${vertical ? 'columns' : 'lines'}', (tester) async {
        await tester.runAsync(() async {
          const letters = TextLetterStyle(fontSize: 64);
          final at = vertical ? CanvasPoint(x: 300, y: 20) : anchor;
          final upright = leanOf(
            await textDrawn(said([run('口', letters)], vertical: vertical, at: at)),
          );
          final leaning = leanOf(
            await textDrawn(
              said(
                [run('口', letters.copyWith(italic: true))],
                vertical: vertical,
                at: at,
              ),
            ),
          );

          expect(leaning.top - leaning.bottom, greaterThan(5));
          expect(upright.top - upright.bottom, lessThan(2));
        });
      });
    }
  });

  group('lines that carry on from each other', () {
    const plain = TextLetterStyle(underline: true);
    final heavy = plain.copyWith(bold: true);

    test('in letters every pass paints alike are ONE line — along a line, '
        'and down a column', () {
      final along = CanvasLetterLinesBuilder()
        ..under(plain, const ui.Rect.fromLTRB(0, 10, 20.5, 12))
        ..under(heavy, const ui.Rect.fromLTRB(20.5, 10, 40, 12));
      final down = CanvasLetterLinesBuilder()
        ..through(plain, const ui.Rect.fromLTRB(5, 0, 7, 30.25))
        ..through(heavy, const ui.Rect.fromLTRB(5, 30.25, 7, 60));

      expect(_rectsOf(along.build()), [const ui.Rect.fromLTRB(0, 10, 40, 12)]);
      expect(_rectsOf(down.build()), [const ui.Rect.fromLTRB(5, 0, 7, 60)]);
    });

    test('in letters a pass paints otherwise, or that do not meet, or that '
        'stand otherwise, are not', () {
      final apartLines = CanvasLetterLinesBuilder()
        ..under(plain, const ui.Rect.fromLTRB(0, 10, 20, 12))
        ..under(plain.copyWith(color: red), const ui.Rect.fromLTRB(20, 10, 40, 12))
        ..under(plain, const ui.Rect.fromLTRB(41, 10, 60, 12))
        ..under(plain, const ui.Rect.fromLTRB(60, 11, 80, 13));

      expect(_rectsOf(apartLines.build()), hasLength(4));
      expect(
        canvasLettersPaintAlike(plain, plain.copyWith(outlineWidth: 2)),
        isFalse,
      );
      expect(
        canvasLettersPaintAlike(plain, plain.copyWith(antialias: false)),
        isFalse,
      );
      expect(
        canvasLettersPaintAlike(plain, plain.copyWith(outlineColor: blue)),
        isFalse,
      );
      expect(canvasLettersPaintAlike(plain, heavy), isTrue);
    });
  });
}

/// The rects [lines] draws — its letters smooth and bare of outlines, so
/// drawn in the fill pass alone — read off a canvas that keeps them.
List<ui.Rect> _rectsOf(CanvasLetterLines lines) {
  final canvas = _RectsCanvas();
  CanvasLetterPasses<Object>.of(
    const [TextLetterStyle()],
    (_) => Object(),
    letGo: (_) {},
  ).paint(canvas, within: ui.Rect.largest, draw: (_) {}, lines: lines);
  return canvas.rects;
}

class _RectsCanvas implements ui.Canvas {
  final List<ui.Rect> rects = [];

  @override
  void drawRect(ui.Rect rect, ui.Paint paint) => rects.add(rect);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
