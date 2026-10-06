import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_chrome.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_stage.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_fixture.dart';
import '../../../helpers/cel_text_hand.dart';

/// R9-rest (the text tool): WHEN ITS CHROME IS DRAWN AGAIN.
///
/// What it draws is measured on the real app
/// (`a_text_is_sized_and_turned_by_its_box_test`) — but a test that asks a
/// painter to paint cannot tell whether the canvas would have asked it to:
/// a painter that forgot one of its inputs paints the new picture when
/// asked and leaves the old one on screen. So the question 「is this
/// another picture」 is asked here, of each input.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CelTextBox boxOf(String words, {double x = 8}) => celTextBoxOf(
    CelTextContent(
      spans: [
        CelTextSpan(text: words, style: const TextLetterStyle(fontSize: 8)),
      ],
      anchor: CanvasPoint(x: x, y: 8),
    ),
  );

  CelTextStage stageAt(double zoom) => CelTextStage(
    viewport: CanvasViewport(zoom: zoom),
    canvasSize: celTextTestCanvas,
    placement: null,
  );

  late TextHand hand;
  late ValueNotifier<bool> caretLit;

  setUp(() {
    hand = textHand(bake: bakesAtOnce);
    caretLit = ValueNotifier(true);
    addTearDown(caretLit.dispose);
  });

  CelTextChromePainter chrome({
    List<CelTextBox> resting = const [],
    Rect? traced,
    double zoom = 1,
    Color color = const Color(0xFF4488FF),
  }) => CelTextChromePainter(
    tool: hand.tool,
    stage: stageAt(zoom),
    restingBoxes: resting,
    tracedBox: traced,
    caretLit: caretLit,
    color: color,
  );

  test('the same inputs are the same picture: it is not drawn again', () {
    final a = boxOf('ab');

    expect(chrome(resting: [a]).shouldRepaint(chrome(resting: [a])), isFalse);
    expect(chrome().shouldRepaint(chrome()), isFalse);
  });

  test('🚨a box in nobody\'s hand that is ANOTHER — one more, one fewer, '
      'one in another place — is another picture', () {
    final a = boxOf('ab');
    final b = boxOf('ab', x: 40);

    expect(chrome(resting: [a, b]).shouldRepaint(chrome(resting: [a])), isTrue);
    expect(chrome().shouldRepaint(chrome(resting: [a])), isTrue);
    expect(chrome(resting: [b]).shouldRepaint(chrome(resting: [a])), isTrue);
  });

  test('so is another traced box, another view of the canvas, another '
      'colour', () {
    const traced = Rect.fromLTWH(1, 2, 30, 40);

    expect(chrome(traced: traced).shouldRepaint(chrome()), isTrue);
    expect(
      chrome(traced: traced).shouldRepaint(chrome(traced: traced)),
      isFalse,
    );
    expect(chrome(zoom: 2).shouldRepaint(chrome()), isTrue);
    expect(
      chrome(color: const Color(0xFFFF0000)).shouldRepaint(chrome()),
      isTrue,
    );
  });

  // ⚠️What the HAND holds is not one of the inputs above: the painter reads
  // it as it paints, and is asked to paint again by whoever told it. The
  // cross is told of on a line of its own (`CelTextTool.carryCross`), so
  // that line has to be one the painter hears.
  test('🚨a cross carried is drawn again: the painter hears the cross\'s '
      'own line — and the caret\'s, and the hand\'s', () {
    final held = textHand(
      bake: bakesAtOnce,
      text: CelTextContent(
        spans: const [
          CelTextSpan(text: 'ab', style: TextLetterStyle(fontSize: 8)),
        ],
        anchor: CanvasPoint(x: 8, y: 8),
      ),
    );
    final painter = CelTextChromePainter(
      tool: held.tool,
      stage: stageAt(1),
      restingBoxes: const [],
      tracedBox: null,
      caretLit: caretLit,
      color: const Color(0xFF4488FF),
    );
    var asked = 0;
    painter.addListener(() => asked += 1);

    held.tool.carryCross(const Offset(3, 0));
    expect(asked, 1);

    caretLit.value = false;
    expect(asked, 2);

    held.tool.celTextsChanged();
    expect(asked, 3);
  });

  test('and another hand: a painter is its tool\'s', () {
    final other = textHand(bake: bakesAtOnce);
    final painter = CelTextChromePainter(
      tool: other.tool,
      stage: stageAt(1),
      restingBoxes: const [],
      tracedBox: null,
      caretLit: caretLit,
      color: const Color(0xFF4488FF),
    );

    expect(painter.shouldRepaint(chrome()), isTrue);
  });
}
