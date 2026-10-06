import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/brush/cel_text_commands.dart';
import 'package:anicel/src/ui/brush/text_tool_options.dart';
import 'package:anicel/src/ui/brush/text_tool_settings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';
import 'package:anicel/src/ui/widgets/color_swatch_button.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_hand.dart';

/// R9-rest (the text tool): THE ROWS OF ITS SETTINGS — the layout 유저 took
/// on 2026-10-06, top to bottom: the text in hand and its delete · 글자 —
/// face, size, tracking, bold, colour, outline, outline width · 상자 —
/// alignment, box width, line spacing, background.
///
/// What a row reads and writes is `TextToolSettingsValues`'s, measured
/// there. Here: every row is there, shows what it should, and a hand on it
/// reaches the text — once a drag, once a window.
void main() {
  const plain = TextLetterStyle(fontSize: 16);
  const red = TextLetterStyle(fontSize: 16, color: 0xFFFF0000);

  CelTextSpan run(String words, [TextLetterStyle style = plain]) =>
      CelTextSpan(text: words, style: style);

  CelTextContent said(
    List<CelTextSpan> spans, {
    double? wrapWidth,
    TextCelAlign align = TextCelAlign.left,
  }) => CelTextContent(
    spans: spans,
    anchor: CanvasPoint(x: 8, y: 8),
    wrapWidth: wrapWidth,
    align: align,
  );

  Finder row(String name) => find.byKey(ValueKey<String>('text-tool-$name'));

  /// The settings over a hand that holds [text] by its box, or nothing.
  Future<TextHand> pumpSettings(
    WidgetTester tester, {
    CelTextContent? text,
    TextToolOptions next = const TextToolOptions(letters: plain),
  }) async {
    final hand = textHand(bake: bakesAtOnce, text: text, next: next);
    final commands = CelTextCommands()..bind(hand.tool);
    addTearDown(commands.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              height: 640,
              child: TextToolSettings(
                options: hand.options,
                commands: commands,
                currentColorOf: () => 0xFFAABBCC,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return hand;
  }

  FieldSlider bar(WidgetTester tester, String name) =>
      tester.widget<FieldSlider>(row(name));

  /// What the bar [name] writes as its number.
  Finder written(String name, String text) =>
      find.descendant(of: row(name), matching: find.text(text));

  Pill pill(WidgetTester tester, String name) => tester.widget<Pill>(row(name));

  ColorSwatchButton swatch(WidgetTester tester, String name) =>
      tester.widget<ColorSwatchButton>(
        find.ancestor(
          of: row(name),
          matching: find.byType(ColorSwatchButton),
        ),
      );

  testWidgets('🚨every row has its seat, in the order of the layout — with '
      'a text in hand or with none', (tester) async {
    const rows = [
      'selected-text',
      'font',
      'size',
      'tracking',
      'bold',
      'color',
      'outline',
      'outline-width',
      'align',
      'box-width',
      'line-height',
      'background',
    ];

    Future<List<double>> tops() async => [
      for (final name in rows) tester.getTopLeft(row(name)).dy,
    ];

    await pumpSettings(tester);
    final withNone = await tops();
    for (final name in rows) {
      expect(row(name), findsOneWidget, reason: name);
    }
    expect(row('delete-text'), findsOneWidget);
    expect(withNone, [...withNone]..sort(), reason: 'top to bottom');

    // ⛔없다가 생기는 UI 금지: a text in hand moves no row.
    await pumpSettings(tester, text: said([run('ab')]));
    expect(await tops(), withNone);
  });

  group('with nothing in hand', () {
    testWidgets('the rows show what the next text will start as', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        next: const TextToolOptions(
          letters: TextLetterStyle(
            fontSize: 30,
            letterSpacing: 4,
            bold: true,
            color: 0xFF102030,
          ),
          align: TextCelAlign.center,
          lineHeight: 1.5,
        ),
      );

      expect(written('size', '30.0 px'), findsOneWidget);
      expect(written('tracking', '4'), findsOneWidget);
      expect(
        tester
            .widget<BooleanDot>(
              find.descendant(
                of: row('bold'),
                matching: find.byType(BooleanDot),
              ),
            )
            .value,
        isTrue,
      );
      expect(swatch(tester, 'color').color, 0xFF102030);
      expect(swatch(tester, 'outline').color, isNull);
      expect(pill(tester, 'align-center').selected, isTrue);
      expect(pill(tester, 'align-left').selected, isFalse);
      expect(written('line-height', '150%'), findsOneWidget);
      expect(swatch(tester, 'background').color, isNull);
    });

    testWidgets('🚨the box width is nobody\'s to set: neither answer is lit, '
        'and neither takes a press — the seats stay', (tester) async {
      await pumpSettings(tester);

      for (final name in ['box-width-auto', 'box-width-fixed']) {
        expect(pill(tester, name).selected, isFalse, reason: name);
        expect(pill(tester, name).onTap, isNull, reason: name);
      }
    });

    testWidgets('the text\'s name is empty and its delete is dead', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(
        tester.widget<PanelFlyoutButton>(row('selected-text')).label,
        isEmpty,
      );
      await tester.tap(row('delete-text'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a row pressed sets the NEXT text', (tester) async {
      final hand = await pumpSettings(tester);

      await tester.tap(row('bold'));
      await tester.pump();
      await tester.tap(row('align-right'));
      await tester.pump();

      expect(hand.options.value.letters.bold, isTrue);
      expect(hand.options.value.align, TextCelAlign.right);
      expect(hand.host.ran, isEmpty);
      expect(pill(tester, 'align-right').selected, isTrue);
    });
  });

  group('with a text in hand', () {
    testWidgets('the rows show the TEXT — its name on one line', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        text: said(
          [run('ab\ncd', const TextLetterStyle(fontSize: 24))],
          wrapWidth: 90,
          align: TextCelAlign.right,
        ),
      );

      expect(
        tester.widget<PanelFlyoutButton>(row('selected-text')).label,
        'ab cd',
      );
      expect(written('size', '24.0 px'), findsOneWidget);
      expect(pill(tester, 'align-right').selected, isTrue);
      expect(pill(tester, 'box-width-fixed').selected, isTrue);
      expect(pill(tester, 'box-width-auto').selected, isFalse);
    });

    testWidgets('🚨what its letters do not agree on reads as 「—」: the bar, '
        'the face, the ring and the swatch', (tester) async {
      await pumpSettings(
        tester,
        text: said([
          run('ab', red),
          run(
            'cd',
            const TextLetterStyle(
              fontSize: 32,
              bold: true,
              fontFamily: 'Nanum Gothic',
            ),
          ),
        ]),
      );

      expect(written('size', '—'), findsOneWidget);
      expect(tester.widget<PanelFlyoutButton>(row('font')).label, '—');
      expect(
        tester
            .widget<BooleanDot>(
              find.descendant(
                of: row('bold'),
                matching: find.byType(BooleanDot),
              ),
            )
            .mixed,
        isTrue,
      );
      expect(swatch(tester, 'color').mixed, isTrue);
      // What they agree on is its value.
      expect(written('tracking', '0'), findsOneWidget);
      expect(swatch(tester, 'outline').mixed, isFalse);
    });

    testWidgets('🚨a bar DRAGGED shows as it goes and lands once, where the '
        'hand lets go', (tester) async {
      final hand = await pumpSettings(tester, text: said([run('ab')]));
      final size = tester.getRect(row('size'));

      final drag = await tester.startGesture(size.center);
      await tester.pump();
      await drag.moveBy(const Offset(30, 0));
      await tester.pump();
      await drag.moveBy(const Offset(30, 0));
      await tester.pump();

      final shown =
          hand.tool.session!.shown.content.spans.single.style.fontSize;
      expect(shown, greaterThan(16), reason: 'the text on screen follows');
      expect(hand.host.ran, isEmpty, reason: 'nothing lands mid-drag');
      expect(landedOn(hand.cel).spans.single.style.fontSize, 16);

      await drag.up();
      await tester.pump();

      expect(hand.host.ran, hasLength(1));
      expect(landedOn(hand.cel).spans.single.style.fontSize, shown);
      expect(hand.options.value.letters.fontSize, shown);
    });

    testWidgets('a mixed ring pressed turns every letter on', (tester) async {
      final hand = await pumpSettings(
        tester,
        text: said([
          run('ab'),
          run('cd', const TextLetterStyle(fontSize: 16, bold: true)),
        ]),
      );

      await tester.tap(row('bold'));
      await tester.pump();

      expect(
        landedOn(hand.cel).spans.single,
        run('abcd', const TextLetterStyle(fontSize: 16, bold: true)),
      );
      expect(hand.host.ran, hasLength(1));
    });

    testWidgets('the face is picked from the app\'s own, the one in use '
        'marked', (tester) async {
      final hand = await pumpSettings(tester, text: said([run('ab')]));

      expect(
        tester.widget<PanelFlyoutButton>(row('font')).label,
        AppTypography.bundledFamily,
      );

      await tester.tap(row('font'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('text-tool-font-Nanum Gothic')),
      );
      await tester.pumpAndSettle();

      expect(
        landedOn(hand.cel).spans.single.style.fontFamily,
        'Nanum Gothic',
      );
      expect(hand.options.value.letters.fontFamily, 'Nanum Gothic');
      expect(
        tester.widget<PanelFlyoutButton>(row('font')).label,
        'Nanum Gothic',
      );
    });

    testWidgets('🚨the outline\'s width is dead until the letters have an '
        'outline to be the width of', (tester) async {
      final hand = await pumpSettings(tester, text: said([run('ab')]));

      expect(bar(tester, 'outline-width').onChanged, isNull);

      hand.tool.changeLetters(
        (style) => style.copyWith(outlineColor: 0xFF00FF00),
      );
      await tester.pump();

      expect(bar(tester, 'outline-width').onChanged, isNotNull);
    });

    testWidgets('🚨a colour picked lands ONCE, when its window closes — '
        'however many colours the wheel passed', (tester) async {
      final hand = await pumpSettings(tester, text: said([run('ab')]));

      await tester.tap(row('color'));
      await tester.pumpAndSettle();
      final wheel = find.byKey(const ValueKey<String>('color-picker-wheel'));
      final spot = tester.getCenter(wheel);
      await tester.tapAt(spot);
      await tester.pump();
      await tester.tapAt(spot + const Offset(8, 6));
      await tester.pump();

      final picked = hand.tool.session!.shown.content.spans.single.style.color;
      expect(picked, isNot(0xFF000000), reason: '⛔fixture: a colour picked');
      expect(hand.host.ran, isEmpty, reason: 'the window is still open');

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(wheel, findsNothing, reason: '⛔fixture: the window closed');
      expect(hand.host.ran, hasLength(1));
      expect(landedOn(hand.cel).spans.single.style.color, picked);
      expect(hand.options.value.letters.color, picked);
    });

    testWidgets('「현재 색 반영」 brings the brush\'s colour to the letters', (
      tester,
    ) async {
      final hand = await pumpSettings(tester, text: said([run('ab')]));

      await tester.tap(row('color'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('color-picker-use-current')),
      );
      await tester.pump();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(landedOn(hand.cel).spans.single.style.color, 0xFFAABBCC);
    });

    testWidgets('the outline is taken off with 「없음」', (tester) async {
      final hand = await pumpSettings(
        tester,
        text: said([
          run(
            'ab',
            const TextLetterStyle(
              fontSize: 16,
              outlineColor: 0xFF00FF00,
              outlineWidth: 3,
            ),
          ),
        ]),
      );

      await tester.tap(row('outline'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('color-picker-none')),
      );
      await tester.pump();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(landedOn(hand.cel).spans.single.style.outlineColor, isNull);
      expect(hand.host.ran, hasLength(1));
    });

    testWidgets('🚨the box width swaps the text in hand — and it reads the '
        'other answer', (tester) async {
      final hand = await pumpSettings(tester, text: said([run('ab')]));

      expect(pill(tester, 'box-width-auto').selected, isTrue);

      await tester.tap(row('box-width-fixed'));
      await tester.pump();

      // 「ab」 at 16 is 32 wide, and a box is a pixel past its longest line.
      expect(landedOn(hand.cel).wrapWidth, 33);
      expect(pill(tester, 'box-width-fixed').selected, isTrue);
      expect(hand.host.ran, hasLength(1));

      await tester.tap(row('box-width-auto'));
      await tester.pump();

      expect(landedOn(hand.cel).wrapWidth, isNull);
      expect(hand.host.ran, hasLength(2));
    });

    testWidgets('the line spacing reads as a share of the letters\' size, '
        'and a press on its bar sets it', (tester) async {
      final hand = await pumpSettings(tester, text: said([run('ab')]));

      expect(written('line-height', '125%'), findsOneWidget);

      // Four fifths of the way along its TRACK — the bar less the +/− pair
      // at its end, 14 wide and 3 clear of it.
      final line = tester.getRect(row('line-height'));
      await tester.tapAt(
        line.centerLeft + Offset((line.width - 17) * 0.8, 0),
      );
      await tester.pump();

      // From 50% to 300%: four fifths of the way is 250%.
      expect(landedOn(hand.cel).lineHeight, closeTo(2.5, 1e-9));
      expect(hand.host.ran, hasLength(1));
      expect(written('line-height', '250%'), findsOneWidget);
    });

    testWidgets('🚨the delete beside its name takes the text off its cel', (
      tester,
    ) async {
      final hand = await pumpSettings(tester, text: said([run('ab')]));

      await tester.tap(row('delete-text'));
      await tester.pump();

      expect(pictureUnder(hand.cel).texts, isEmpty);
      expect(hand.tool.session, isNull);
      expect(hand.host.ran, hasLength(1));
      expect(
        tester.widget<PanelFlyoutButton>(row('selected-text')).label,
        isEmpty,
      );
    });
  });

  testWidgets('a host that owns no settings and holds no text shows the '
      'defaults, and its controls are shut', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: SizedBox(
            width: 260,
            height: 640,
            child: TextToolSettings(options: null, commands: null),
          ),
        ),
      ),
    );

    expect(written('size', '48.0 px'), findsOneWidget);
    expect(bar(tester, 'size').onChanged, isNull);
    expect(bar(tester, 'line-height').onChanged, isNull);
    expect(pill(tester, 'align-left').onTap, isNull);
    expect(tester.widget<PanelFlyoutButton>(row('font')).enabled, isFalse);
  });
}
