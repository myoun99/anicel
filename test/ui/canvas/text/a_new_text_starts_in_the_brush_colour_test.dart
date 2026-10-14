import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/brush/text_tool_options.dart';
import 'package:anicel/src/ui/brush/text_tool_settings.dart';
import 'package:anicel/src/ui/brush/text_tool_settings_values.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/color_swatch_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_hand.dart';
import '../../../helpers/cel_text_held_baker.dart';
import '../../../helpers/cel_text_tool_harness.dart';

/// F-342: A NEW TEXT IS SET IN THE BRUSH'S COLOUR — the brush's as it is
/// when the text is made. The tool has no colour of its own: with no text
/// in hand, its colour setting IS the brush's.
///
/// 🗣️유저 2026-10-12 (F-342): 「색도 그냥 결정되돌림. 생성시 브러시색
/// 따라가도록」 — F-334-Q1's other answer, 「새 텍스트는 늘 지금 붓 색」:
/// 「텍스트를 고르지 않은 채 도구 설정의 색을 바꾸면 붓 색이 바뀐다(색이
/// 하나). 텍스트를 고르고 바꾸면 그 텍스트만」. ↩️F-334-Q1 (2026-10-10) had
/// taken 「자기 색은 두고, 처음만 붓 색」: the first text's brush colour became
/// the tool's own, and the brush moved after reached no text.
void main() {
  const red = 0xFFCC2233;
  const blue = 0xFF2233CC;
  const green = 0xFF22CC33;
  const black = 0xFF000000;

  group('the hand', () {
    /// The hand over an empty cel — or one carrying [text], taken by its
    /// box — with the tool's values as a run of the app starts them, and
    /// the settings' law over them, reading the brush's colour and setting
    /// it.
    ({TextHand hand, TextToolSettingsValues Function() values}) handWith({
      CelTextContent? text,
    }) {
      final hand = textHand(bake: HeldBaker().call, text: text);
      return (
        hand: hand,
        values: () => TextToolSettingsValues(
          options: hand.options,
          tool: hand.tool,
          brushColour: hand.host.brushColour,
          onBrushColour: (colour) => hand.host.brushColour = colour,
        ),
      );
    }

    /// The colour the text just begun at the top left will be typed in.
    int beginAText(TextHand hand) {
      hand.tool.beginText(hand.cel, CanvasPoint(x: 8, y: 8));
      return hand.tool.letterStylesSpokenFor!.single.color;
    }

    test('🚨every new text is set in the brush\'s colour as it is when the '
        'text is made', () {
      final (:hand, values: _) = handWith();

      hand.host.brushColour = red;
      expect(beginAText(hand), red);
      hand.tool.confirm();

      hand.host.brushColour = blue;
      expect(beginAText(hand), blue, reason: '「생성시 브러시색 따라가도록」');
    });

    test('with no text in hand the settings show the brush\'s colour, '
        'following it', () {
      final (:hand, :values) = handWith();
      int shown() => values().letter((style) => style.color).value;

      hand.host.brushColour = red;
      expect(shown(), red);
      hand.host.brushColour = blue;
      expect(shown(), blue);
    });

    test('🚨a colour picked in the settings with NO text in hand is the '
        'brush\'s — the next text\'s by it — and the tool keeps none', () {
      final (:hand, :values) = handWith();
      hand.host.brushColour = red;

      values().setColour(green);

      expect(hand.host.brushColour, green, reason: '「색이 하나」');
      expect(hand.options.value, TextToolOptions.defaults);
      expect(beginAText(hand), green);
    });

    test('🚨a colour picked with a text IN HAND is that text\'s alone: the '
        'brush\'s stays, and the next text is set in it', () {
      final (:hand, :values) = handWith(
        text: CelTextContent(
          spans: const [CelTextSpan(text: 'ab', style: TextLetterStyle())],
          anchor: CanvasPoint(x: 40, y: 40),
        ),
      );
      expect(hand.tool.session, isNotNull, reason: '⛔fixture: taken');
      hand.host.brushColour = red;

      values().setColour(green);

      expect(hand.tool.letterStylesSpokenFor, [
        const TextLetterStyle(color: green),
      ]);
      expect(hand.host.brushColour, red);
      expect(beginAText(hand), red);
    });

    test('a setting of the letters or of the box with no text in hand is '
        'the next text\'s — and its colour is still the brush\'s', () {
      final (:hand, :values) = handWith();
      hand.host.brushColour = red;

      values().setLetters((style) => style.copyWith(fontSize: 30));
      values().setAlign(TextCelAlign.center);
      hand.host.brushColour = blue;
      beginAText(hand);

      expect(hand.tool.letterStylesSpokenFor!.single.fontSize, 30);
      expect(hand.tool.contentInHand!.align, TextCelAlign.center);
      expect(hand.tool.letterStylesSpokenFor!.single.color, blue);
    });

    test('a text TAKEN in hand gives the next text nothing of its '
        'colour', () {
      final (:hand, values: _) = handWith(
        text: CelTextContent(
          spans: const [
            CelTextSpan(text: 'ab', style: TextLetterStyle(color: green)),
          ],
          anchor: CanvasPoint(x: 40, y: 40),
        ),
      );
      expect(hand.tool.session, isNotNull, reason: '⛔fixture: taken');
      hand.tool.confirm();

      hand.host.brushColour = blue;

      expect(beginAText(hand), blue);
    });

    test('with no brush to read, a text is set in the colour its letters '
        'were made in', () {
      final (:hand, values: _) = handWith();

      expect(beginAText(hand), black);
      hand.tool.confirm();

      hand.host.brushColour = blue;
      expect(beginAText(hand), blue);
    });
  });

  group('the settings', () {
    ColorSwatchButton swatch(WidgetTester tester) =>
        tester.widget<ColorSwatchButton>(
          find.ancestor(
            of: find.byKey(const ValueKey<String>('text-tool-color')),
            matching: find.byType(ColorSwatchButton),
          ),
        );

    Future<void> pumpOver(
      WidgetTester tester,
      ValueNotifier<TextToolOptions> options, {
      required int brush,
      required ValueChanged<int> onBrushColour,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 640,
            child: TextToolSettings(
              options: options,
              commands: null,
              currentColorOf: () => brush,
              onBrushColour: onBrushColour,
            ),
          ),
        ),
      ),
    );

    testWidgets('with no text in hand the colour row is the brush\'s: it '
        'shows it, and a colour typed in its window is set on it', (
      tester,
    ) async {
      final options = ValueNotifier(TextToolOptions.defaults);
      addTearDown(options.dispose);
      final brushes = <int>[];

      await pumpOver(tester, options, brush: red, onBrushColour: brushes.add);
      expect(swatch(tester).color, red);
      await pumpOver(tester, options, brush: blue, onBrushColour: brushes.add);
      expect(swatch(tester).color, blue, reason: 'it follows the brush');

      await tester.tap(find.byKey(const ValueKey<String>('text-tool-color')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('color-status-hex')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('color-status-hex-input')),
        '22CC33',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(brushes.last, green);
      expect(options.value, TextToolOptions.defaults, reason: 'none kept');
    });
  });

  group('the real app', () {
    void paintWith(WidgetTester tester, int colour) {
      final brush = brushOf(tester);
      brush.value = brush.value.copyWith(color: colour);
    }

    /// Sets [words] at the canvas pixel [at] and lets go of them.
    Future<void> setAt(WidgetTester tester, Offset at, String words) async {
      await clickAt(tester, at.dx, at.dy);
      await typeText(tester, words);
      await clickAt(tester, at.dx + 300, at.dy + 200);
    }

    int colourOf(WidgetTester tester, String words) => celOf(tester).texts
        .singleWhere((text) => text.content.text == words)
        .content
        .spans
        .single
        .style
        .color;

    testWidgets('🚨a text is set in the brush\'s colour, and the next one, '
        'after the brush\'s moved, in the brush\'s new one', (tester) async {
      await pumpTextToolApp(tester);
      await takeTextTool(tester);
      final c = canvasPixelInView(tester);

      paintWith(tester, red);
      await pumpFrames(tester);
      await setAt(tester, c, 'hi');

      expect(colourOf(tester, 'hi'), red);
      expect(
        shownPixel(celOf(tester), c.dx.toInt() + 10, c.dy.toInt() + 10),
        [0xCC, 0x22, 0x33, 0xFF],
      );

      paintWith(tester, blue);
      await pumpFrames(tester);
      await setAt(tester, c + const Offset(0, 120), 'yo');

      expect(colourOf(tester, 'yo'), blue);
      expect(colourOf(tester, 'hi'), red, reason: 'a text set keeps its own');
    });
  });
}
