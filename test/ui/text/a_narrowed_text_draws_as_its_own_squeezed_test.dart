import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_faces.dart';

/// text-letters-lean-and-underline ⑥ (Q1, 유저 2026-10-17): a text's letters
/// DRAWN narrower or wider — 장평, [CelTextContent.letterWidth] — in the
/// app's own faces: what is drawn is the text at its own width through a
/// canvas squeezed to that width.
///
/// ⚖️The app's faces here, the test font's in
/// a_text_draws_its_letters_narrower_test.dart, which loads none (card
/// two-text-files-measure-in-the-test-font-only-when-they-run-first,
/// 2026-11-23).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CelTextLayout set(CelTextContent content) {
    final layout = layoutCelText(content);
    addTearDown(layout.dispose);
    return layout;
  }

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
}
