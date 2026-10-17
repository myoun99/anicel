import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/cel_text_laying.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/text_tool_options.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_fixture.dart';
import '../../../helpers/cel_text_held_baker.dart';

/// R9-rest (the text tool): THE TOOL'S HAND — the one text it holds, how it
/// holds it, and the landing of what the person made of it.
///
/// 🚨★★★ONE HOLD, AND EVERY WAY OUT OF IT LANDS (the press table 유저 took
/// on 2026-10-06: there is no cancel — the way back is undo). And a step of
/// history holds a WHOLE text: the engine is held by the test
/// ([HeldBaker]), so each of these can stand in the frames where what the
/// person wants is ahead of what the engine has made.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const plain = TextLetterStyle(fontSize: 8);
  const red = TextLetterStyle(fontSize: 8, color: 0xFFFF0000);

  CelTextSpan run(String words, [TextLetterStyle style = plain]) =>
      CelTextSpan(text: words, style: style);

  CelTextContent said(
    List<CelTextSpan> spans, {
    double x = 8,
    double y = 8,
  }) => CelTextContent(spans: spans, anchor: CanvasPoint(x: x, y: y));

  /// A text a cel carries, with the plate the stand-in makes of it.
  CelText carried(int id, CelTextContent content) =>
      CelText(id: id, content: content, plate: plateOf(content));

  final drawn = TileCoord(x: 3, y: 3);
  final ink = tileOf({
    (1, 1): [9, 9, 9, 255],
  });

  ({CelTextTool tool, _Host host, HeldBaker baker, CelTextCel cel}) hand({
    List<CelText> texts = const [],
  }) {
    final host = _Host();
    final baker = HeldBaker();
    final CelTextCel cel = (
      key: celTextTestKey,
      coordinator: editingStackOn(
        drawingOf({drawn: ink}).withTexts(texts),
      ),
      canvasSize: celTextTestCanvas,
      cacheInvalidationSink: null,
    );
    // The cel under the tool, until a test says another is.
    host.cel = cel;
    return (
      tool: CelTextTool(host: host, bake: baker.call),
      host: host,
      baker: baker,
      cel: cel,
    );
  }

  BitmapSurface pictureOf(CelTextCel cel) =>
      cel.coordinator.currentSurfaceOf(cel.key);

  List<(int, String)> textsOn(CelTextCel cel) => [
    for (final text in pictureOf(cel).texts) (text.id, text.content.text),
  ];

  /// What the canvas draws for [cel], as one picture — null: the cel as it
  /// is. What it draws in the cel's place, with what floats over that
  /// (F-344) laid on top in its order: the text in hand as it is shown,
  /// then the texts of the cel above it.
  BitmapSurface? shownFor(CelTextTool tool, CelTextCel cel) {
    final picture = pictureOf(cel);
    final hole = tool.onCanvas.shownSurfaceFor(cel.key, picture);
    final floating = tool.onCanvas.floatingOn(cel.key, picture);
    if (floating == null) {
      return hole;
    }
    final session = tool.session!;
    final shown = session.shown;
    final under = hole ?? picture;
    return under.withTexts([
      ...under.texts,
      if (!shown.content.isEmpty)
        CelText(
          id: session.textId ?? nextCelTextId(under.texts),
          content: shown.content,
          plate: shown.plate,
        ),
      ...floating.above,
    ]);
  }

  /// The keyboard leaves [text] in the field of the text in hand.
  void typeInto(CelTextTool tool, String text) {
    tool.letters!.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  final at = CanvasPoint(x: 8, y: 8);

  /// Another cel of the same stack.
  const elsewhere = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('another'),
  );

  group('a new text', () {
    test('begins in hand by its LETTERS, the caret in it — and nothing of '
        'it is on the cel or on the canvas', () {
      final (:tool, :host, :baker, :cel) = hand();

      tool.beginText(cel, at);

      expect(tool.hold, CelTextHold.letters);
      expect(tool.letters!.text, '');
      expect(tool.letters!.selection, const TextSelection.collapsed(offset: 0));
      expect(tool.session!.textId, isNull);
      expect(tool.session!.content.anchor, at);
      expect(tool.session!.content.wrapWidth, isNull);
      expect(shownFor(tool, cel), isNull);
      expect(textsOn(cel), isEmpty);
      expect(host.ran, isEmpty);
      expect(baker.asked, isEmpty);
    });

    test('starts as the tool\'s settings say, and as wide as it was '
        'dragged', () {
      final (:tool, :host, baker: _, :cel) = hand();
      const big = TextLetterStyle(fontSize: 16, color: 0xFFFF0000);
      host.options = const TextToolOptions(
        letters: big,
        align: TextCelAlign.center,
        lineHeight: 2,
        backgroundColor: 0xFF00FF00,
      );

      tool.beginText(cel, at, wrapWidth: 24);
      typeInto(tool, 'a');

      final content = tool.session!.content;
      expect(content.spans, [run('a', big)]);
      expect(content.paragraphs.single.align, TextCelAlign.center);
      expect(content.paragraphs.single.lineHeight, 2);
      expect(content.backgroundColor, 0xFF00FF00);
      expect(content.wrapWidth, 24);
    });

    test('🚨typed into, it is on the canvas once baked while the cel hears '
        'nothing — and letting go of the LETTERS lands it as one step, the '
        'text still in hand by its box', () async {
      final (:tool, :host, :baker, :cel) = hand();
      tool.beginText(cel, at);

      typeInto(tool, 'ab');

      expect(baker.asked.single.content.text, 'ab');
      expect(shownFor(tool, cel), isNull, reason: 'not baked yet');

      await baker.pending.answer();

      expect(shownFor(tool, cel)!.texts.single.content.text, 'ab');
      expect(textsOn(cel), isEmpty);
      expect(host.ran, isEmpty);

      tool.stopTyping();

      expect(host.ran, hasLength(1));
      expect(host.history.undoCount, 1);
      expect(textsOn(cel), [(1, 'ab')]);
      expect(tool.hold, CelTextHold.box);
      expect(tool.letters, isNull);
      expect(tool.session!.textId, 1, reason: 'it is the cel\'s text now');
      expect(shownFor(tool, cel), isNull, reason: 'the cel carries it');
    });

    test('confirm lands it and lets go of it', () async {
      final (:tool, :host, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'ab');
      await baker.pending.answer();

      tool.confirm();

      expect(tool.session, isNull);
      expect(tool.letters, isNull);
      expect(tool.holdsAnything, isFalse);
      expect(host.ran, hasLength(1));
      expect(textsOn(cel), [(1, 'ab')]);
    });

    test('a text let go of is DONE WITH: nothing listens to it any more, and '
        'the letters it had set are let go of with it', () async {
      final (:tool, host: _, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'ab');
      await baker.pending.answer();
      final session = tool.session!;

      tool.confirm();

      // What a session that was disposed of says of a new listener.
      expect(() => session.addListener(() {}), throwsFlutterError);
    });

    test('🚨a landing says the FACES its letters are written in — each '
        'once, the app\'s own left unsaid — and a text taken off its cel '
        'says none', () async {
      final sans = plain.copyWith(fontFamily: 'Probe Sans');
      final serif = plain.copyWith(fontFamily: 'Probe Serif');
      final (:tool, :host, :baker, :cel) = hand(
        texts: [
          carried(
            4,
            said([run('ab', sans), run('cd'), run('ef', serif), run('g', sans)]),
          ),
        ],
      );
      tool.takeText(cel, pictureOf(cel).texts.single);

      tool.changeLetters((style) => style.copyWith(fontSize: 16));
      await baker.pending.answer();

      expect(host.ran, hasLength(1), reason: '⛔fixture: it landed');
      expect(host.setInOf, [
        {'Probe Sans', 'Probe Serif'},
      ]);

      tool.deleteText();

      expect(host.ran, hasLength(2), reason: '⛔fixture: it was deleted');
      expect(host.setInOf.last, isEmpty);
    });

    test('beginning ANOTHER text lands the one in hand first', () async {
      final (:tool, :host, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'ab');
      await baker.pending.answer();
      final there = CanvasPoint(x: 16, y: 16);

      tool.beginText(cel, there);

      expect(host.ran, hasLength(1));
      expect(textsOn(cel), [(1, 'ab')]);
      expect(tool.session!.textId, isNull, reason: 'a new one is in hand');
      expect(tool.session!.content.anchor, there);
      expect(tool.letters!.text, '');
    });

    test('let go of with NO letters, it leaves nothing — no text and no '
        'step — by either way out', () {
      final (:tool, :host, baker: _, :cel) = hand();

      tool
        ..beginText(cel, at)
        ..confirm();

      expect(tool.session, isNull);
      expect(tool.holdsAnything, isFalse);

      tool
        ..beginText(cel, at)
        ..stopTyping();

      expect(tool.session, isNull, reason: 'nothing to hold by its box');
      expect(host.ran, isEmpty);
      expect(textsOn(cel), isEmpty);
    });
  });

  group('let go of before its last letters are baked', () {
    test('🚨it stays on the canvas as it was last made, the hand free for '
        'another — and lands once it is whole', () async {
      final (:tool, :host, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'a');
      await baker.pending.answer();
      typeInto(tool, 'ab');

      tool.confirm();

      expect(tool.session, isNull);
      expect(tool.holdsAnything, isTrue, reason: 'a landing is still owed');
      expect(host.ran, isEmpty);
      expect(textsOn(cel), isEmpty);
      expect(shownFor(tool, cel)!.texts.single.content.text, 'a');

      await baker.pending.answer();

      expect(host.ran, hasLength(1));
      expect(textsOn(cel), [(1, 'ab')]);
      expect(tool.holdsAnything, isFalse);
      expect(shownFor(tool, cel), isNull);
    });

    test('landNow lands what is SHOWN, at once, and gives the last want '
        'up: the engine\'s late answer changes nothing', () async {
      final (:tool, :host, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'a');
      await baker.pending.answer();
      typeInto(tool, 'ab');

      tool.landNow();

      expect(host.ran, hasLength(1));
      expect(textsOn(cel), [(1, 'a')]);
      expect(tool.session, isNull);
      expect(tool.holdsAnything, isFalse);

      await baker.pending.answer();

      expect(host.ran, hasLength(1));
      expect(textsOn(cel), [(1, 'a')]);
    });

    test('a text already on its way out is landed by landNow too — once', () async {
      final (:tool, :host, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'a');
      await baker.pending.answer();
      typeInto(tool, 'ab');
      tool.confirm();
      expect(tool.holdsAnything, isTrue, reason: '⛔fixture');

      tool.landNow();
      await baker.pending.answer();

      expect(host.ran, hasLength(1));
      expect(textsOn(cel), [(1, 'a')]);
      expect(tool.holdsAnything, isFalse);
    });

    test('landNow lands them IN THE ORDER THEY WERE LET GO OF, the one in '
        'hand last: history has them in the order they were made', () async {
      final (:tool, :host, :baker, :cel) = hand(
        texts: [carried(4, said([run('zz')], x: 16, y: 16))],
      );
      tool.beginText(cel, at);
      typeInto(tool, 'a');
      await baker.pending.answer();
      typeInto(tool, 'ab');
      // The second taken: the first is let go of, its last want owed.
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, 'zzz');
      await baker.asked.last.answer();
      expect(host.ran, isEmpty, reason: '⛔fixture: neither has landed');

      tool.landNow();

      expect(textsOn(cel), [(4, 'zzz'), (5, 'a')]);
      host.history.undo();
      expect(
        textsOn(cel),
        [(4, 'zz'), (5, 'a')],
        reason: 'the one in hand landed LAST: it is the first taken back',
      );
    });

    test('🚨DELETED while a landing of it was still owed, it stays deleted: '
        'the engine\'s late answer lands nothing', () async {
      final (:tool, :host, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'a');
      await baker.pending.answer();
      typeInto(tool, 'ab');
      tool.stopTyping();
      expect(host.ran, isEmpty, reason: '⛔fixture: the landing is owed');

      tool.deleteText();
      await baker.pending.answer();

      expect(host.ran, isEmpty);
      expect(textsOn(cel), isEmpty);
      expect(tool.holdsAnything, isFalse);
    });

    test('the letters taken up again before it settled: the visit goes on, '
        'and lands once, when it ends', () async {
      final (:tool, :host, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'ab');
      tool.stopTyping();
      expect(tool.hold, CelTextHold.box, reason: '⛔fixture');
      expect(host.ran, isEmpty, reason: '⛔fixture: not baked');

      tool.typeAt(const TextSelection.collapsed(offset: 2));
      await baker.pending.answer();

      expect(host.ran, isEmpty, reason: 'the letters are held again');

      typeInto(tool, 'abc');
      await baker.pending.answer();
      tool.stopTyping();

      expect(host.ran, hasLength(1));
      expect(textsOn(cel), [(1, 'abc')]);
    });
  });

  group('a text the cel carries', () {
    test('taken, it is in hand by its BOX exactly as the cel carries it: '
        'nothing to draw differently, and nothing to land', () {
      final (:tool, :host, :baker, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );

      tool.takeText(cel, pictureOf(cel).texts.single);

      expect(tool.hold, CelTextHold.box);
      expect(tool.session!.textId, 4);
      expect(shownFor(tool, cel), isNull);

      tool.confirm();

      expect(host.ran, isEmpty);
      expect(baker.asked, isEmpty);
    });

    test('taking the text already in hand keeps the hand on it and lets go '
        'of its letters', () {
      final (:tool, host: _, baker: _, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );
      final text = pictureOf(cel).texts.single;
      tool
        ..takeText(cel, text)
        ..typeAt(const TextSelection.collapsed(offset: 1));
      final session = tool.session;

      tool.takeText(cel, text);

      expect(tool.session, same(session));
      expect(tool.hold, CelTextHold.box);
    });

    test('the same id on ANOTHER cel is another text: taking it lets go of '
        'the one in hand', () {
      final (:tool, host: _, baker: _, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );
      cel.coordinator.restoreSurfaceSnapshot(
        elsewhere,
        drawingOf(const {}).withTexts([carried(4, said([run('zz')]))]),
      );
      final CelTextCel other = (
        key: elsewhere,
        coordinator: cel.coordinator,
        canvasSize: cel.canvasSize,
        cacheInvalidationSink: null,
      );
      tool.takeText(cel, pictureOf(cel).texts.single);
      final first = tool.session;

      tool.takeText(other, pictureOf(other).texts.single);

      expect(tool.session, isNot(same(first)));
      expect(tool.session!.key, elsewhere);
      expect(tool.session!.content.text, 'zz');
    });

    test('taking ANOTHER lands the one in hand first', () async {
      final (:tool, :host, :baker, :cel) = hand(
        texts: [
          carried(4, said([run('ab')])),
          carried(5, said([run('zz')], x: 16, y: 16)),
        ],
      );
      final texts = pictureOf(cel).texts;
      tool
        ..takeText(cel, texts[0])
        ..typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, 'abc');
      await baker.pending.answer();

      tool.takeText(cel, texts[1]);

      expect(host.ran, hasLength(1));
      expect(textsOn(cel), [(4, 'abc'), (5, 'zz')]);
      expect(tool.session!.textId, 5);
      expect(tool.hold, CelTextHold.box);
    });

    test('deleteText takes it off its cel as one step and lets go of it', () {
      final (:tool, :host, baker: _, :cel) = hand(
        texts: [
          carried(4, said([run('ab')])),
          carried(5, said([run('zz')], x: 16, y: 16)),
        ],
      );
      tool.takeText(cel, pictureOf(cel).texts.first);

      tool.deleteText();

      expect(textsOn(cel), [(5, 'zz')]);
      expect(tool.session, isNull);
      expect(host.ran.single.command.description, 'Delete text');

      host.history.undo();

      expect(textsOn(cel), [(4, 'ab'), (5, 'zz')]);
    });

    test('a text that never landed is simply gone: no step', () async {
      final (:tool, :host, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'ab');
      await baker.pending.answer();

      tool.deleteText();

      expect(host.ran, isEmpty);
      expect(tool.session, isNull);
      expect(tool.holdsAnything, isFalse);
      expect(shownFor(tool, cel), isNull);
    });
  });

  // 「그림으로 굳히기」 — 유저 2026-10-06: 「텍스트 그림으로 굳히기 아이디어
  // 좋네 … 동작은 텍스트 선택하면 해당 버튼 활성화색」.
  group('the text in hand turned into drawing', () {
    /// The tile the stand-in bakes a text anchored at (8, 8) to.
    final plateTile = TileCoord(x: 1, y: 1);

    /// What the cel SHOWS: its drawing with its texts laid.
    BitmapSurface shownOn(CelTextCel cel) =>
        celSurfaceWithTextsLaid(pictureOf(cel));

    List<String> stepsOf(_Host host) => [
      for (final ran in host.ran) ran.command.description,
    ];

    /// One pixel of [cel]'s DRAWING at the plate's tile — the stand-in
    /// writes how many letters the text has into its first byte.
    List<int>? drawnAt(CelTextCel cel, int x, int y) =>
        pixelOf(pictureOf(cel), plateTile, x, y);

    test('🚨it is its cel\'s DRAWING and no text of it — one step, and the '
        'hand is free; the cel shows what it showed; one undo gives the '
        'text back', () {
      final (:tool, :host, baker: _, :cel) = hand(
        texts: [
          carried(4, said([run('ab')])),
          carried(5, said([run('zz')], x: 16, y: 16)),
        ],
      );
      final showed = shownOn(cel);
      expect(drawnAt(cel, 0, 0), isNull, reason: '⛔fixture: bare paper');
      tool.takeText(cel, pictureOf(cel).texts.first);

      tool.turnIntoDrawing();

      expect(textsOn(cel), [(5, 'zz')]);
      expect(drawnAt(cel, 0, 0), [2, 0, 0, 255]);
      expect(shownOn(cel), showed);
      expect(tool.session, isNull);
      expect(tool.holdsAnything, isFalse);
      expect(stepsOf(host), ['Text to drawing']);
      expect(host.setInOf.single, isEmpty, reason: 'it registers no face');
      expect(host.ran.single.withCelMadeSince, isNull);

      host.history.undo();

      expect(textsOn(cel), [(4, 'ab'), (5, 'zz')]);
      expect(drawnAt(cel, 0, 0), isNull);
    });

    test('🚨what was typed lands FIRST, a step of its own: one undo gives '
        'the text back AS IT WAS TYPED, a second the cel as it was before '
        'the visit', () async {
      final (:tool, :host, :baker, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, 'abc');
      await baker.pending.answer();

      tool.turnIntoDrawing();

      expect(stepsOf(host), ['Set text', 'Text to drawing']);
      expect(textsOn(cel), isEmpty);
      expect(drawnAt(cel, 0, 0), [3, 0, 0, 255]);
      expect(tool.session, isNull);
      expect(tool.letters, isNull);

      host.history.undo();
      expect(textsOn(cel), [(4, 'abc')]);
      host.history.undo();
      expect(textsOn(cel), [(4, 'ab')]);
    });

    test('a NEW text is set on its cel — with the cel its press made — and '
        'then turned: the turning takes no cel with it', () async {
      final (:tool, :host, :baker, :cel) = hand();
      tool.beginText(cel, at, celMadeSince: host.gestures.mark);
      typeInto(tool, 'ab');
      await baker.pending.answer();

      tool.turnIntoDrawing();

      expect(stepsOf(host), ['Set text', 'Text to drawing']);
      expect(host.ran.first.withCelMadeSince, isNotNull);
      expect(host.ran.last.withCelMadeSince, isNull);
      expect(textsOn(cel), isEmpty);
      expect(drawnAt(cel, 0, 0), [2, 0, 0, 255]);

      host.history.undo();
      expect(textsOn(cel), [(1, 'ab')]);
    });

    test('🚨its last want still being set, it stays on the canvas as it was '
        'last made and is NOBODY\'S TEXT — no box, nothing to take, no row '
        '— and turns once it is set', () async {
      final (:tool, :host, :baker, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, 'abc');
      expect(tool.takeableOn(cel), hasLength(1), reason: '⛔fixture');

      tool.turnIntoDrawing();

      expect(tool.session, isNull);
      expect(tool.holdsAnything, isTrue, reason: 'a landing is still owed');
      expect(host.ran, isEmpty);
      expect(textsOn(cel), [(4, 'ab')], reason: 'still a text of the cel');
      expect(tool.onCanvas.restingBoxesOn(cel.key, pictureOf(cel)), isEmpty);
      expect(tool.takeableOn(cel), isEmpty);
      expect(tool.list.texts, isEmpty);
      tool.list.take(4);
      expect(tool.session, isNull, reason: 'the list takes none of it');

      await baker.pending.answer();

      expect(stepsOf(host), ['Set text', 'Text to drawing']);
      expect(textsOn(cel), isEmpty);
      expect(drawnAt(cel, 0, 0), [3, 0, 0, 255]);
      expect(tool.holdsAnything, isFalse);
      expect(shownFor(tool, cel), isNull);
    });

    test('⛔CONTROL: a text merely let go of while its last want is being '
        'set keeps its box and its row — it is still a text', () async {
      final (:tool, host: _, :baker, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, 'abc');

      tool.confirm();

      expect(tool.holdsAnything, isTrue, reason: '⛔fixture');
      expect(
        tool.onCanvas.restingBoxesOn(cel.key, pictureOf(cel)),
        hasLength(1),
      );
      expect(tool.takeableOn(cel), hasLength(1));
      expect(tool.list.texts, hasLength(1));
      await baker.pending.answer();
    });

    test('a text on ANOTHER cel on its way into the drawing hides none of '
        'this one\'s', () async {
      final (:tool, host: _, :baker, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );
      cel.coordinator.restoreSurfaceSnapshot(
        elsewhere,
        drawingOf(const {}).withTexts([carried(4, said([run('zz')]))]),
      );
      final CelTextCel there = (
        key: elsewhere,
        coordinator: cel.coordinator,
        canvasSize: cel.canvasSize,
        cacheInvalidationSink: null,
      );
      tool
        ..takeText(there, pictureOf(there).texts.single)
        ..typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, 'zzz');
      tool.turnIntoDrawing();
      expect(tool.holdsAnything, isTrue, reason: '⛔fixture');

      expect(tool.takeableOn(cel), hasLength(1));
      expect(tool.takeableOn(there), isEmpty);
      await baker.pending.answer();
    });

    test('whoever cannot wait (landNow) turns it AS IT IS SHOWN, at once: '
        'the last want is given up, and the engine\'s late answer changes '
        'nothing', () async {
      final (:tool, :host, :baker, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, 'abc');
      tool.turnIntoDrawing();

      tool.landNow();

      expect(stepsOf(host), ['Text to drawing']);
      expect(textsOn(cel), isEmpty);
      expect(drawnAt(cel, 0, 0), [2, 0, 0, 255]);
      expect(tool.holdsAnything, isFalse);

      await baker.pending.answer();

      expect(host.ran, hasLength(1));
      expect(textsOn(cel), isEmpty);
    });

    test('a save meanwhile (landShown) lands it as shown and it is still a '
        'text in the file; it turns when its last want is set', () async {
      final (:tool, :host, :baker, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, 'abc');
      await baker.pending.answer();
      typeInto(tool, 'abcd');
      tool.turnIntoDrawing();

      expect(tool.landShown(), isTrue);

      expect(stepsOf(host), ['Set text']);
      expect(textsOn(cel), [(4, 'abc')]);
      expect(tool.holdsAnything, isTrue);

      await baker.pending.answer();

      expect(stepsOf(host), ['Set text', 'Set text', 'Text to drawing']);
      expect(textsOn(cel), isEmpty);
      expect(drawnAt(cel, 0, 0), [4, 0, 0, 255]);
    });

    test('a text with NO letters is let go of and nothing is turned: a new '
        'one leaves no step, one emptied is taken off its cel', () async {
      final (:tool, :host, :baker, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );
      tool
        ..beginText(cel, at)
        ..turnIntoDrawing();

      expect(host.ran, isEmpty);
      expect(tool.session, isNull);

      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, '');
      // No letters are no bake: what is shown follows by itself.
      await pumpEventQueue();
      expect(baker.asked, isEmpty, reason: '⛔fixture');
      tool.turnIntoDrawing();

      expect(stepsOf(host), ['Delete text']);
      expect(textsOn(cel), isEmpty);
      expect(drawnAt(cel, 0, 0), isNull);
    });

    test('with nothing in hand it does nothing', () {
      final (:tool, :host, baker: _, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );

      tool.turnIntoDrawing();

      expect(host.ran, isEmpty);
      expect(textsOn(cel), [(4, 'ab')]);
    });

    // 🗣️유저 2026-10-07 (`R9-rest-Q5`, asked whether the texts under it that
    // it covers turn with it): 「고른 텍스트만 굳힌다」. So nothing else the
    // hand holds is touched by the turning — a text under it least of all.
    group('with a text under it that it covers', () {
      /// A text over [said]'s tile that covers ONE pixel of it — so the
      /// drawing under it can be read beside that pixel.
      CelText covering(int id) => CelText(
        id: id,
        content: said([run('zz')]),
        plate: {
          plateTile: tileOf({
            (0, 0): [77, 0, 0, 255],
          }),
        },
      );

      test('🚨the one under it STAYS A TEXT of its cel, and nothing of it '
          'is in the drawing — one still owed its landing lands in its own '
          'time, a step of its own', () async {
        final (:tool, :host, :baker, :cel) = hand(
          texts: [carried(1, said([run('ab')])), covering(2)],
        );
        tool
          ..takeText(cel, pictureOf(cel).texts.first)
          ..typeAt(const TextSelection.collapsed(offset: 2));
        typeInto(tool, 'abc');
        await baker.pending.answer();
        typeInto(tool, 'abcd');
        // The upper one taken: the lower is let go of, its last want owed.
        tool.takeText(cel, pictureOf(cel).texts.last);
        expect(tool.holdsAnything, isTrue, reason: '⛔fixture');
        expect(host.ran, isEmpty, reason: '⛔fixture: nothing landed yet');

        tool.turnIntoDrawing();

        expect(stepsOf(host), ['Text to drawing']);
        expect(textsOn(cel), [(1, 'ab')], reason: 'not landed by this');
        expect(drawnAt(cel, 0, 0), [77, 0, 0, 255], reason: 'the one picked');
        expect(drawnAt(cel, 1, 1), [0, 0, 0, 0], reason: 'none of the other');
        expect(tool.holdsAnything, isTrue, reason: 'the other is still owed');

        await baker.pending.answer();

        expect(stepsOf(host), ['Text to drawing', 'Set text']);
        expect(textsOn(cel), [(1, 'abcd')]);
        expect(drawnAt(cel, 1, 1), [0, 0, 0, 0]);
        expect(tool.holdsAnything, isFalse);
      });

      test('🚨one IN HAND stays in hand, its letters open, a text of its '
          'cel', () async {
        final (:tool, host: _, :baker, :cel) = hand(
          texts: [carried(1, said([run('ab')])), covering(2)],
        );
        tool
          ..takeText(cel, pictureOf(cel).texts.last)
          ..typeAt(const TextSelection.collapsed(offset: 2));
        typeInto(tool, 'zzz');
        tool.turnIntoDrawing();
        // The lower one taken and typed into while the upper is on its way.
        tool
          ..takeText(cel, pictureOf(cel).texts.first)
          ..typeAt(const TextSelection.collapsed(offset: 2));
        expect(tool.session!.textId, 1, reason: '⛔fixture');

        await baker.pending.answer();

        expect(textsOn(cel), [(1, 'ab')]);
        expect(drawnAt(cel, 0, 0), [3, 0, 0, 255], reason: 'the one picked');
        expect(tool.session!.textId, 1);
        expect(tool.letters, isNotNull);
      });
    });
  });

  group('a LETTER setting changed on the text in hand', () {
    final mixed = said([run('ab'), run('cd', red)]);

    test('🚨held by its BOX it reaches every letter, each keeping what the '
        'change leaves alone — one step, the text still in hand', () async {
      final (:tool, :host, :baker, :cel) = hand(texts: [carried(4, mixed)]);
      tool.takeText(cel, pictureOf(cel).texts.single);

      tool.changeLetters((style) => style.copyWith(fontSize: 16));

      final sized = [
        run('ab', plain.copyWith(fontSize: 16)),
        run('cd', red.copyWith(fontSize: 16)),
      ];
      expect(baker.asked.single.content.spans, sized);
      expect(host.ran, isEmpty, reason: 'a step holds a whole text');

      await baker.pending.answer();

      expect(host.ran, hasLength(1));
      expect(pictureOf(cel).texts.single.content.spans, sized);
      expect(tool.hold, CelTextHold.box);
      expect(tool.session!.textId, 4);

      host.history.undo();

      expect(pictureOf(cel).texts.single.content, mixed);
    });

    test('🚨with letters SELECTED it reaches those alone; with a caret and '
        'none selected, every letter', () {
      final (:tool, host: _, baker: _, :cel) = hand(
        texts: [carried(4, mixed)],
      );
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection(baseOffset: 3, extentOffset: 1))
        ..changeLetters((style) => style.copyWith(bold: true));

      expect(tool.letters!.content.spans, [
        run('a'),
        run('b', plain.copyWith(bold: true)),
        run('c', red.copyWith(bold: true)),
        run('d', red),
      ]);

      tool
        ..typeAt(const TextSelection.collapsed(offset: 2))
        ..changeLetters((style) => style.copyWith(letterSpacing: 3));

      expect(
        [for (final span in tool.letters!.content.spans) span.style],
        everyElement(
          isA<TextLetterStyle>().having(
            (style) => style.letterSpacing,
            'letterSpacing',
            3,
          ),
        ),
      );
      expect(tool.letters!.content.spans, hasLength(4));
    });

    test('while the LETTERS are held it is part of the visit: a step back '
        'in the field, and it lands with the letters — once', () async {
      final (:tool, :host, :baker, :cel) = hand(texts: [carried(4, mixed)]);
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection.collapsed(offset: 4))
        ..changeLetters((style) => style.copyWith(fontSize: 16));

      expect(tool.letters!.canUndo, isTrue);

      await baker.pending.answer();

      expect(host.ran, isEmpty, reason: 'the visit is not over');

      tool.stopTyping();

      expect(host.ran, hasLength(1));
      expect(
        pictureOf(cel).texts.single.content.spans.first.style.fontSize,
        16,
      );
    });

    test('🚨tried and taken back within one visit, it lands NOTHING: the '
        'text is the one the cel carries, and history has no empty step', () async {
      final (:tool, :host, :baker, :cel) = hand(texts: [carried(4, mixed)]);
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection.collapsed(offset: 4))
        ..changeLetters((style) => style.copyWith(fontSize: 16));
      await baker.pending.answer();

      tool.letters!.undo();
      await baker.pending.answer();
      tool.stopTyping();

      expect(host.ran, isEmpty);
      expect(host.history.undoCount, 0);
      expect(pictureOf(cel).texts.single.content, mixed);
    });

    test('a value still being dragged is shown and does not land; the one '
        'it comes to rest on lands them as ONE step', () async {
      final (:tool, :host, :baker, :cel) = hand(texts: [carried(4, mixed)]);
      tool.takeText(cel, pictureOf(cel).texts.single);
      double sizeOf(BitmapSurface surface) =>
          surface.texts.single.content.spans.first.style.fontSize;

      tool.changeLetters((s) => s.copyWith(fontSize: 9), settled: false);
      await baker.pending.answer();
      tool.changeLetters((s) => s.copyWith(fontSize: 10), settled: false);
      await baker.pending.answer();

      expect(host.ran, isEmpty);
      expect(sizeOf(shownFor(tool, cel)!), 10);
      expect(sizeOf(pictureOf(cel)), 8);

      tool.changeLetters((s) => s.copyWith(fontSize: 11));

      expect(host.ran, isEmpty, reason: 'not baked yet');

      await baker.pending.answer();

      expect(host.ran, hasLength(1));
      expect(sizeOf(pictureOf(cel)), 11);

      host.history.undo();

      expect(sizeOf(pictureOf(cel)), 8);
    });

    test('dragged while the letters are held, it is ONE step back in the '
        'field', () {
      final (:tool, host: _, baker: _, :cel) = hand(
        texts: [carried(4, mixed)],
      );
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection.collapsed(offset: 4))
        ..changeLetters((s) => s.copyWith(fontSize: 9), settled: false)
        ..changeLetters((s) => s.copyWith(fontSize: 10), settled: false)
        ..changeLetters((s) => s.copyWith(fontSize: 11));

      tool.letters!.undo();

      expect(tool.letters!.content, mixed);
      expect(tool.letters!.canUndo, isFalse);

      // The next change is a step of its own, not one more value of that.
      tool
        ..changeLetters((s) => s.copyWith(fontSize: 12))
        ..changeLetters((s) => s.copyWith(fontSize: 13));
      tool.letters!.undo();

      expect(tool.letters!.content.spans.first.style.fontSize, 12);
    });

    test('on a text with NO letters it is the next letter\'s — the caret '
        'grows with it, and the letter then typed wears it', () {
      final (:tool, host: _, baker: _, :cel) = hand();
      tool
        ..beginText(cel, at)
        ..changeLetters((style) => style.copyWith(fontSize: 16));

      expect(tool.letters!.nextLetterStyle.fontSize, 16);
      expect(tool.session!.nextLetterStyle.fontSize, 16);
      expect(tool.session!.shown.layout.block.height, 20);

      typeInto(tool, 'a');

      expect(tool.letters!.content.spans.single.style.fontSize, 16);
    });

    test('after a bake the engine refused, a setting still reaches the '
        'letters the FIELD holds — every one typed', () async {
      final (:tool, host: _, :baker, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, 'abc');
      await baker.pending.refuse(StateError('no raster'));
      expect(tool.session!.content.text, 'ab', reason: '⛔fixture: the want');

      tool
        ..changeLetters((style) => style.copyWith(bold: true))
        ..changeBox((content) => content.copyWith(letterWidth: 0.5));

      final held = tool.letters!.content;
      expect(held.text, 'abc');
      expect(held.spans.single.style.bold, isTrue);
      expect(held.letterWidth, 0.5);
    });

    test('with nothing in hand it changes nothing', () {
      final (:tool, :host, :baker, cel: _) = hand();

      tool
        ..changeLetters((style) => style.copyWith(fontSize: 16))
        ..changeBox((content) => content.copyWith(letterWidth: 0.5));

      expect(host.ran, isEmpty);
      expect(baker.asked, isEmpty);
    });
  });

  group('a PARAGRAPH setting changed on the text in hand', () {
    const right = CelTextParagraph(align: TextCelAlign.right, lineHeight: 2);
    const apart = CelTextParagraph(align: TextCelAlign.center, lineHeight: 3);
    // 「ab」 set to the right, then 「cd」 set apart.
    final two = CelTextContent(
      spans: [run('ab\ncd')],
      anchor: CanvasPoint(x: 8, y: 8),
      paragraphs: const [right, apart],
    );
    CelTextParagraph centred(CelTextParagraph paragraph) =>
        paragraph.copyWith(align: TextCelAlign.center);

    test('🚨held by its BOX it reaches every paragraph, each keeping what '
        'the change leaves alone — one step, the text still in hand', () async {
      final (:tool, :host, :baker, :cel) = hand(texts: [carried(4, two)]);
      tool.takeText(cel, pictureOf(cel).texts.single);

      tool.changeParagraphs(centred);
      await baker.pending.answer();

      expect(host.ran, hasLength(1));
      expect(pictureOf(cel).texts.single.content.paragraphs, const [
        CelTextParagraph(align: TextCelAlign.center, lineHeight: 2),
        apart,
      ]);
      expect(tool.hold, CelTextHold.box);

      host.history.undo();

      expect(pictureOf(cel).texts.single.content, two);
    });

    test('🚨with letters SELECTED it reaches the paragraphs they are in '
        'alone; with a caret and none selected, every one', () {
      final (:tool, host: _, baker: _, :cel) = hand(texts: [carried(4, two)]);
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection(baseOffset: 4, extentOffset: 3))
        ..changeParagraphs((paragraph) => paragraph.copyWith(lineHeight: 5));

      expect(tool.letters!.content.paragraphs, const [
        right,
        CelTextParagraph(align: TextCelAlign.center, lineHeight: 5),
      ]);

      tool
        ..typeAt(const TextSelection.collapsed(offset: 1))
        ..changeParagraphs((paragraph) => paragraph.copyWith(lineHeight: 4));

      expect([
        for (final paragraph in tool.letters!.content.paragraphs)
          paragraph.lineHeight,
      ], [4, 4]);
    });

    test('what it shows is how those paragraphs are set — the selection\'s, '
        'or with none selected every one', () {
      final (:tool, host: _, baker: _, :cel) = hand(texts: [carried(4, two)]);

      expect(tool.paragraphsSpokenFor, isNull, reason: 'nothing in hand');

      tool.takeText(cel, pictureOf(cel).texts.single);

      expect(tool.paragraphsSpokenFor, [right, apart]);

      tool.typeAt(const TextSelection(baseOffset: 0, extentOffset: 3));

      expect(tool.paragraphsSpokenFor, [right], reason: '「ab」 and its break');

      tool.typeAt(const TextSelection(baseOffset: 1, extentOffset: 4));

      expect(tool.paragraphsSpokenFor, [right, apart]);
    });
  });

  group('a setting of the WHOLE TEXT', () {
    test('reaches the text in hand as one step', () async {
      final (:tool, :host, :baker, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..changeBox((content) => content.copyWith(letterWidth: 0.5));
      await baker.pending.answer();

      expect(host.ran, hasLength(1));
      expect(pictureOf(cel).texts.single.content.letterWidth, 0.5);
    });

    test('a value still being dragged is shown and does not land; the one '
        'it comes to rest on lands them as ONE step', () async {
      final (:tool, :host, :baker, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );
      tool.takeText(cel, pictureOf(cel).texts.single);
      double widthOf(BitmapSurface surface) =>
          surface.texts.single.content.letterWidth;
      final before = widthOf(pictureOf(cel));

      tool.changeBox(
        (content) => content.copyWith(letterWidth: 0.5),
        settled: false,
      );
      await baker.pending.answer();
      tool.changeBox(
        (content) => content.copyWith(letterWidth: 0.75),
        settled: false,
      );
      await baker.pending.answer();

      expect(host.ran, isEmpty);
      expect(widthOf(shownFor(tool, cel)!), 0.75);
      expect(widthOf(pictureOf(cel)), before);

      tool.changeBox((content) => content.copyWith(letterWidth: 0.25));

      expect(host.ran, isEmpty, reason: 'not baked yet');

      await baker.pending.answer();

      expect(host.ran, hasLength(1));
      expect(widthOf(pictureOf(cel)), 0.25);

      host.history.undo();

      expect(widthOf(pictureOf(cel)), before);
    });

    test('while the letters are held it is set on what is being TYPED, and '
        'lands with it', () async {
      final (:tool, :host, :baker, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, 'abc');

      tool.changeBox((content) => content.copyWith(letterWidth: 0.5));

      expect(tool.letters!.content.text, 'abc');
      expect(tool.letters!.content.letterWidth, 0.5);
      expect(host.ran, isEmpty);

      await baker.asked[0].answer();
      await baker.pending.answer();
      tool.stopTyping();

      final landed = pictureOf(cel).texts.single.content;
      expect(host.ran, hasLength(1));
      expect((landed.text, landed.letterWidth), ('abc', 0.5));
    });
  });

  group('what the canvas is given to draw', () {
    test('is for the cel the text is on, and no other', () async {
      final (:tool, host: _, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'a');
      await baker.pending.answer();

      expect(shownFor(tool, cel), isNotNull, reason: '⛔fixture');
      expect(tool.onCanvas.shownSurfaceFor(elsewhere, pictureOf(cel)), isNull);

      // And the same of a text on its way out, still drawn until it lands.
      typeInto(tool, 'ab');
      tool.confirm();

      expect(shownFor(tool, cel), isNotNull, reason: '⛔fixture');
      expect(tool.onCanvas.shownSurfaceFor(elsewhere, pictureOf(cel)), isNull);
    });

    test('the canvas is told when what it shows changes — a text begun, a '
        'bake landed, a text let go of', () async {
      final (:tool, :host, :baker, :cel) = hand();

      tool.beginText(cel, at);
      final begun = host.redrawn;
      expect(begun, greaterThan(0));

      typeInto(tool, 'ab');
      await baker.pending.answer();
      final baked = host.redrawn;
      expect(baked, greaterThan(begun));

      tool.confirm();
      expect(host.redrawn, greaterThan(baked));
    });

    test('🚨F-344: a text in hand shown otherwise is LIFTED — in the cel\'s '
        'place the cel without it and without the texts above it, and '
        'those float over it in their order', () {
      final below = carried(3, said([run('lo')]));
      final held = carried(4, said([run('ab')], x: 12));
      final over = carried(5, said([run('hi')], y: 14));
      final (:tool, host: _, baker: _, :cel) = hand(
        texts: [below, held, over],
      );
      tool.takeText(cel, held);
      final session = tool.session!;

      session.showMoved(session.moveOrigin, dx: 8, dy: 0);

      final picture = pictureOf(cel);
      final hole = tool.onCanvas.shownSurfaceFor(cel.key, picture)!;
      final floating = tool.onCanvas.floatingOn(cel.key, picture)!;
      expect([for (final text in hole.texts) text.id], [3]);
      expect(hole.tiles, picture.tiles, reason: 'the drawing stays');
      expect([for (final text in floating.above) text.id], [5]);
      expect(floating.under, same(hole));
      expect(floating.pixels.plate, same(held.plate));
      expect((floating.pixels.dx, floating.pixels.dy), (8, 0));
    });

    test('🚨F-344-Q3: a canvas that floats the LANDING is given the cel '
        'without the text in hand alone — the texts above it stay', () {
      final below = carried(3, said([run('lo')]));
      final held = carried(4, said([run('ab')], x: 12));
      final over = carried(5, said([run('hi')], y: 14));
      final (:tool, host: _, baker: _, :cel) = hand(
        texts: [below, held, over],
      );
      tool.takeText(cel, held);
      final session = tool.session!;
      expect(
        tool.onCanvas.shownWithoutFor(cel.key, pictureOf(cel)),
        isNull,
        reason: 'taken and not yet carried, it is shown as the cel has it',
      );

      session.showMoved(session.moveOrigin, dx: 8, dy: 0);

      final picture = pictureOf(cel);
      final without = tool.onCanvas.shownWithoutFor(cel.key, picture)!;
      expect([for (final text in without.texts) text.id], [3, 5]);
      expect(without.tiles, picture.tiles, reason: 'the drawing stays');
      expect(
        tool.onCanvas.shownWithoutFor(cel.key, picture),
        same(without),
        reason: 'one picture for the whole carry',
      );
    });

    test('🚨F-344: a hand carrying the text tells the panel only as the '
        'text lifts off and as it is put back — each move between is told '
        'on shownInHand alone', () {
      final standing = carried(4, said([run('ab')]));
      final (:tool, :host, baker: _, :cel) = hand(texts: [standing]);
      tool.takeText(cel, standing);
      final session = tool.session!;
      final origin = session.moveOrigin;
      final taken = host.redrawn;
      BitmapSurface? hole() =>
          tool.onCanvas.shownSurfaceFor(cel.key, pictureOf(cel));
      var moves = 0;
      var settings = 0;
      tool
        ..shownInHand.addListener(() => moves += 1)
        ..addListener(() => settings += 1);

      session.showMoved(origin, dx: 1, dy: 0);
      final lifted = hole();
      for (var dx = 2; dx <= 6; dx++) {
        session.showMoved(origin, dx: dx, dy: 0);
      }

      expect(host.redrawn, taken + 1, reason: 'lifted off, once');
      expect(moves, 6);
      expect(settings, 0, reason: 'a carry is no other text');
      expect(lifted, isNotNull, reason: '⛔fixture');
      expect(hole(), same(lifted), reason: 'one hole for the whole carry');
      expect(tool.shownInHand.value, same(session.shown));

      session.showMoved(origin, dx: 0, dy: 0);

      expect(host.redrawn, taken + 2, reason: 'put back');
      expect(hole(), isNull);
    });

    test('🚨F-344: letters typed into a text in hand tell the panel once, as '
        'the text lifts off — each bake after that is told on shownInHand '
        'alone', () async {
      final (:tool, :host, :baker, :cel) = hand();
      tool.beginText(cel, at);
      final begun = host.redrawn;
      typeInto(tool, 'a');
      await baker.pending.answer();
      expect(host.redrawn, begun + 1, reason: 'lifted off');
      var shown = 0;
      tool.shownInHand.addListener(() => shown += 1);

      for (final words in ['ab', 'abc']) {
        typeInto(tool, words);
        await baker.pending.answer();
      }

      expect(host.redrawn, begun + 1, reason: 'still lifted');
      expect(shown, 2);
      final floating = tool.onCanvas.floatingOn(cel.key, pictureOf(cel))!;
      expect(floating.pixels.plate, same(tool.session!.shown.plate));
    });

    test('🚨F-344: the text taken is on shownInHand at once — another '
        'taken is, and none is once it is let go of', () {
      final first = carried(4, said([run('ab')]));
      final second = carried(5, said([run('cd')], y: 24));
      final (:tool, host: _, baker: _, :cel) = hand(texts: [first, second]);

      tool.takeText(cel, first);
      final one = tool.shownInHand.value;
      tool.takeText(cel, second);
      final other = tool.shownInHand.value;
      final session = tool.session!;
      tool.confirm();

      expect(one?.content, first.content);
      expect(other, same(session.shown));
      expect(tool.shownInHand.value, isNull);
    });

    test('🚨F-344: a text carried and DELETED leaves nothing lifted — the '
        'next one carried lifts off in its turn, and the panel is told', () {
      final first = carried(4, said([run('ab')]));
      final second = carried(5, said([run('cd')], y: 24));
      final (:tool, :host, baker: _, :cel) = hand(texts: [first, second]);
      tool.takeText(cel, first);
      final one = tool.session!;
      one.showMoved(one.moveOrigin, dx: 4, dy: 0);
      tool
        ..deleteText()
        ..takeText(cel, second);
      final other = tool.session!;
      final taken = host.redrawn;

      other.showMoved(other.moveOrigin, dx: 4, dy: 0);

      expect(textsOn(cel), [(5, 'cd')], reason: '⛔fixture: deleted');
      expect(host.redrawn, taken + 1, reason: 'lifted off');
    });

    test('🚨F-344: the text in hand landed as it is shown is put back — '
        'and the panel is told', () {
      final standing = carried(4, said([run('ab')]));
      final (:tool, :host, baker: _, :cel) = hand(texts: [standing]);
      tool.takeText(cel, standing);
      final session = tool.session!;
      session.showMoved(session.moveOrigin, dx: 4, dy: 0);
      final carrying = host.redrawn;

      expect(tool.landShown(), isTrue);

      expect(host.redrawn, carrying + 1, reason: 'put back');
      expect(tool.onCanvas.shownSurfaceFor(cel.key, pictureOf(cel)), isNull);
    });

    test('🚨F-344: the text in hand landed as it is shown tells the panel '
        'ONCE that it is put back — with another let go of still owed its '
        'landing', () {
      final first = carried(4, said([run('ab')]));
      final second = carried(5, said([run('cd')], y: 24));
      final (:tool, :host, :baker, :cel) = hand(texts: [first, second]);
      tool
        ..takeText(cel, first)
        ..typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, 'abc');
      // The other taken: this one is let go of, its last want owed.
      tool.takeText(cel, second);
      final session = tool.session!;
      session.showMoved(session.moveOrigin, dx: 4, dy: 0);
      final carrying = host.redrawn;
      expect(
        baker.pending.content.text,
        'abc',
        reason: '⛔fixture: the one let go of is still owed its last want',
      );

      expect(tool.landShown(), isTrue);

      expect(host.ran, hasLength(1), reason: 'the one in hand, as shown');
      expect(host.redrawn, carrying + 1, reason: 'put back, once');
    });

    test('a NEW text has nothing above it: its hole is its cel, and it '
        'floats over all of the cel\'s texts', () async {
      final standing = carried(4, said([run('ab')]));
      final (:tool, host: _, :baker, :cel) = hand(texts: [standing]);
      tool.beginText(cel, CanvasPoint(x: 4, y: 20));
      typeInto(tool, 'cd');
      await baker.pending.answer();

      final picture = pictureOf(cel);
      final floating = tool.onCanvas.floatingOn(cel.key, picture)!;
      expect(tool.onCanvas.shownSurfaceFor(cel.key, picture), isNull);
      expect(floating.above, isEmpty);
      expect(floating.pixels.plate, same(tool.session!.shown.plate));
    });
  });

  group('the boxes of the texts in nobody\'s hand', () {
    /// The box [content] has on the canvas, its letters set afresh.
    List<Offset> boxOf(CelTextContent content) {
      final layout = layoutCelText(content);
      addTearDown(layout.dispose);
      return layout.boxCorners;
    }

    List<List<Offset>> resting(CelTextTool tool, CelTextCel cel) => [
      for (final box in tool.onCanvas.restingBoxesOn(cel.key, pictureOf(cel)))
        box.corners,
    ];

    final first = said([run('ab')]);
    final second = said([run('cde')], x: 40, y: 24);

    test('with nothing in hand: every text of the cel, as they are '
        'stacked', () {
      final (:tool, host: _, baker: _, :cel) = hand(
        texts: [carried(1, first), carried(2, second)],
      );

      expect(resting(tool, cel), [boxOf(first), boxOf(second)]);
      expect(boxOf(first), isNot(boxOf(second)), reason: '⛔fixture');
    });

    test('🚨the text IN HAND is not among them — its own box says it is '
        'the one', () {
      final (:tool, host: _, baker: _, :cel) = hand(
        texts: [carried(1, first), carried(2, second)],
      );

      tool.takeText(cel, pictureOf(cel).texts.last);

      expect(resting(tool, cel), [boxOf(first)]);

      tool.confirm();

      expect(resting(tool, cel), [boxOf(first), boxOf(second)]);
    });

    test('a text in hand speaks for none of ANOTHER cel\'s, whatever their '
        'ids', () {
      final (:tool, host: _, baker: _, :cel) = hand(
        texts: [carried(1, first), carried(2, second)],
      );
      tool.takeText(cel, pictureOf(cel).texts.last);

      expect(
        [
          for (final box in tool.onCanvas.restingBoxesOn(
            elsewhere,
            pictureOf(cel),
          ))
            box.corners,
        ],
        [boxOf(first), boxOf(second)],
      );
    });

    test('🚨a text let go of that still OWES its landing rests where it is '
        'SHOWN — not where the cel still carries it, and once', () async {
      final (:tool, host: _, :baker, :cel) = hand(texts: [carried(1, first)]);
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, 'abc');
      await baker.pending.answer();
      typeInto(tool, 'abcd');

      tool.confirm();

      expect(tool.session, isNull, reason: '⛔fixture');
      expect(tool.holdsAnything, isTrue, reason: '⛔fixture: a landing owed');
      expect(textsOn(cel), [(1, 'ab')], reason: '⛔fixture: not landed yet');
      expect(resting(tool, cel), [boxOf(said([run('abc')]))]);

      await baker.pending.answer();

      expect(textsOn(cel), [(1, 'abcd')], reason: '⛔fixture');
      expect(resting(tool, cel), [boxOf(said([run('abcd')]))]);
    });

    test('a text let go of on ANOTHER cel rests on none of this one\'s, and '
        'speaks for none of its texts', () async {
      final (:tool, host: _, :baker, :cel) = hand(texts: [carried(1, first)]);
      tool
        ..takeText(cel, pictureOf(cel).texts.single)
        ..typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, 'abc');
      await baker.pending.answer();
      typeInto(tool, 'abcd');
      tool.confirm();
      expect(tool.holdsAnything, isTrue, reason: '⛔fixture: a landing owed');

      // Another cel's picture, carrying a text of the very id.
      final other = drawingOf(const {}).withTexts([carried(1, second)]);

      expect(
        [
          for (final box in tool.onCanvas.restingBoxesOn(elsewhere, other))
            box.corners,
        ],
        [boxOf(second)],
      );
    });

    test('a NEW text let go of before anything of it was made rests '
        'nowhere, until it is', () async {
      final (:tool, host: _, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'a');

      tool.confirm();

      expect(tool.holdsAnything, isTrue, reason: '⛔fixture: a landing owed');
      expect(resting(tool, cel), isEmpty);

      await baker.pending.answer();

      expect(resting(tool, cel), [boxOf(pictureOf(cel).texts.single.content)]);
    });

    test('and one let go of mid-typing rests where its last letters were '
        'made, though the cel has none of it yet', () async {
      final (:tool, host: _, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'a');
      await baker.pending.answer();
      final shown = tool.session!.shown.content;
      typeInto(tool, 'ab');

      tool.confirm();

      expect(textsOn(cel), isEmpty, reason: '⛔fixture: not landed yet');
      expect(resting(tool, cel), [boxOf(shown)]);
    });
  });

  group('the texts of the cel under the hand, as the settings list them', () {
    final first = said([run('ab')]);
    final second = said([run('cde')], x: 40, y: 24);

    test('🚨from the TOP of the stack down, each by its own letters', () {
      final (:tool, host: _, baker: _, cel: _) = hand(
        texts: [carried(1, first), carried(2, second)],
      );

      expect(tool.list.texts, [
        (id: 2, text: 'cde', inHand: false),
        (id: 1, text: 'ab', inHand: false),
      ]);
    });

    test('🚨the one in hand is marked, and named by what is TYPED into it — '
        'landed or not', () async {
      final (:tool, :host, :baker, :cel) = hand(
        texts: [carried(1, first), carried(2, second)],
      );
      tool
        ..takeText(cel, pictureOf(cel).texts.first)
        ..typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, 'abz');

      expect(host.ran, isEmpty, reason: '⛔fixture: nothing landed');
      expect(tool.list.texts, [
        (id: 2, text: 'cde', inHand: false),
        (id: 1, text: 'abz', inHand: true),
      ]);
    });

    test('a NEW text in hand is the topmost — it will be, once it is on '
        'its cel — and one with no letters is not listed', () {
      final (:tool, host: _, baker: _, :cel) = hand(
        texts: [carried(1, first)],
      );
      tool.beginText(cel, at);

      expect(tool.list.texts, [(id: 1, text: 'ab', inHand: false)]);

      typeInto(tool, 'new');

      expect(tool.list.texts, [
        (id: null, text: 'new', inHand: true),
        (id: 1, text: 'ab', inHand: false),
      ]);
    });

    test('with no cel under the tool there is none — and a text held on '
        'ANOTHER cel marks none of this one\'s', () {
      final (:tool, :host, baker: _, :cel) = hand(
        texts: [carried(1, first)],
      );
      tool.takeText(cel, pictureOf(cel).texts.single);

      host.cel = null;
      expect(tool.list.texts, isEmpty);

      // Another cel of the stack, carrying a text of the same id.
      host.cel = (
        key: elsewhere,
        coordinator: cel.coordinator,
        canvasSize: cel.canvasSize,
        cacheInvalidationSink: null,
      );
      cel.coordinator.restoreSurfaceSnapshot(
        elsewhere,
        drawingOf(const {}).withTexts([carried(1, second)]),
      );

      expect(tool.list.texts, [(id: 1, text: 'cde', inHand: false)]);
    });

    group('picked', () {
      test('🚨it is taken in hand by its BOX, and what was in hand lands '
          'first', () async {
        final (:tool, :host, :baker, :cel) = hand(
          texts: [carried(1, first), carried(2, second)],
        );
        tool
          ..takeText(cel, pictureOf(cel).texts.first)
          ..typeAt(const TextSelection.collapsed(offset: 2));
        typeInto(tool, 'abz');
        await baker.pending.answer();

        tool.list.take(2);

        expect(tool.session!.textId, 2);
        expect(tool.hold, CelTextHold.box);
        expect(tool.letters, isNull);
        expect(host.ran, hasLength(1));
        expect(textsOn(cel), [(1, 'abz'), (2, 'cde')]);
      });

      test('the one already in hand stays in hand: its letters are let go '
          'of, and what was typed lands', () async {
        final (:tool, :host, :baker, :cel) = hand(texts: [carried(1, first)]);
        tool
          ..takeText(cel, pictureOf(cel).texts.single)
          ..typeAt(const TextSelection.collapsed(offset: 2));
        typeInto(tool, 'abz');
        await baker.pending.answer();

        tool.list.take(1);

        expect(tool.session!.textId, 1);
        expect(tool.letters, isNull);
        expect(textsOn(cel), [(1, 'abz')]);
        expect(host.ran, hasLength(1));
      });

      test('a new text in hand, picked, lands and stays in hand', () async {
        final (:tool, :host, :baker, :cel) = hand();
        tool.beginText(cel, at);
        typeInto(tool, 'new');
        await baker.pending.answer();

        tool.list.take(null);

        expect(tool.session, isNotNull);
        expect(tool.letters, isNull);
        expect(textsOn(cel), [(1, 'new')]);
        expect(host.ran, hasLength(1));
      });

      test('a text of the same id held on ANOTHER cel is not this one\'s: '
          'this cel\'s is taken', () {
        final (:tool, :host, baker: _, :cel) = hand(texts: [carried(1, first)]);
        tool.takeText(cel, pictureOf(cel).texts.single);
        final CelTextCel other = (
          key: elsewhere,
          coordinator: cel.coordinator,
          canvasSize: cel.canvasSize,
          cacheInvalidationSink: null,
        );
        cel.coordinator.restoreSurfaceSnapshot(
          elsewhere,
          drawingOf(const {}).withTexts([carried(1, second)]),
        );
        host.cel = other;

        tool.list.take(1);

        expect(tool.session!.key, elsewhere);
        expect(tool.session!.textId, 1);
      });

      test('one that is not on the cel is nothing to take', () {
        final (:tool, :host, baker: _, :cel) = hand(texts: [carried(1, first)]);

        tool.list.take(7);

        expect(tool.session, isNull);
        expect(host.ran, isEmpty);
      });
    });

    group('deleted', () {
      test('🚨ANOTHER text is taken off its cel — one step — and the one in '
          'hand stays in hand, what was typed into it still its own', () async {
        final (:tool, :host, :baker, :cel) = hand(
          texts: [carried(1, first), carried(2, second)],
        );
        tool
          ..takeText(cel, pictureOf(cel).texts.first)
          ..typeAt(const TextSelection.collapsed(offset: 2));
        typeInto(tool, 'abz');
        await baker.pending.answer();
        var told = 0;
        tool.addListener(() => told += 1);
        final redrawn = host.redrawn;

        tool.list.delete(2);

        expect(told, 1, reason: 'whoever lists the texts is told');
        expect(host.redrawn, redrawn + 1, reason: 'and the canvas');
        expect(host.ran, hasLength(1));
        expect(textsOn(cel), [(1, 'ab')], reason: 'the typing has not landed');
        expect(tool.session!.textId, 1);
        expect(tool.letters, isNotNull, reason: 'still typed into');
        expect(tool.list.texts, [(id: 1, text: 'abz', inHand: true)]);

        tool.confirm();

        expect(textsOn(cel), [(1, 'abz')]);
        expect(host.ran, hasLength(2));

        host.history.undo();
        host.history.undo();

        expect(textsOn(cel), [(1, 'ab'), (2, 'cde')]);
      });

      test('the one IN HAND is taken off and let go of', () {
        final (:tool, :host, baker: _, :cel) = hand(
          texts: [carried(1, first), carried(2, second)],
        );
        tool.takeText(cel, pictureOf(cel).texts.last);

        tool.list.delete(2);

        expect(tool.session, isNull);
        expect(textsOn(cel), [(1, 'ab')]);
        expect(host.ran, hasLength(1));
      });

      test('a new text in hand that never landed is simply gone', () {
        final (:tool, :host, baker: _, :cel) = hand();
        tool.beginText(cel, at);
        typeInto(tool, 'new');

        tool.list.delete(null);

        expect(tool.session, isNull);
        expect(textsOn(cel), isEmpty);
        expect(host.ran, isEmpty);
      });

      test('🚨one let go of that still OWED its landing does not come back '
          'with it', () async {
        final (:tool, :host, :baker, :cel) = hand(texts: [carried(1, first)]);
        tool
          ..takeText(cel, pictureOf(cel).texts.single)
          ..typeAt(const TextSelection.collapsed(offset: 2));
        typeInto(tool, 'abz');
        tool.confirm();
        expect(tool.holdsAnything, isTrue, reason: '⛔fixture: a landing owed');

        tool.list.delete(1);

        expect(textsOn(cel), isEmpty);
        expect(tool.holdsAnything, isFalse);

        await baker.pending.answer();

        expect(textsOn(cel), isEmpty, reason: 'what it owed went with it');
        expect(host.ran, hasLength(1));
      });

      test('a text of the same id held on ANOTHER cel is not the one taken '
          'off: this cel\'s is, and the hand keeps its own', () {
        final (:tool, :host, baker: _, :cel) = hand(texts: [carried(1, first)]);
        tool.takeText(cel, pictureOf(cel).texts.single);
        final CelTextCel other = (
          key: elsewhere,
          coordinator: cel.coordinator,
          canvasSize: cel.canvasSize,
          cacheInvalidationSink: null,
        );
        cel.coordinator.restoreSurfaceSnapshot(
          elsewhere,
          drawingOf(const {}).withTexts([carried(1, second)]),
        );
        host.cel = other;

        tool.list.delete(1);

        expect(textsOn(other), isEmpty);
        expect(textsOn(cel), [(1, 'ab')]);
        expect(tool.session!.key, cel.key);
      });

      test('with none in hand to name and no id, nothing is taken off', () {
        final (:tool, :host, baker: _, :cel) = hand(texts: [carried(1, first)]);

        tool.list.delete(null);

        expect(textsOn(cel), [(1, 'ab')]);
        expect(host.ran, isEmpty);
      });
    });

    test('told that the cel\'s texts are others, the tool tells whoever '
        'lists them — and not the canvas, which drew the change', () {
      final (:tool, :host, baker: _, cel: _) = hand();
      var told = 0;
      tool.addListener(() => told += 1);
      final redrawn = host.redrawn;

      tool.celTextsChanged();

      expect(told, 1);
      expect(host.redrawn, redrawn);
    });
  });

  group('the cel a press made for its text', () {
    test('rides the text\'s FIRST landing, and no later one', () async {
      final (:tool, :host, :baker, :cel) = hand();
      final since = tool.historyMark;
      tool.beginText(cel, at, celMadeSince: since);
      typeInto(tool, 'ab');
      await baker.pending.answer();

      tool.stopTyping();

      expect(host.ran.single.withCelMadeSince, since);

      tool.changeBox((content) => content.copyWith(letterWidth: 0.5));
      await baker.pending.answer();

      expect(host.ran, hasLength(2));
      expect(host.ran.last.withCelMadeSince, isNull);
    });

    test('a text begun on a cel that was there hands nothing over', () async {
      final (:tool, :host, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'ab');
      await baker.pending.answer();

      tool.confirm();

      expect(host.ran.single.withCelMadeSince, isNull);
    });
  });

  group('a save a person asked for (landShown)', () {
    test('🚨lands the text as it is shown and the typing goes on: what is '
        'typed after is a step of its own', () async {
      final (:tool, :host, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'ab');
      await baker.pending.answer();

      expect(tool.landShown(), isTrue);

      expect(host.ran, hasLength(1));
      expect(textsOn(cel), [(1, 'ab')]);
      expect(tool.hold, CelTextHold.letters, reason: 'still being typed');
      expect(tool.letters!.text, 'ab');
      expect(tool.session!.textId, 1);

      expect(tool.landShown(), isFalse, reason: 'nothing new to land');
      expect(host.ran, hasLength(1));

      typeInto(tool, 'abc');
      await baker.pending.answer();
      tool.stopTyping();

      expect(host.ran, hasLength(2));
      expect(textsOn(cel), [(1, 'abc')]);
    });

    test('a want still being set is not in the file: what was last MADE is, '
        'and the rest lands with the visit', () async {
      final (:tool, :host, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'a');
      await baker.pending.answer();
      typeInto(tool, 'ab');

      expect(tool.landShown(), isTrue);

      expect(textsOn(cel), [(1, 'a')]);

      await baker.pending.answer();
      tool.stopTyping();

      expect(textsOn(cel), [(1, 'ab')]);
      expect(host.ran, hasLength(2));
    });

    test('a text on its way out lands as shown too, and its last want '
        'after it', () async {
      final (:tool, :host, :baker, :cel) = hand();
      tool.beginText(cel, at);
      typeInto(tool, 'a');
      await baker.pending.answer();
      typeInto(tool, 'ab');
      tool.confirm();

      expect(tool.landShown(), isTrue);

      expect(textsOn(cel), [(1, 'a')]);
      expect(tool.holdsAnything, isTrue, reason: 'its last want is owed');

      await baker.pending.answer();

      expect(textsOn(cel), [(1, 'ab')]);
      expect(tool.holdsAnything, isFalse);
    });

    test('with nothing to land it lands nothing, and says so', () {
      final (:tool, :host, baker: _, :cel) = hand(
        texts: [carried(4, said([run('ab')]))],
      );

      expect(tool.landShown(), isFalse);

      tool.takeText(cel, pictureOf(cel).texts.single);

      expect(tool.landShown(), isFalse);
      expect(host.ran, isEmpty);
    });
  });

  test('a hand going away lands what it holds, as shown — and tells '
      'nobody: the canvas it would redraw is the one going', () async {
    final (:tool, :host, :baker, :cel) = hand();
    tool.beginText(cel, at);
    typeInto(tool, 'a');
    await baker.pending.answer();
    typeInto(tool, 'ab');
    final redrawn = host.redrawn;
    var told = 0;
    tool.addListener(() => told += 1);

    tool.dispose();

    expect(host.ran, hasLength(1));
    expect(textsOn(cel), [(1, 'a')]);
    expect(host.redrawn, redrawn);
    expect(told, 0);
  });

  // 🗣️F-377 (유저 2026-10-17): 「변형중 언두가 직전변형 취소라던가. 끝나면
  // 한번에 취소라던가 하듯이 변형 상태는 모두 기본적으로 그걸 따르도록.
  // 텍스트 변형이든 뭐든」 — the transform box's law (유저 2026-09-20), for a
  // text held by its box; a visit to its letters stays a step of its own
  // (F-377-Q1's recommended 「변형만 묶는다」).
  group('🗣️F-377: what the box lands while it holds a text', () {
    /// A hand holding the text 「ab」 its cel carries, by its box.
    ({CelTextTool tool, _Host host, HeldBaker baker, CelTextCel cel})
    holdingAb() {
      final holding = hand(texts: [carried(4, said([run('ab')]))]);
      holding.tool.takeText(holding.cel, pictureOf(holding.cel).texts.single);
      return holding;
    }

    double xOn(CelTextCel cel) => pictureOf(cel).texts.single.content.anchor.x;

    /// The box carries the text in hand [dx] across, and lets go there.
    void carryBy(CelTextTool tool, int dx) => tool
      ..carry(dx: dx, dy: 0)
      ..landEdit();

    test('🚨each step it landed goes back one at a time while it holds the '
        'text — still in hand, as its cel carries it — and none is left once '
        'it stands as it was taken', () {
      final (:tool, :host, baker: _, :cel) = holdingAb();
      carryBy(tool, 4);
      carryBy(tool, 3);
      expect(xOn(cel), 15, reason: '⛔전제: carried 7 from 8');
      expect(host.history.undoCount, 2, reason: '⛔전제: a step a carry');

      expect(tool.canStepBack, isTrue);
      tool.stepBack();

      expect(xOn(cel), 12);
      expect(tool.hold, CelTextHold.box, reason: 'still in hand');
      expect(tool.session!.shown.content.anchor.x, 12);
      expect(tool.session!.shownAsCarried, isTrue);
      expect(host.history.undoCount, 1);
      expect(
        host.history.canRedo,
        isFalse,
        reason: 'a step the hold took back is not one it made',
      );

      tool.stepBack();

      expect(xOn(cel), 8);
      expect(tool.canStepBack, isFalse, reason: 'it stands as it was taken');
    });

    test('🚨let go, what it landed is ONE step — one undo puts the text '
        'back where it was taken', () {
      final (:tool, :host, baker: _, :cel) = holdingAb();
      carryBy(tool, 4);
      carryBy(tool, 3);

      tool.confirm();

      expect(host.history.undoCount, 1);
      host.history.undo();
      expect(xOn(cel), 8);
    });

    test('taking up its letters closes the box\'s steps into one: the visit '
        'is its own step, and what the box lands after it another', () async {
      final (:tool, :host, :baker, :cel) = holdingAb();
      carryBy(tool, 4);
      carryBy(tool, 3);

      tool.typeAt(const TextSelection.collapsed(offset: 2));

      expect(host.history.undoCount, 1, reason: 'the carries are ONE');
      expect(tool.canStepBack, isFalse, reason: 'the letters answer now');

      typeInto(tool, 'abc');
      await baker.pending.answer();
      tool.stopTyping();
      expect(host.history.undoCount, 2, reason: '⛔전제: the visit');
      carryBy(tool, 2);
      carryBy(tool, 2);
      tool.confirm();

      expect(host.history.undoCount, 3);
      host.history.undo();
      expect(xOn(cel), 15, reason: 'the carries after the visit, in one');
      host.history.undo();
      expect(pictureOf(cel).texts.single.content.text, 'ab');
      host.history.undo();
      expect(xOn(cel), 8);
    });

    test('🚨one still being set is given up: nothing of it lands, and the '
        'bake it asked for is never shown', () async {
      final (:tool, :host, :baker, :cel) = holdingAb();
      final taken = pictureOf(cel).texts.single;
      tool.changeBox((content) => content.copyWith(align: TextCelAlign.right));
      expect(host.history.undoCount, 0, reason: '⛔전제: still being set');

      expect(tool.canStepBack, isTrue);
      tool.stepBack();
      expect(tool.canStepBack, isFalse, reason: 'it was the only one');

      await baker.pending.answer();

      expect(
        tool.session!.shown.content,
        taken.content,
        reason: 'shown, it would flash for a frame',
      );
      expect(tool.session!.shown.plate, taken.plate);
      expect(host.history.undoCount, 0, reason: 'nothing landed');
    });

    test('what lands it before the box lets go — a save, or a step about to '
        'be taken elsewhere — lands among the box\'s steps', () {
      final saved = holdingAb();
      carryBy(saved.tool, 4);
      saved.tool.carry(dx: 3, dy: 0);
      expect(saved.tool.landShown(), isTrue, reason: '⛔전제: a save');
      saved.tool
        ..landEdit()
        ..confirm();
      expect(saved.host.history.undoCount, 1, reason: 'saved, still one');

      final taken = holdingAb();
      carryBy(taken.tool, 4);
      taken.tool
        ..carry(dx: 3, dy: 0)
        ..landNow();
      expect(taken.host.history.undoCount, 1, reason: 'landed now, one');
      taken.host.history.undo();
      expect(xOn(taken.cel), 8);
    });

    test('🚨a visit still being set when the box takes the text again is the '
        'visit\'s step: what the box did meanwhile rides it, and none of it '
        'is the box\'s to take back', () async {
      final (:tool, :host, :baker, :cel) = holdingAb();
      tool.typeAt(const TextSelection.collapsed(offset: 2));
      typeInto(tool, 'abc');
      tool
        ..stopTyping()
        ..changeBox((content) => content.copyWith(align: TextCelAlign.right));
      expect(host.history.undoCount, 0, reason: '⛔전제: nothing set yet');

      await baker.pending.answer();
      await baker.pending.answer();

      expect(host.history.undoCount, 1, reason: 'one step, the visit');
      expect(pictureOf(cel).texts.single.content.align, TextCelAlign.right);
      expect(tool.canStepBack, isFalse);
    });

    test('a step the box still owes when its letters are taken rides the '
        'visit: while they are held the box has none to take back', () async {
      final (:tool, :host, :baker, :cel) = holdingAb();
      tool
        ..changeBox((content) => content.copyWith(align: TextCelAlign.right))
        ..typeAt(const TextSelection.collapsed(offset: 2));

      expect(tool.canStepBack, isFalse);

      await baker.pending.answer();
      tool.stopTyping();
      expect(host.history.undoCount, 1, reason: 'the visit, the setting in it');
      expect(pictureOf(cel).texts.single.content.align, TextCelAlign.right);
    });

    test('taken off its cel after the box landed steps: those are ONE, and '
        'taking it off another', () {
      final (:tool, :host, baker: _, :cel) = holdingAb();
      carryBy(tool, 4);
      carryBy(tool, 3);

      tool.deleteText();

      expect(host.history.undoCount, 2);
      host.history.undo();
      expect(xOn(cel), 15, reason: 'back on, where the box had it');
      host.history.undo();
      expect(xOn(cel), 8, reason: 'and the box\'s steps back in one');
    });

    test('⛔a step written elsewhere while it was held stays its own: the box '
        'takes back and folds only what it landed after it', () {
      final (:tool, :host, baker: _, :cel) = holdingAb();
      carryBy(tool, 4);
      host.history.execute(_Elsewhere());
      carryBy(tool, 3);

      tool.stepBack();

      expect(xOn(cel), 12);
      expect(tool.canStepBack, isFalse, reason: 'the step under it is not its');

      carryBy(tool, 3);
      carryBy(tool, 3);
      tool.confirm();

      expect(host.history.undoCount, 3, reason: 'a carry, theirs, two in one');
      host.history.undo();
      expect(xOn(cel), 12);
    });
  });
}

/// A step of somebody else's, written while the hand holds a text.
class _Elsewhere implements Command {
  @override
  String get description => 'Elsewhere';

  @override
  void execute() {}

  @override
  void undo() {}
}

/// The canvas panel the hand works on, stood in for: real history, and a
/// note of every step it was asked to run.
class _Host implements CelTextToolHost {
  final HistoryManager history = HistoryManager();

  @override
  TextToolOptions options = const TextToolOptions(
    letters: TextLetterStyle(fontSize: 8),
  );

  @override
  int? get brushColour => null;

  final List<({Command command, HistoryMark? withCelMadeSince})> ran = [];

  /// The families each step was said to be set in, in the order they ran.
  final List<Set<String>> setInOf = [];

  /// How many times the canvas was told to draw again.
  int redrawn = 0;

  @override
  CelTextCel? cel;

  @override
  HistoryGestures get gestures => history.gestures;

  @override
  void run(
    Command command, {
    HistoryMark? withCelMadeSince,
    Set<String> setIn = const {},
  }) {
    setInOf.add(setIn);
    ran.add((command: command, withCelMadeSince: withCelMadeSince));
    history.execute(command);
  }

  @override
  void shownChanged() => redrawn += 1;
}
