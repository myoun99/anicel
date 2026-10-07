import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/text/canvas_letter_faces.dart';
import 'package:anicel/src/ui/text/cel_text_bake.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show TextPainter;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_fixture.dart';

/// R9-rest, 세로쓰기: THE PAINTERS OF A TEXT IN COLUMNS ARE KEPT — one a
/// cell, a pass, by what each is made of — so that a text set again, which
/// every letter typed does, makes only the painters it did not have.
///
/// 🔬Measured on the device (Windows, debug build, 2026-10-07): making them
/// all was ≈47 µs a cell a pass on the thread that answers the keys — 5 ms
/// for fifty letters, 77 ms for eight hundred outlined.
///
/// 🚨AND WHAT A TEXT BAKES TO DOES NOT CHANGE BY A BYTE for being set from
/// kept painters (유저: 「결과 절대 바뀌면 안되는건 캔버스뿐임」) — the last
/// group.
///
/// ⚠️The painters are counted off the framework's own notices of a
/// `TextPainter` made and disposed: nothing in the layout is asked how many
/// it made.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const plain = TextLetterStyle(fontSize: 10);

  CelTextContent columns(
    List<CelTextSpan> spans, {
    double? wrapWidth,
    double x = 28,
    double y = 2,
  }) => CelTextContent(
    spans: spans,
    anchor: CanvasPoint(x: x, y: y),
    wrapWidth: wrapWidth,
    lineHeight: 1,
    vertical: true,
  );

  CelTextSpan run(String words, [TextLetterStyle style = plain]) =>
      CelTextSpan(text: words, style: style);

  /// The painters made and disposed while [body] ran.
  ({int made, int gone}) counted(void Function() body) {
    var made = 0;
    var gone = 0;
    void heard(ObjectEvent event) {
      if (event.object is! TextPainter) {
        return;
      }
      if (event is ObjectCreated) {
        made += 1;
      } else if (event is ObjectDisposed) {
        gone += 1;
      }
    }

    FlutterMemoryAllocations.instance.addListener(heard);
    try {
      body();
    } finally {
      FlutterMemoryAllocations.instance.removeListener(heard);
    }
    return (made: made, gone: gone);
  }

  /// [content] set, and let go of when the test ends.
  CelTextLayout set(CelTextContent content) {
    final layout = layoutCelText(content);
    addTearDown(layout.dispose);
    return layout;
  }

  // Every test starts with nothing kept that no layout holds — and the
  // layouts of the test before are let go of by then.
  setUp(debugForgetIdleCelTextCellPainters);

  group('a text set again', () {
    test('⛔CONTROL: set from nothing, it makes a painter a cell', () {
      final first = counted(() => set(columns([run('あいう')])));

      expect(first, (made: 3, gone: 0));
    });

    test('🚨makes only the painters of the cells it did NOT have — a letter '
        'typed at its end is one painter', () {
      set(columns([run('あいう')]));

      final again = counted(() => set(columns([run('あいうえ')])));

      expect(again, (made: 1, gone: 0));
    });

    test('a letter typed in its MIDDLE is one painter too: a cell is kept '
        'by what it is, not by where it stands', () {
      set(columns([run('あいう')]));

      final again = counted(() => set(columns([run('あえいう')])));

      expect(again, (made: 1, gone: 0));
    });

    test('the same letter twice in one text is one painter', () {
      expect(counted(() => set(columns([run('ああいあ')]))).made, 2);
    });

    test('set again as it was, it makes none', () {
      set(columns([run('あいう')], wrapWidth: 20));

      expect(
        counted(() => set(columns([run('あいう')], wrapWidth: 40))),
        (made: 0, gone: 0),
      );
    });
  });

  group('a painter is held by every layout that sets its cell', () {
    test('🚨one layout let go of disposes nothing another still holds — '
        'which goes on measuring and drawing with it', () {
      final shown = layoutCelText(columns([run('あい')]));
      final wanted = set(columns([run('あいう')]));

      final letGo = counted(shown.dispose);

      expect(letGo, (made: 0, gone: 0));
      expect(wanted.block, const ui.Rect.fromLTWH(-10, 0, 10, 30));
      final recorder = ui.PictureRecorder();
      wanted.paint(ui.Canvas(recorder));
      recorder.endRecording().dispose();
    });

    test('held by none, it is KEPT for the next setting: nothing is '
        'disposed, and nothing made when its text is set again', () {
      final layout = layoutCelText(columns([run('あい')]));

      expect(counted(layout.dispose), (made: 0, gone: 0));
      expect(counted(() => set(columns([run('あい')]))), (made: 0, gone: 0));
    });

    test('the idle ones forgotten are DISPOSED, and made again when next '
        'set', () {
      layoutCelText(columns([run('あい')])).dispose();

      expect(
        counted(debugForgetIdleCelTextCellPainters),
        (made: 0, gone: 2),
      );
      expect(counted(() => set(columns([run('あい')]))).made, 2);
    });

    test('🚨a painter still HELD is never disposed, however many others '
        'are let go of meanwhile — let go of by one of two is not idle', () {
      final first = layoutCelText(columns([run('あ')]));
      final second = set(columns([run('あ')]));
      first.dispose();
      // 1100 letters, no two alike and none of them 「あ」.
      final many = String.fromCharCodes([
        for (var at = 0; at < 1100; at += 1) 0x4E00 + at,
      ]);
      final flood = layoutCelText(columns([run(many)]));

      final letGo = counted(flood.dispose);

      expect(letGo.gone, 1100 - 1024, reason: 'the flood\'s own, no other');
      expect(second.block, const ui.Rect.fromLTWH(-10, 0, 10, 10));
      final recorder = ui.PictureRecorder();
      second.paint(ui.Canvas(recorder));
      recorder.endRecording().dispose();
    });

    test('🚨…but not for ever: past a thousand and twenty-four let go of '
        'since, the longest idle are disposed', () {
      // 1100 letters, no two alike.
      final many = String.fromCharCodes([
        for (var at = 0; at < 1100; at += 1) 0x4E00 + at,
      ]);
      final layout = layoutCelText(columns([run(many)]));

      final letGo = counted(layout.dispose);

      expect(letGo, (made: 0, gone: 1100 - 1024));
      // The LAST of them are the ones kept.
      final tail = many.substring(1100 - 1024);
      expect(counted(() => set(columns([run(tail)]))).made, 0);
      // …and the first are GONE from the keeping: set again they are made
      // again — never handed back disposed — and draw.
      final head = set(columns([run(many.substring(0, 1100 - 1024))]));
      final recorder = ui.PictureRecorder();
      head.paint(ui.Canvas(recorder));
      recorder.endRecording().dispose();
    });

    test('…and a cell that fell out of the keeping is MADE again', () {
      final many = String.fromCharCodes([
        for (var at = 0; at < 1100; at += 1) 0x4E00 + at,
      ]);
      layoutCelText(columns([run(many)])).dispose();

      expect(
        counted(
          () => set(columns([run(many.substring(0, 1100 - 1024))])),
        ).made,
        1100 - 1024,
      );
    });

    test('⛔CONTROL: a text in LINES keeps none — one paragraph, set again '
        'whole', () {
      CelTextContent lines(String words) => CelTextContent(
        spans: [run(words)],
        anchor: CanvasPoint(x: 2, y: 2),
      );
      final first = layoutCelText(lines('あいう'));
      addTearDown(first.dispose);

      final again = counted(() => layoutCelText(lines('あいう')).dispose());

      expect(again, (made: 1, gone: 1));
    });
  });

  group('a cell\'s painter is kept by ALL it is made of', () {
    test('other letters, another size, another colour: each its own', () {
      set(columns([run('あ')]));

      expect(counted(() => set(columns([run('い')]))).made, 1);
      expect(
        counted(
          () => set(columns([run('あ', const TextLetterStyle(fontSize: 12))])),
        ).made,
        1,
      );
      expect(
        counted(
          () => set(
            columns([
              run('あ', const TextLetterStyle(fontSize: 10, color: 0xFF112233)),
            ]),
          ),
        ).made,
        1,
      );
    });

    test('🚨another PASS: an outlined letter is two painters, its fill and '
        'its outline — and a letter with none beside it is one, not two', () {
      const outlined = TextLetterStyle(
        fontSize: 10,
        outlineColor: 0xFF0000FF,
        outlineWidth: 2,
      );

      expect(counted(() => set(columns([run('あ', outlined)]))).made, 2);
      // 「い」 is not the outline pass's to draw: it has no painter there.
      expect(
        counted(() => set(columns([run('あ', outlined), run('い')]))).made,
        1,
      );
    });

    test('a HARD letter is measured on its own colour and drawn as cover: '
        'two painters — and a smooth one beside it still one', () {
      const hard = TextLetterStyle(fontSize: 10, antialias: false);

      expect(counted(() => set(columns([run('あ', hard)]))).made, 2);
      expect(
        counted(() => set(columns([run('あ', hard), run('い')]))).made,
        1,
      );
    });

    test('🚨a hard letter outlined IN ITS OWN COLOUR has two covers of one '
        'colour, its outline\'s and its fill\'s: each its own painter', () {
      const hardRinged = TextLetterStyle(
        fontSize: 10,
        color: 0xFFAA0000,
        outlineColor: 0xFFAA0000,
        outlineWidth: 2,
        antialias: false,
      );

      // What it is measured on · the outline's cover · the fill's cover.
      expect(counted(() => set(columns([run('あ', hardRinged)]))).made, 3);
    });

    // ⚠️Not asked here: 「lying down or standing」, which is in the key too.
    // No two cells of a text differ by that ALONE — a word lying down is
    // two letters or more, or one with its space after it; a standing cell
    // is neither — so no setting can tell a key that forgot it. It cannot
    // be forgotten: the painter is made of the key itself.
    test('a word lying down is tracked by its own painter, a standing '
        'letter by the room after it — and each is kept as it is set', () {
      const tracked = TextLetterStyle(fontSize: 10, letterSpacing: 4);

      final word = set(columns([run('ab', tracked)]));
      final letter = set(columns([run('あ', tracked)]));

      // 「ab」 lying down: two letters and the tracking after each.
      expect(word.block, const ui.Rect.fromLTWH(-10, 0, 10, 28));
      // 「あ」 standing: its em, and its tracking as room.
      expect(letter.block, const ui.Rect.fromLTWH(-10, 0, 10, 14));
      // Set again from kept painters, they stand as they did.
      expect(
        counted(() {
          expect(set(columns([run('ab', tracked)])).block, word.block);
          expect(set(columns([run('あ', tracked)])).block, letter.block);
        }),
        (made: 0, gone: 0),
      );
    });

    test('🚨the FACES the engine had: a face arrived, and every cell is set '
        'again', () {
      set(columns([run('あい')]));
      CanvasLetterFaces.current = CanvasLetterFaces();
      addTearDown(() => CanvasLetterFaces.current = CanvasLetterFaces());

      expect(counted(() => set(columns([run('あい')]))).made, 2);
    });
  });

  // 🚨The whole of why this may be kept at all.
  group('what a text bakes to is what it bakes to set from nothing', () {
    Future<Map<TileCoord, List<int>>> baked(CelTextContent content) async {
      final layout = layoutCelText(content);
      final Map<TileCoord, BitmapTile> plate;
      try {
        plate = await bakeCelTextPlate(
          layout,
          canvasSize: celTextTestCanvas,
          tileSize: celTextTestTileSize,
        );
      } finally {
        layout.dispose();
      }
      return {for (final entry in plate.entries) entry.key: entry.value.pixels};
    }

    const outlined = TextLetterStyle(
      fontSize: 10,
      color: 0xFFC80A14,
      outlineColor: 0xFF0A14C8,
      outlineWidth: 3,
    );
    const hard = TextLetterStyle(
      fontSize: 10,
      color: 0xFF14C80A,
      antialias: false,
    );

    test('🚨to the byte — its cells kept from OTHER texts, in other places, '
        'beside other styles', () async {
      final text = columns([
        run('あ1', outlined),
        run('ab', hard),
        run('い。'),
      ], wrapWidth: 20);
      final fromNothing = await baked(text);
      expect(fromNothing, isNotEmpty, reason: '⛔fixture');

      // The same cells, held by texts that set them elsewhere and
      // otherwise: in another order, turned, one column long.
      debugForgetIdleCelTextCellPainters();
      set(
        columns([
          run('い。'),
          run('ab', hard),
          run('あ1', outlined),
        ], x: 10, y: 20),
      );
      set(
        CelTextContent(
          spans: [run('。あ', outlined), run('い')],
          anchor: CanvasPoint(x: 16, y: 16),
          rotationDegrees: 30,
          lineHeight: 2,
          vertical: true,
        ),
      );
      final kept = counted(() => set(text));
      expect(kept.made, lessThan(4), reason: '⛔fixture: set from kept ones');

      expect(await baked(text), fromNothing);
    });
  });
}
