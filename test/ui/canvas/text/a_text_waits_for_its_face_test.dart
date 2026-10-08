import 'dart:async';
import 'dart:typed_data';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/brush/text_tool_options.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';
import 'package:anicel/src/ui/text/canvas_letter_faces.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_fixture.dart';
import '../../../helpers/cel_text_hand.dart';
import '../../../helpers/cel_text_held_baker.dart';

/// R9-rest (the text tool's faces): A FACE IS READ WHEN LETTERS ARE FIRST
/// ASKED FOR IN IT, and until it is here the letters would be set in
/// another. So while a text's face is on its way nothing measures the text
/// and no plate is made of it — for the tool it is not there yet, in every
/// place alike — and its arrival is what brings it.
///
/// What the engine does with a face is measured against the engine
/// (`a_brought_face_sets_the_letters_test`); here the face's ARRIVAL is the
/// test's to give.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const plain = TextLetterStyle(fontSize: 8);
  const brought = TextLetterStyle(fontSize: 8, fontFamily: 'Probe Sans');

  late Completer<void> arrival;
  late List<String> read;

  setUp(() {
    arrival = Completer<void>();
    read = [];
    CanvasLetterFaces.current = CanvasLetterFaces(
      files: (family) async {
        read.add(family);
        await arrival.future;
        return [Uint8List(4)];
      },
      register: (bytes, {required engineFamily}) async {},
    )..setHeld({'Probe Sans': 'sans'});
  });
  tearDown(() => CanvasLetterFaces.current = CanvasLetterFaces());

  Future<void> theFaceArrives() async {
    arrival.complete();
    await pumpEventQueue();
  }

  CelTextContent said(
    String words,
    TextLetterStyle style, {
    double x = 4,
    double y = 4,
  }) => CelTextContent(
    spans: [CelTextSpan(text: words, style: style)],
    anchor: CanvasPoint(x: x, y: y),
  );

  /// The hand over a cel that carries [texts], bottom to top, with nothing
  /// in hand.
  ({CelTextTool tool, TextHandHost host, CelTextCel cel, HeldBaker baker})
  handOver(
    List<CelTextContent> texts, {
    TextToolOptions next = TextToolOptions.defaults,
  }) {
    final baker = HeldBaker();
    final host = TextHandHost(() => next);
    final tool = CelTextTool(host: host, bake: baker.call);
    final CelTextCel cel = (
      key: celTextTestKey,
      coordinator: editingStackOn(
        drawingOf(const {}).withTexts([
          for (final (index, text) in texts.indexed)
            CelText(id: index + 1, content: text, plate: plateOf(text)),
        ]),
      ),
      canvasSize: celTextTestCanvas,
      cacheInvalidationSink: null,
    );
    host.cel = cel;
    return (tool: tool, host: host, cel: cel, baker: baker);
  }

  final inTheAppsFace = said('ab', plain);
  final inTheBroughtFace = said('cd', brought, x: 20);

  group('the texts the tool can reach', () {
    test('🚨are all of a picture\'s but the ones written in a face that is '
        'on its way — and asking is what sends for it', () {
      final picture = drawingOf(const {}).withTexts([
        CelText(id: 1, content: inTheAppsFace, plate: const {}),
        CelText(id: 2, content: inTheBroughtFace, plate: const {}),
      ]);

      expect(read, isEmpty, reason: '⛔fixture: nothing has asked yet');
      expect([for (final text in celTextsInReach(picture)) text.id], [1]);
      expect(read, ['Probe Sans']);
    });

    test('with the face here, all of them, bottom to top', () async {
      final picture = drawingOf(const {}).withTexts([
        CelText(id: 1, content: inTheBroughtFace, plate: const {}),
        CelText(id: 2, content: inTheAppsFace, plate: const {}),
      ]);
      expect([for (final text in celTextsInReach(picture)) text.id], [2]);

      await theFaceArrives();

      expect([for (final text in celTextsInReach(picture)) text.id], [1, 2]);
      expect(read, ['Probe Sans'], reason: 'read once');
    });

    test('a text ONE run of which is in the face on its way waits too', () {
      final mixed = CelTextContent(
        spans: const [
          CelTextSpan(text: 'ab', style: plain),
          CelTextSpan(text: 'cd', style: brought),
        ],
        anchor: CanvasPoint(x: 4, y: 4),
      );

      expect(celTextAwaitsAFace(mixed), isTrue);
      expect(celTextAwaitsAFace(inTheAppsFace), isFalse);
    });

    test('🚨a face this device does NOT hold is waited for by nobody: its '
        'text is set in the app\'s face, and is in reach at once', () {
      final elsewhere = said(
        'ef',
        const TextLetterStyle(fontSize: 8, fontFamily: 'Nobody Sans'),
      );
      final picture = drawingOf(const {}).withTexts([
        CelText(id: 1, content: elsewhere, plate: const {}),
      ]);

      expect(celTextAwaitsAFace(elsewhere), isFalse);
      expect([for (final text in celTextsInReach(picture)) text.id], [1]);
      expect(read, isEmpty);
      expect(celTextFacesArriving(elsewhere), isNull);
    });
  });

  group('while a text\'s face is on its way', () {
    test('🚨its box is not drawn — the others\' are — and it is when the '
        'face is here', () async {
      final (:tool, host: _, :cel, baker: _) = handOver([
        inTheAppsFace,
        inTheBroughtFace,
      ]);
      List<List<Offset>> resting() => [
        for (final box in tool.restingBoxesOn(cel.key, pictureUnder(cel)))
          box.corners,
      ];

      expect(resting(), [celTextBoxOf(inTheAppsFace).corners]);

      await theFaceArrives();

      expect(resting(), [
        celTextBoxOf(inTheAppsFace).corners,
        celTextBoxOf(inTheBroughtFace).corners,
      ]);
    });

    test('🚨the settings\' list does not name it, and it cannot be taken '
        'from there — and can, when the face is here', () async {
      final (:tool, host: _, cel: _, baker: _) = handOver([
        inTheAppsFace,
        inTheBroughtFace,
      ]);

      expect(tool.list.texts, [(id: 1, text: 'ab', inHand: false)]);
      tool.list.take(2);
      expect(tool.session, isNull);

      await theFaceArrives();

      expect(tool.list.texts, [
        (id: 2, text: 'cd', inHand: false),
        (id: 1, text: 'ab', inHand: false),
      ]);
      tool.list.take(2);
      expect(tool.session!.textId, 2);
    });
  });

  group('a text in hand set in a face that is on its way', () {
    test('🚨is not baked until the face is here: what is on screen stays '
        'the text that was, whole — and then the engine is asked', () async {
      final baker = HeldBaker();
      final hand = textHand(bake: baker.call, text: inTheAppsFace);

      hand.tool.changeLetters((style) => style.copyWith(fontFamily: 'Probe Sans'));
      await pumpEventQueue();

      expect(baker.asked, isEmpty, reason: 'no plate is made in another face');
      expect(hand.tool.session!.shown.content, inTheAppsFace);
      expect(hand.host.ran, isEmpty);
      expect(read, ['Probe Sans']);

      await theFaceArrives();

      expect(baker.asked, hasLength(1));
      expect(baker.pending.content.spans.single.style.fontFamily, 'Probe Sans');
      await baker.pending.answer();
      expect(
        hand.tool.session!.shown.content.spans.single.style.fontFamily,
        'Probe Sans',
      );
      expect(landedOn(hand.cel).spans.single.style.fontFamily, 'Probe Sans');
    });

    test('a newer want made while it waited is the one that is baked', () async {
      final baker = HeldBaker();
      final hand = textHand(bake: baker.call, text: inTheAppsFace);

      hand.tool
        ..changeLetters((style) => style.copyWith(fontFamily: 'Probe Sans'))
        ..changeLetters((style) => style.copyWith(bold: true));
      await theFaceArrives();

      expect(baker.asked, hasLength(1));
      expect(baker.pending.content.spans.single.style.bold, isTrue);
      expect(baker.pending.content.spans.single.style.fontFamily, 'Probe Sans');
    });

    test('🚨a text WITH letters does not wait for the face the NEXT letter '
        'would be in — that face is none of its own', () {
      final baker = HeldBaker();
      final hand = textHand(
        bake: baker.call,
        text: inTheAppsFace,
        next: const TextToolOptions(letters: brought),
      );

      hand.tool.changeLetters((style) => style.copyWith(bold: true));

      expect(baker.asked, hasLength(1), reason: 'asked in the same turn');
    });

    test('with every face here, the engine is asked without a pause', () async {
      await theFaceArrives();
      CanvasLetterFaces.current.sendFor('Probe Sans');
      await pumpEventQueue();
      final baker = HeldBaker();
      final hand = textHand(bake: baker.call, text: inTheAppsFace);

      hand.tool.changeLetters((style) => style.copyWith(fontFamily: 'Probe Sans'));

      expect(baker.asked, hasLength(1), reason: 'asked in the same turn');
    });
  });

  group('a new text, with no letters yet', () {
    final at = CanvasPoint(x: 6, y: 6);

    test('🚨whose next letter is in a face on its way is set again when '
        'the face is here — its caret was measured in another', () async {
      final (:tool, host: _, :cel, :baker) = handOver(
        const [],
        next: const TextToolOptions(letters: brought),
      );

      tool.beginText(cel, at);
      final session = tool.session!;
      var set = 0;
      session.addListener(() => set += 1);
      final first = session.shown.layout;

      expect(session.settled, isFalse);
      expect(read, ['Probe Sans']);

      await theFaceArrives();

      expect(session.settled, isTrue);
      expect(set, isPositive, reason: 'whoever draws its caret is told');
      expect(session.shown.layout, isNot(same(first)));
      expect(baker.asked, isEmpty, reason: 'no letters: nothing to bake');
    });

    test('whose next letter is in the app\'s face is settled from the start', () {
      final (:tool, host: _, :cel, baker: _) = handOver(const []);

      tool.beginText(cel, at);

      expect(tool.session!.settled, isTrue);
      expect(read, isEmpty);
    });
  });
}
