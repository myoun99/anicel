import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
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

/// F-334: A NEW TEXT STARTS IN THE BRUSH'S COLOUR — the first one, and the
/// tool keeps that colour as its own.
///
/// 🗣️유저 2026-10-10: 「텍스트툴 처음 생성되는 색 기본값 검정말고 브러시?
/// 색으로 생성」 → F-334-Q1 「자기 색은 두고, 처음만 붓 색」: 「처음
/// 생성될떄만 기본값을 붓색. 이후로 편집도중 브러시 색 바꾼다고 텍스트색
/// 안바뀜. 진짜 초기값만 브러시색으로 해두는것」.
void main() {
  const red = 0xFFCC2233;
  const blue = 0xFF2233CC;
  const green = 0xFF22CC33;
  const black = 0xFF000000;

  group('the hand', () {
    /// The hand over an empty cel — or one carrying [text] — with the
    /// tool's values as a run of the app starts them, and the settings'
    /// law over them reading [brushColour].
    ({TextHand hand, TextToolSettingsValues Function(int? brush) values})
    handWith({CelTextContent? text}) {
      final hand = textHand(bake: HeldBaker().call, text: text);
      return (
        hand: hand,
        values: (brush) => TextToolSettingsValues(
          options: hand.options,
          tool: hand.tool,
          brushColour: brush,
        ),
      );
    }

    /// The colour the text just begun at the top left will be typed in.
    int beginAText(TextHand hand) {
      hand.tool.beginText(hand.cel, CanvasPoint(x: 8, y: 8));
      return hand.tool.letterStylesSpokenFor!.single.color;
    }

    test('🚨the FIRST text is set in the brush\'s colour — and the tool keeps '
        'it: the next is set in it whatever the brush\'s became', () {
      final (:hand, values: _) = handWith();
      expect(
        hand.options.value,
        TextToolOptions.defaults,
        reason: '⛔fixture: the tool as a run of the app starts it',
      );

      hand.host.brushColour = red;
      expect(beginAText(hand), red);
      hand.tool.confirm();

      hand.host.brushColour = blue;
      expect(
        beginAText(hand),
        red,
        reason: '「이후로 … 브러시 색 바꾼다고 텍스트색 안바뀜」',
      );
    });

    test('until then the settings show the brush\'s colour, following it — '
        'and after it, the tool\'s own', () {
      final (:hand, :values) = handWith();
      int shown(int brush) => values(brush).letter((style) => style.color).value;

      expect(shown(red), red);
      expect(shown(blue), blue);

      hand.host.brushColour = green;
      beginAText(hand);
      hand.tool.confirm();

      expect(shown(red), green);
    });

    test('a colour picked in the settings before any text is the first '
        'text\'s — the brush\'s is not read', () {
      final (:hand, :values) = handWith();

      values(red).setColour(green);
      hand.host.brushColour = red;

      expect(beginAText(hand), green);
    });

    test('the brush\'s own colour picked there (「현재 색 반영」) is the tool\'s '
        'own all the same — the brush moved after reaches no text', () {
      final (:hand, :values) = handWith();

      values(red).setColour(red);
      hand.host.brushColour = blue;

      expect(beginAText(hand), red);
    });

    test('a setting other than the colour — of the letters or of a paragraph — '
        'gives the tool no colour of its own', () {
      final (:hand, :values) = handWith();

      values(red).setLetters((style) => style.copyWith(fontSize: 30));
      values(red).setParagraphs(
        (paragraph) => paragraph.copyWith(align: TextCelAlign.center),
      );
      hand.host.brushColour = blue;
      beginAText(hand);

      expect(hand.tool.letterStylesSpokenFor!.single.fontSize, 30);
      expect(
        hand.tool.contentInHand!.paragraphs.single.align,
        TextCelAlign.center,
      );
      expect(hand.tool.letterStylesSpokenFor!.single.color, blue);
    });

    test('a text TAKEN in hand is not a text set: the tool still has no '
        'colour of its own', () {
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

    test('with no brush to read, a text is set in the colour the tool was made '
        'in — and the tool keeps taking the brush\'s once there is one', () {
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
            ),
          ),
        ),
      ),
    );

    testWidgets('the colour row shows the brush\'s colour while the tool has '
        'none of its own — and 「현재 색 반영」 there makes it the tool\'s', (
      tester,
    ) async {
      final options = ValueNotifier(TextToolOptions.defaults);
      addTearDown(options.dispose);

      await pumpOver(tester, options, brush: red);
      expect(swatch(tester).color, red);
      await pumpOver(tester, options, brush: blue);
      expect(swatch(tester).color, blue, reason: 'it follows the brush');

      await tester.tap(find.byKey(const ValueKey<String>('text-tool-color')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('color-picker-use-current')),
      );
      await tester.pumpAndSettle();
      await pumpOver(tester, options, brush: red);

      expect(swatch(tester).color, blue);
    });
  });

  group('the real app', () {
    /// The brush in hand on the canvas the text tool works on.
    ValueNotifier<BrushToolState> brushOf(WidgetTester tester) =>
        tester
                .widget<BrushCanvasPanel>(
                  find.ancestor(
                    of: textLayer(),
                    matching: find.byType(BrushCanvasPanel),
                  ),
                )
                .brushToolState!
            as ValueNotifier<BrushToolState>;

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

    testWidgets('🚨the first text is set in the brush\'s colour, and the next '
        'in the same after the brush\'s moved', (tester) async {
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

      expect(colourOf(tester, 'yo'), red);
    });
  });
}
