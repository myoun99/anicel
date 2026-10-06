import 'dart:async';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_fixture.dart';
import '../../../helpers/cel_text_held_baker.dart';

/// R9-rest (the text tool): ONE TEXT THE TOOL IS HOLDING — the text as its
/// cel carries it, what the person has made of it since, and what of that
/// is on screen.
///
/// The engine is held by the test ([HeldBaker]), so every test here can
/// stand between a text being wanted and its pixels existing.
///
/// In the test font every letter is a box one size wide: 「ab」 at 8 is 16
/// wide on a line 10 tall, and its pixels can be a letter's size — 8 —
/// beyond that on every side. The test canvas is 32×32, its pasteboard wall
/// one canvas further out: −32 to 64.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const letters = TextLetterStyle(fontSize: 8);

  CelTextContent says(String words, {double x = 8, double y = 8}) =>
      CelTextContent(
        spans: [CelTextSpan(text: words, style: letters)],
        anchor: CanvasPoint(x: x, y: y),
      );

  CelTextContent nothingAt({double x = 8, double y = 8}) =>
      CelTextContent(spans: const [], anchor: CanvasPoint(x: x, y: y));

  /// A text a cel carries, with the plate the stand-in makes of it.
  CelText carried(int id, CelTextContent content) =>
      CelText(id: id, content: content, plate: plateOf(content));

  final drawn = TileCoord(x: 3, y: 3);
  final ink = tileOf({
    (1, 1): [9, 9, 9, 255],
  });

  BitmapSurface picture([List<CelText> texts = const []]) =>
      drawingOf({drawn: ink}).withTexts(texts);

  ({CelTextSession session, HeldBaker baker}) holding(CelText? standing) {
    final baker = HeldBaker();
    return (
      session: CelTextSession(
        key: celTextTestKey,
        canvasSize: celTextTestCanvas,
        tileSize: celTextTestTileSize,
        standing: standing,
        content: standing?.content ?? nothingAt(),
        nextLetterStyle: letters,
        bake: baker.call,
      ),
      baker: baker,
    );
  }

  List<(int, String)> textsOf(BitmapSurface surface) => [
    for (final text in surface.texts) (text.id, text.content.text),
  ];

  group('a text that is not on the cel yet', () {
    test('shows nothing and has nothing to land while it has no letters', () {
      final (:session, :baker) = holding(null);
      final cel = picture();

      expect(session.settled, isTrue);
      expect(session.textId, isNull);
      expect(session.shownOver(cel), same(cel));
      expect(session.landing(coordinator: editingStackOn(cel)), isNull);
      expect(baker.asked, isEmpty);
    });

    test('🚨typed into, it is SHOWN only once its pixels are made — and then '
        'on top of the texts the cel carries', () async {
      final (:session, :baker) = holding(null);
      final under = carried(4, says('zz', x: 16, y: 16));
      final cel = picture([under]);
      var told = 0;
      session.addListener(() => told += 1);

      session.set(says('ab'));

      expect(session.content, says('ab'), reason: 'what the person wants');
      expect(session.shown.content.isEmpty, isTrue, reason: 'not set yet');
      expect(session.settled, isFalse);
      expect(session.shownOver(cel), same(cel));
      expect(baker.asked.single.content, says('ab'));
      expect(told, 1);

      await baker.pending.answer();

      expect(session.settled, isTrue);
      expect(session.shown.content, says('ab'));
      expect(
        session.shown.layout.content,
        says('ab'),
        reason: 'the box and the caret are read off the text the plate is of',
      );
      expect(told, greaterThan(1), reason: 'the canvas is told to draw it');
      final shown = session.shownOver(cel);
      expect(textsOf(shown), [(4, 'zz'), (5, 'ab')]);
      expect(shown.texts.last.plate, plateOf(says('ab')));
      expect(shown.texts.first, same(under));
      expect(shown.tileAt(drawn), same(ink), reason: 'the drawing is its own');
    });

    test('🚨the newest want wins: a text the engine was overtaken on is '
        'never set', () async {
      final (:session, :baker) = holding(null);

      session
        ..set(says('a'))
        ..set(says('ab'))
        ..set(says('abc'));

      expect(baker.asked, hasLength(1), reason: 'one bake at a time');

      await baker.asked[0].answer();

      expect(
        session.shown.content,
        says('a'),
        reason: 'a whole text is shown, even one already overtaken',
      );
      expect(baker.asked, hasLength(2));
      expect(baker.asked[1].content, says('abc'), reason: '「ab」 is skipped');
      expect(
        baker.asked[1].previous,
        plateOf(says('a')),
        reason: 'the plate on screen is the one whose tiles are worth keeping',
      );
      expect(session.settled, isFalse);

      await baker.asked[1].answer();

      expect(session.shown.content, says('abc'));
      expect(session.settled, isTrue);
      expect(baker.asked, hasLength(2));
    });

    test('whenSettled waits for the LAST want, and answers at once when '
        'nothing is owed', () async {
      final (:session, :baker) = holding(null);
      var settled = false;

      session.set(says('a'));
      unawaited(session.whenSettled().then((_) => settled = true));
      session.set(says('ab'));
      await baker.asked[0].answer();

      expect(settled, isFalse, reason: 'the last want is not on screen yet');

      await baker.asked[1].answer();

      expect(settled, isTrue);
      await expectLater(session.whenSettled(), completes);
    });

    test('the step it lands sets it on top, under an id of its own', () async {
      final (:session, :baker) = holding(null);
      final coordinator = editingStackOn(
        picture([carried(4, says('zz', x: 16, y: 16))]),
      );
      session.set(says('ab'));
      await baker.pending.answer();

      final command = session.landing(coordinator: coordinator)!..execute();

      expect(command.textId, 5);
      expect(textsOf(coordinator.currentSurfaceOf(celTextTestKey)), [
        (4, 'zz'),
        (5, 'ab'),
      ]);
    });
  });

  group('a bake the engine refuses', () {
    test('leaves the last text it made on screen, takes the want back to '
        'it, and says so', () async {
      final (:session, :baker) = holding(null);
      session.set(says('a'));
      await baker.pending.answer();
      var told = 0;
      session.addListener(() => told += 1);

      session.set(says('ab'));
      final waiting = session.whenSettled();
      final before = told;
      await baker.pending.refuse(StateError('no raster'));

      expect(session.failure, isStateError);
      expect(session.shown.content, says('a'));
      expect(session.content, says('a'), reason: 'not asked again and again');
      expect(session.settled, isTrue);
      expect(told, before + 1, reason: 'whoever shows the text is told');
      await expectLater(waiting, completes);
    });

    test('the next want is asked of the engine again, and a bake it makes '
        'clears the failure', () async {
      final (:session, :baker) = holding(null);
      session.set(says('a'));
      await baker.pending.refuse(StateError('no raster'));
      expect(session.failure, isNotNull, reason: '⛔fixture');

      session.set(says('ab'));
      expect(baker.asked, hasLength(2));
      await baker.pending.answer();

      expect(session.failure, isNull);
      expect(session.shown.content, says('ab'));
    });
  });

  group('a text with no letters', () {
    test('asks the engine for nothing: it has no pixels, and is not on the '
        'canvas', () {
      final standing = carried(4, says('ab'));
      final cel = picture([standing, carried(5, says('zz', x: 16, y: 16))]);
      final (:session, :baker) = holding(standing);

      session.set(nothingAt());

      expect(baker.asked, isEmpty);
      expect(session.settled, isTrue);
      expect(session.shown.plate, isEmpty);
      expect(textsOf(session.shownOver(cel)), [(5, 'zz')]);
    });

    test('lands as the text taken OFF its cel — one step', () {
      final standing = carried(4, says('ab'));
      final cel = picture([standing, carried(5, says('zz', x: 16, y: 16))]);
      final coordinator = editingStackOn(cel);
      final (:session, baker: _) = holding(standing);
      session.set(nothingAt());

      final history = HistoryManager()
        ..execute(session.landing(coordinator: coordinator)!);

      expect(textsOf(coordinator.currentSurfaceOf(celTextTestKey)), [
        (5, 'zz'),
      ]);
      history.undo();
      expect(textsOf(coordinator.currentSurfaceOf(celTextTestKey)), [
        (4, 'ab'),
        (5, 'zz'),
      ]);
    });

    test('is measured by the letter about to be typed: a change of that '
        'alone is shown, with nothing baked', () {
      final (:session, :baker) = holding(null);
      expect(session.shown.layout.block.height, 10, reason: '⛔fixture');

      session.set(
        nothingAt(),
        nextLetterStyle: const TextLetterStyle(fontSize: 16),
      );

      expect(session.nextLetterStyle.fontSize, 16);
      expect(session.shown.layout.block.height, 20);
      expect(session.settled, isTrue);
      expect(baker.asked, isEmpty);
    });

    test('⛔a text WITH letters is not set again for it', () {
      final standing = carried(4, says('ab'));
      final (:session, :baker) = holding(standing);
      final layout = session.shown.layout;

      session.set(
        standing.content,
        nextLetterStyle: const TextLetterStyle(fontSize: 16),
      );

      expect(session.shown.layout, same(layout));
      expect(session.settled, isTrue);
      expect(baker.asked, isEmpty);
    });
  });

  group('a text the cel carries', () {
    test('is shown as the cel carries it: the cel itself, and nothing to '
        'land', () {
      final standing = carried(4, says('ab'));
      final cel = picture([standing]);
      final (:session, :baker) = holding(standing);

      expect(session.textId, 4);
      expect(session.shown.plate, same(standing.plate));
      expect(session.shownOver(cel), same(cel));
      expect(session.landing(coordinator: editingStackOn(cel)), isNull);
      expect(baker.asked, isEmpty);
    });

    test('set differently, it is shown in ITS PLACE among the cel\'s texts, '
        'under its id — once baked', () async {
      final first = carried(3, says('ab'));
      final second = carried(5, says('zz', x: 16, y: 16));
      final cel = picture([first, second]);
      final (:session, :baker) = holding(first);

      session.set(says('abc'));

      expect(session.shownOver(cel), same(cel), reason: 'as it stands, yet');

      await baker.pending.answer();

      final shown = session.shownOver(cel);
      expect(textsOf(shown), [(3, 'abc'), (5, 'zz')]);
      expect(shown.texts[0].plate, plateOf(says('abc')));
      expect(shown.texts[1], same(second));
    });

    test('🚨set differently and then BACK, it is the text the cel carries '
        'again — nothing to land, though its tiles were baked afresh', () async {
      final standing = carried(4, says('ab'));
      final cel = picture([standing]);
      final (:session, :baker) = holding(standing);

      session.set(says('abc'));
      await baker.pending.answer();
      session.set(says('ab'));
      await baker.pending.answer();

      final at = tileOfAnchor(says('ab'));
      expect(
        session.shown.plate[at],
        isNot(same(standing.plate[at])),
        reason: '⛔fixture: other tiles holding the same pixels',
      );
      expect(session.shownOver(cel), same(cel));
      expect(session.landing(coordinator: editingStackOn(cel)), isNull);
    });

    test('⛔the same letters baked to OTHER pixels are not the text the cel '
        'carries: that lands', () async {
      final standing = carried(4, says('ab'));
      final cel = picture([standing]);
      final (:session, :baker) = holding(standing);

      session.set(says('abc'));
      await baker.pending.answer();
      session.set(says('ab'));
      await baker.pending.answer({
        tileOfAnchor(says('ab')): tileFilledWith([77, 0, 0, 255]),
      });

      expect(session.shownOver(cel), isNot(same(cel)));
      expect(session.landing(coordinator: editingStackOn(cel)), isNotNull);
    });

    test('told the cel no longer carries it, it is a text that would be '
        'new: laid on top, and what was drawn of it in its place forgotten', () async {
      final standing = carried(4, says('ab'));
      final cel = picture([standing]);
      final (:session, :baker) = holding(standing);
      session.set(says('abc'));
      await baker.pending.answer();
      expect(textsOf(session.shownOver(cel)), [(4, 'abc')], reason: '⛔fixture');

      session.standOn(null);

      expect(session.textId, isNull);
      expect(textsOf(session.shownOver(cel)), [(4, 'ab'), (5, 'abc')]);
    });

    test('🚨the step it lands holds what is SHOWN, never a want still being '
        'set — and the session then stands on what the cel carries', () async {
      final standing = carried(4, says('ab'));
      final coordinator = editingStackOn(picture([standing]));
      final (:session, :baker) = holding(standing);

      session.set(says('abc'));

      expect(
        session.landing(coordinator: coordinator),
        isNull,
        reason: 'what is shown is still the text the cel carries',
      );

      await baker.pending.answer();
      final command = session.landing(coordinator: coordinator)!..execute();

      final landed = coordinator.currentSurfaceOf(celTextTestKey);
      expect(command.textId, 4);
      expect(landed.texts.single.content, says('abc'));

      session.standOn(landed.texts.single);

      expect(session.standing, same(landed.texts.single));
      expect(session.shownOver(landed), same(landed));
      expect(session.landing(coordinator: coordinator), isNull);
    });
  });

  group('a move by whole pixels', () {
    test('🚨moves the PIXELS, at once — the engine is not asked — and the '
        'text with them', () {
      final standing = carried(4, says('ab'));
      final cel = picture([standing]);
      final (:session, :baker) = holding(standing);
      final origin = session.moveOrigin;

      session.showMoved(origin, cel, dx: 8, dy: 0);

      expect(session.shown.content, says('ab', x: 16));
      expect(session.content, says('ab', x: 16));
      expect(session.settled, isTrue);
      expect(session.shown.plate.keys, [TileCoord(x: 2, y: 1)]);
      expect(
        session.shown.plate.values.single,
        standing.plate.values.single,
        reason: 'the very pixels, a tile over',
      );
      expect(
        session.shown.layout.content,
        says('ab', x: 16),
        reason: 'the box moves with the letters',
      );
      expect(baker.asked, isEmpty);
    });

    test('is measured from where the text STOOD when the hand took it, '
        'never from the last move', () {
      final standing = carried(4, says('ab'));
      final cel = picture([standing]);
      final (:session, baker: _) = holding(standing);
      final origin = session.moveOrigin;

      session
        ..showMoved(origin, cel, dx: 8, dy: 0)
        ..showMoved(origin, cel, dx: 16, dy: 8);

      expect(session.shown.content, says('ab', x: 24, y: 16));
      expect(session.shown.plate.keys, [TileCoord(x: 3, y: 2)]);
    });

    test('back where it stood, it is the text the cel carries — its very '
        'tiles, and nothing to land', () {
      final standing = carried(4, says('ab'));
      final cel = picture([standing]);
      final (:session, baker: _) = holding(standing);
      final origin = session.moveOrigin;

      session
        ..showMoved(origin, cel, dx: 8, dy: 0)
        ..showMoved(origin, cel, dx: 0, dy: 0);

      expect(session.shown.plate, same(origin.plate));
      expect(session.shownOver(cel), same(cel));
      expect(session.landing(coordinator: editingStackOn(cel)), isNull);
    });

    test('🚨ACROSS THE PASTEBOARD WALL it is set again, not cut — and a '
        'move made while that is under way waits its turn', () async {
      final standing = carried(4, says('ab'));
      final cel = picture([standing]);
      final (:session, :baker) = holding(standing);
      final origin = session.moveOrigin;

      // Its pixels can reach x = 32; 40 further is past the wall at 64.
      session.showMoved(origin, cel, dx: 40, dy: 0);

      expect(baker.asked.single.content, says('ab', x: 48));
      expect(session.shown.content, says('ab'), reason: 'until it is set');

      // Back inside, where a move alone would do — but a bake is under way.
      session.showMoved(origin, cel, dx: 8, dy: 0);

      expect(baker.asked, hasLength(1));
      expect(session.shown.content, says('ab'));

      await baker.asked[0].answer();
      expect(baker.asked[1].content, says('ab', x: 16));
      await baker.asked[1].answer();

      expect(session.shown.content, says('ab', x: 16));
      expect(session.settled, isTrue);
    });

    test('each of the four walls is a wall — and up to it, it is still a '
        'move', () {
      // 「ab」 at (8, 8) can reach from (0, 0) to (32, 26); the walls stand
      // at −32 and 64.
      for (final (dx, dy) in [(40, 0), (-40, 0), (0, 40), (0, -40)]) {
        final standing = carried(4, says('ab'));
        final (:session, :baker) = holding(standing);

        session.showMoved(
          session.moveOrigin,
          picture([standing]),
          dx: dx,
          dy: dy,
        );

        expect(baker.asked, hasLength(1), reason: 'past it by ($dx, $dy)');
      }
      for (final (dx, dy) in [(32, 0), (-32, 0), (0, 38), (0, -32)]) {
        final standing = carried(4, says('ab'));
        final (:session, :baker) = holding(standing);

        session.showMoved(
          session.moveOrigin,
          picture([standing]),
          dx: dx,
          dy: dy,
        );

        expect(baker.asked, isEmpty, reason: 'up to it by ($dx, $dy)');
        expect(session.settled, isTrue);
      }
    });

    test('a hand that has not moved a whole pixel since the last move '
        'changes nothing, and nobody is told', () {
      final standing = carried(4, says('ab'));
      final cel = picture([standing]);
      final (:session, baker: _) = holding(standing);
      final origin = session.moveOrigin;
      session.showMoved(origin, cel, dx: 8, dy: 0);
      final layout = session.shown.layout;
      var told = 0;
      session.addListener(() => told += 1);

      session.showMoved(origin, cel, dx: 8, dy: 0);

      expect(told, 0);
      expect(session.shown.layout, same(layout));
    });

    test('a text that stands ACROSS the wall is set again wherever it goes: '
        'what the wall cut away is not in its pixels', () {
      // Its pixels can reach x = 68, past the wall at 64.
      final standing = carried(4, says('ab', x: 44));
      final cel = picture([standing]);
      final (:session, :baker) = holding(standing);

      session.showMoved(session.moveOrigin, cel, dx: -24, dy: 0);

      expect(baker.asked.single.content, says('ab', x: 20));
    });
  });

  test('asked twice of one cel it is ONE picture — what the canvas keys '
      'its drawing on — and another once the text is set differently', () async {
    final standing = carried(4, says('ab'));
    final cel = picture([standing]);
    final (:session, :baker) = holding(standing);
    session.set(says('abc'));
    await baker.pending.answer();

    final shown = session.shownOver(cel);

    expect(session.shownOver(cel), same(shown));

    session.set(says('abcd'));
    await baker.pending.answer();

    expect(session.shownOver(cel), isNot(same(shown)));
    expect(textsOf(session.shownOver(cel)), [(4, 'abcd')]);
  });

  test('a session let go of mid-bake owes nothing: whoever waited is '
      'answered, and the engine\'s late answer changes nothing', () async {
    final (:session, :baker) = holding(null);
    session.set(says('ab'));
    final waiting = session.whenSettled();

    session.dispose();

    await expectLater(waiting, completes);
    await baker.asked.single.answer();
  });
}
