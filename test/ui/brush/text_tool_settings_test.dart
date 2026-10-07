import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/cel_text_box_edits.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/cel_text_commands.dart';
import 'package:anicel/src/ui/brush/text_tool_options.dart';
import 'package:anicel/src/ui/brush/text_tool_settings.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/cel_text_box_width.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';
import 'package:anicel/src/ui/widgets/color_swatch_button.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';
import 'package:anicel/src/ui/widgets/settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_hand.dart';

/// R9-rest (the text tool): THE ROWS OF ITS SETTINGS — the layout 유저 took
/// on 2026-10-06, top to bottom: the text in hand and its delete · 글자 —
/// face, size, tracking, bold, colour, outline, outline width, the
/// smoothing of the letters' edges · 상자 —
/// alignment, box width, line spacing, background · and at the foot
/// 「그림으로 굳히기」.
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

  /// The settings over a hand that holds [text] by its box, or nothing —
  /// in a box [height] tall: as tall as their rows unless a test says less.
  Future<TextHand> pumpSettings(
    WidgetTester tester, {
    CelTextContent? text,
    TextToolOptions next = const TextToolOptions(letters: plain),
    double height = 640,
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
              height: height,
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

  /// The delete beside the text's name, as the button it is.
  AppIconButton deleteButton(WidgetTester tester) =>
      tester.widget<AppIconButton>(
        find.ancestor(
          of: row('delete-text'),
          matching: find.byType(AppIconButton),
        ),
      );

  /// 「그림으로 굳히기」, as the button it is.
  FilledButton intoDrawing(WidgetTester tester) =>
      tester.widget<FilledButton>(row('into-drawing'));

  BooleanDot boldRing(WidgetTester tester) => tester.widget<BooleanDot>(
    find.descendant(of: row('bold'), matching: find.byType(BooleanDot)),
  );

  /// The ring of the switch that smooths the letters' edges.
  BooleanDot smoothRing(WidgetTester tester) => tester.widget<BooleanDot>(
    find.descendant(of: row('antialias'), matching: find.byType(BooleanDot)),
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
      'antialias',
      'writing',
      'align',
      'box-width',
      'line-height',
      'background',
      // 유저 2026-10-06: at the foot of the settings.
      'into-drawing',
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
            antialias: false,
          ),
          align: TextCelAlign.center,
          lineHeight: 1.5,
        ),
      );

      expect(smoothRing(tester).value, isFalse);
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

    testWidgets('the text\'s name is empty, its delete is dead — and with '
        'no text on the cel its list is shut', (tester) async {
      await pumpSettings(tester);

      final field = tester.widget<PanelFlyoutButton>(row('selected-text'));
      expect(field.label, isEmpty);
      expect(field.enabled, isFalse);
      // Its seat is kept, and it is out: no press, and the glyph dark with
      // the button (the delete red's own rule).
      final delete = deleteButton(tester);
      expect(delete.onPressed, isNull);
      expect(
        (delete.icon as Icon).color,
        AppColors.deleteGlyph(enabled: false),
      );
    });

    testWidgets('「그림으로 굳히기」 keeps its seat and is OUT: there is no '
        'text to turn', (tester) async {
      await pumpSettings(tester);

      expect(intoDrawing(tester).onPressed, isNull);
      expect(
        find.descendant(
          of: row('into-drawing'),
          matching: find.text(AppText.strings.textToolIntoDrawing),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a row pressed sets the NEXT text', (tester) async {
      final hand = await pumpSettings(tester);

      await tester.tap(row('bold'));
      await tester.pump();
      await tester.tap(row('align-right'));
      await tester.pump();
      await tester.tap(row('writing-columns'));
      await tester.pump();

      expect(hand.options.value.letters.bold, isTrue);
      expect(hand.options.value.align, TextCelAlign.right);
      expect(hand.options.value.vertical, isTrue);
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

    testWidgets('letters bold FIRST and plain after are mixed too: the ring '
        'is not on', (tester) async {
      await pumpSettings(
        tester,
        text: said([
          run('ab', const TextLetterStyle(fontSize: 16, bold: true)),
          run('cd'),
        ]),
      );

      expect(boldRing(tester).mixed, isTrue);
      expect(boldRing(tester).value, isFalse);
      expect(tester.takeException(), isNull);
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

    testWidgets('🚨each bar reads and sets its OWN number of the letters: '
        'the tracking theirs, the outline\'s width its', (tester) async {
      const outlined = TextLetterStyle(
        fontSize: 16,
        outlineColor: 0xFF000000,
        outlineWidth: 3,
      );
      final hand = await pumpSettings(
        tester,
        text: said([run('ab', outlined)]),
      );
      expect(written('outline-width', '3 px'), findsOneWidget);
      expect(written('tracking', '0'), findsOneWidget);

      Future<void> slide(String name) async {
        final drag = await tester.startGesture(
          tester.getRect(row(name)).center,
        );
        await tester.pump();
        await drag.moveBy(const Offset(30, 0));
        await tester.pump();
        await drag.up();
        await tester.pump();
      }

      await slide('tracking');
      final tracked = landedOn(hand.cel).spans.single.style;
      expect(tracked.letterSpacing, greaterThan(0));
      expect(tracked.copyWith(letterSpacing: 0), outlined);

      await slide('outline-width');
      final widened = landedOn(hand.cel).spans.single.style;
      expect(widened.outlineWidth, isNot(3));
      expect(widened.copyWith(outlineWidth: 3), tracked);
      // The next text is told each number too — and nothing it was not: it
      // has no outline to be the width of.
      expect(
        hand.options.value.letters,
        plain.copyWith(
          letterSpacing: tracked.letterSpacing,
          outlineWidth: widened.outlineWidth,
        ),
      );
      expect(hand.host.ran, hasLength(2));
    });

    // 🗣️유저 2026-10-06 (asked whether letters need the switch the shape
    // fill and the selection carry): 「권장대로. 2차에서 스위치로 넣음」.
    testWidgets('🚨the smoothing switch is ON for letters as they have '
        'always been — turned off, every letter of the text in hand is '
        'HARD, as one step, and so will the next text\'s be', (tester) async {
      final hand = await pumpSettings(
        tester,
        text: said([run('ab'), run('cd', red)]),
      );
      expect(smoothRing(tester).value, isTrue);
      expect(smoothRing(tester).mixed, isFalse);
      expect(
        find.descendant(
          of: row('antialias'),
          matching: find.text(AppText.strings.brAntiAlias),
        ),
        findsOneWidget,
        reason: 'under the word the shape fill and the selection say',
      );

      await tester.ensureVisible(row('antialias'));
      await tester.pump();
      await tester.tap(row('antialias'));
      await tester.pump();

      expect(
        [for (final span in landedOn(hand.cel).spans) span.style.antialias],
        [false, false],
      );
      expect(
        [for (final span in landedOn(hand.cel).spans) span.style.color],
        [plain.color, red.color],
        reason: 'and nothing else of them is another',
      );
      expect(hand.host.ran, hasLength(1));
      expect(smoothRing(tester).value, isFalse);
      expect(hand.options.value.letters.antialias, isFalse);
    });

    testWidgets('letters that do not agree on it show its ring MIXED, and a '
        'press smooths them all', (tester) async {
      final hand = await pumpSettings(
        tester,
        text: said([
          run('ab', const TextLetterStyle(fontSize: 16, antialias: false)),
          run('cd'),
        ]),
      );
      expect(smoothRing(tester).mixed, isTrue);
      expect(smoothRing(tester).value, isFalse);

      await tester.ensureVisible(row('antialias'));
      await tester.pump();
      await tester.tap(row('antialias'));
      await tester.pump();

      expect(landedOn(hand.cel).spans.single.style.antialias, isTrue);
    });

    // 🗣️유저 2026-10-06: 「세로쓰기: 1차는 가로만」 → 「어차피 타임시트나
    // x시트에서 가로쓰기/세로표기같은거 한거 많으니 그거 통합하면서
    // 진행해도될듯」.
    testWidgets('🚨the way of writing: lines is lit for a text as it has '
        'always been — 「세로」 pressed, the text in hand is written in '
        'COLUMNS where it stands, as one step, and so will the next be', (
      tester,
    ) async {
      final before = said([run('ab'), run('cd', red)]);
      final hand = await pumpSettings(tester, text: before);
      expect(pill(tester, 'writing-lines').selected, isTrue);
      expect(pill(tester, 'writing-columns').selected, isFalse);

      await tester.tap(row('writing-columns'));
      await tester.pump();

      expect(landedOn(hand.cel), celTextWrittenAs(before, vertical: true));
      expect(landedOn(hand.cel).vertical, isTrue);
      expect(hand.host.ran, hasLength(1));
      expect(pill(tester, 'writing-columns').selected, isTrue);
      expect(pill(tester, 'writing-lines').selected, isFalse);
      expect(hand.options.value.vertical, isTrue);

      await tester.tap(row('writing-lines'));
      await tester.pump();

      expect(landedOn(hand.cel).vertical, isFalse);
      expect(hand.options.value.vertical, isFalse);
    });

    testWidgets('🚨the alignment\'s answers are NAMED by where they are on '
        'screen: the head, the middle and the foot of a column are its top, '
        'its middle and its bottom — the seats and the values the same', (
      tester,
    ) async {
      final strings = AppText.strings;
      Finder named(String answer, String label) => find.descendant(
        of: row('align-$answer'),
        matching: find.text(label),
      );
      final hand = await pumpSettings(tester, text: said([run('ab')]));
      expect(named('left', strings.textToolAlignLeft), findsOneWidget);
      expect(named('right', strings.textToolAlignRight), findsOneWidget);
      final seat = tester.getTopLeft(row('align-right'));

      await tester.tap(row('writing-columns'));
      await tester.pump();

      expect(named('left', strings.textToolAlignTop), findsOneWidget);
      expect(named('center', strings.textToolAlignCenter), findsOneWidget);
      expect(named('right', strings.textToolAlignBottom), findsOneWidget);
      expect(named('left', strings.textToolAlignLeft), findsNothing);
      expect(tester.getTopLeft(row('align-right')).dy, seat.dy);

      await tester.tap(row('align-right'));
      await tester.pump();

      expect(landedOn(hand.cel).align, TextCelAlign.right);
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
      PanelFlyoutItem face(String name) => tester
          .widget<PopupMenuItem<PanelFlyoutItem>>(row('font-$name'))
          .value!;
      expect(face(AppTypography.bundledFamily).selected, isTrue);
      expect(face('Nanum Gothic').selected, isFalse);
      await tester.tap(row('font-Nanum Gothic'));
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

    testWidgets('the box behind the letters is picked as a colour is — it '
        'lands when its window closes — and taken off with 「없음」', (
      tester,
    ) async {
      final hand = await pumpSettings(tester, text: said([run('ab')]));

      await tester.tap(row('background'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('color-picker-use-current')),
      );
      await tester.pump();
      expect(hand.host.ran, isEmpty, reason: 'the window is still open');
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(landedOn(hand.cel).backgroundColor, 0xFFAABBCC);
      expect(hand.options.value.backgroundColor, 0xFFAABBCC);
      expect(hand.host.ran, hasLength(1));

      await tester.tap(row('background'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('color-picker-none')),
      );
      await tester.pump();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(landedOn(hand.cel).backgroundColor, isNull);
      expect(hand.options.value.backgroundColor, isNull);
      expect(hand.host.ran, hasLength(2));
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
      expect(
        (deleteButton(tester).icon as Icon).color,
        AppColors.deleteGlyph(enabled: true),
      );

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

  test('「그림으로 굳히기」 is said in EVERY language — in Korean as the '
      'layout 유저 took wrote it, elsewhere by the app\'s own word for a '
      'layer made pixels', () {
    expect(
      {
        for (final language in AppLanguage.values)
          language: AppStrings.of(language).textToolIntoDrawing,
      },
      {
        AppLanguage.en: 'Rasterize',
        AppLanguage.ja: 'ラスタライズ',
        AppLanguage.ko: '그림으로 굳히기',
        AppLanguage.fr: 'Pixelliser',
        AppLanguage.zhHans: '栅格化',
      },
    );
  });

  // 유저 2026-10-06: 「동작은 텍스트 선택하면 해당 버튼 활성화색」.
  testWidgets('🚨「그림으로 굳히기」 is LIT while a text is in hand, and '
      'pressed it turns that text into its cel\'s drawing — one step, the '
      'hand free, and the button out again', (tester) async {
    final hand = await pumpSettings(tester, text: said([run('ab')]));
    expect(pictureUnder(hand.cel).tiles, isEmpty, reason: '⛔fixture');
    expect(intoDrawing(tester).onPressed, isNotNull);

    await tester.ensureVisible(row('into-drawing'));
    await tester.pump();
    await tester.tap(row('into-drawing'));
    await tester.pump();

    final picture = pictureUnder(hand.cel);
    expect(picture.texts, isEmpty);
    expect(picture.tiles, isNotEmpty, reason: 'its pixels are the drawing');
    expect(hand.tool.session, isNull);
    expect(hand.host.ran.single.description, 'Text to drawing');
    expect(intoDrawing(tester).onPressed, isNull);
    expect(
      tester.widget<PanelFlyoutButton>(row('selected-text')).label,
      isEmpty,
    );
  });

  // The press law (CLAUDE.md): 「컨트롤 위에서 시작한 제스처는 그 컨트롤의
  // 것이다. 스크롤은 그 외에서 일어난다」.
  testWidgets('🚨a press on 「그림으로 굳히기」 that WOBBLES is still the '
      'button\'s: the text turns, and the settings do not scroll', (
    tester,
  ) async {
    final hand = await pumpSettings(
      tester,
      text: said([run('ab')]),
      height: 320,
    );
    final list = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const ValueKey<String>('tool-settings-text')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(list.maxScrollExtent, greaterThan(0), reason: '⛔fixture: it scrolls');
    // The button is at the foot of the list, and not built until the list
    // is there — where a hand dragging DOWN has all of it to scroll.
    list.jumpTo(list.maxScrollExtent);
    await tester.pump();
    final scrolledTo = list.pixels;
    final button = tester.getRect(row('into-drawing'));
    expect(button.height, greaterThan(24), reason: '⛔fixture: room to wobble');

    // Down at its top, and past a finger's slop (18) before it comes up —
    // inside the button all the way.
    final finger = await tester.startGesture(
      button.topCenter + const Offset(0, 2),
    );
    await tester.pump();
    await finger.moveBy(const Offset(0, 11));
    await tester.pump();
    await finger.moveBy(const Offset(0, 11));
    await tester.pump();
    await finger.up();
    await tester.pump();

    expect(list.pixels, scrolledTo);
    expect(pictureUnder(hand.cel).texts, isEmpty);
    expect(hand.host.ran.single.description, 'Text to drawing');
  });

  group('🚨the list of the cel\'s texts — 유저: 「거기서 다른 텍스트 '
      '선택할수있게 리스트 고르는 … 텍스트의 이름은 그냥 텍스트 글자대로. '
      '그리고 옆에 삭제버튼 있고」', () {
    /// The settings over a cel that carries 「under」 beneath 「over\ntop」,
    /// the one on top in hand.
    Future<TextHand> pumpTwo(WidgetTester tester) async {
      final hand = await pumpSettings(tester, text: said([run('under')]));
      hand.tool.confirm();
      hand.tool.beginText(hand.cel, CanvasPoint(x: 40, y: 40));
      hand.tool.letters!.value = const TextEditingValue(
        text: 'over\ntop',
        selection: TextSelection.collapsed(offset: 8),
      );
      hand.tool.stopTyping();
      await tester.pump();
      expect(pictureUnder(hand.cel).texts, hasLength(2), reason: '⛔fixture');
      expect(hand.tool.session!.textId, 2, reason: '⛔fixture');
      return hand;
    }

    Future<void> openList(WidgetTester tester) async {
      await tester.tap(row('selected-text'));
      await tester.pumpAndSettle();
    }

    PanelFlyoutItem listed(WidgetTester tester, int place) => tester
        .widget<PopupMenuItem<PanelFlyoutItem>>(row('text-$place'))
        .value!;

    testWidgets('opens on every text of the cel, the top of the stack '
        'first, each by its letters on one line — the one in hand marked', (
      tester,
    ) async {
      await pumpTwo(tester);

      await openList(tester);

      expect(listed(tester, 0).label, 'over top');
      expect(listed(tester, 0).selected, isTrue);
      expect(listed(tester, 1).label, 'under');
      expect(listed(tester, 1).selected, isFalse);
      expect(row('text-2'), findsNothing);
      // Each with a delete of its own, in the delete red.
      for (final place in [0, 1]) {
        expect(
          tester
              .widget<Icon>(
                find.descendant(
                  of: row('text-$place-delete'),
                  matching: find.byIcon(Icons.delete_outline),
                ),
              )
              .color,
          AppColors.deleteGlyph(enabled: true),
          reason: 'row $place',
        );
      }
    });

    testWidgets('a text PICKED is the one in hand, by its box', (tester) async {
      final hand = await pumpTwo(tester);
      final steps = hand.host.ran.length;

      await openList(tester);
      // Where its name is, clear of the delete at the row's end.
      await tester.tapAt(tester.getTopLeft(row('text-1')) + const Offset(24, 16));
      await tester.pumpAndSettle();

      expect(hand.tool.session!.textId, 1);
      expect(hand.tool.letters, isNull);
      expect(hand.host.ran, hasLength(steps), reason: 'nothing to land');
      expect(
        tester.widget<PanelFlyoutButton>(row('selected-text')).label,
        'under',
      );
    });

    testWidgets('🚨a row\'s DELETE takes that text off its cel — one step — '
        'and the one in hand stays in hand', (tester) async {
      final hand = await pumpTwo(tester);
      final steps = hand.host.ran.length;

      await openList(tester);
      await tester.tap(row('text-1-delete'));
      await tester.pumpAndSettle();

      expect(
        [for (final text in pictureUnder(hand.cel).texts) text.content.text],
        ['over\ntop'],
      );
      expect(hand.host.ran, hasLength(steps + 1));
      expect(hand.tool.session!.textId, 2);
    });

    testWidgets('the delete of the one in hand lets go of it', (tester) async {
      final hand = await pumpTwo(tester);

      await openList(tester);
      await tester.tap(row('text-0-delete'));
      await tester.pumpAndSettle();

      expect(
        [for (final text in pictureUnder(hand.cel).texts) text.content.text],
        ['under'],
      );
      expect(hand.tool.session, isNull);
      // The cel still carries a text: the list stays open to it.
      expect(
        tester.widget<PanelFlyoutButton>(row('selected-text')).enabled,
        isTrue,
      );
    });

    testWidgets('with nothing in hand the list still opens on the cel\'s '
        'texts, none marked', (tester) async {
      final hand = await pumpTwo(tester);
      hand.tool.confirm();
      await tester.pump();

      await openList(tester);

      expect(listed(tester, 0).label, 'over top');
      expect(listed(tester, 0).selected, isFalse);
      expect(listed(tester, 1).selected, isFalse);
    });

    testWidgets('🚨the list shuts when the cel\'s last text is gone, and '
        'opens again when one is back — told by the tool', (tester) async {
      final hand = await pumpSettings(tester, text: said([run('only')]));
      hand.tool.confirm();
      await tester.pump();
      expect(
        tester.widget<PanelFlyoutButton>(row('selected-text')).enabled,
        isTrue,
        reason: '⛔fixture',
      );

      // A step of history takes the text off its cel behind the tool's
      // back; the canvas, which draws that, tells the tool.
      hand.cel.coordinator.restoreSurfaceSnapshot(
        hand.cel.key,
        pictureUnder(hand.cel).withTexts(const []),
      );
      hand.tool.celTextsChanged();
      await tester.pump();

      expect(
        tester.widget<PanelFlyoutButton>(row('selected-text')).enabled,
        isFalse,
      );
    });
  });

  testWidgets('the bars run over what can be set from here: sizes multiply '
      'up from the smallest a scale stops at, tracking runs either side of '
      'none, an outline from none, a line pitch in steps of a twentieth', (
    tester,
  ) async {
    await pumpSettings(tester);

    final size = bar(tester, 'size');
    expect(
      (size.min, size.max, size.scale, size.divisions, size.unit),
      (celTextMinFontSize, 2000.0, FieldSliderScale.exponential, null, ' px'),
    );
    final tracking = bar(tester, 'tracking');
    expect(
      (
        tracking.min,
        tracking.max,
        tracking.scale,
        tracking.divisions,
        tracking.unit,
      ),
      (-100.0, 100.0, FieldSliderScale.linear, 200, ''),
    );
    final outline = bar(tester, 'outline-width');
    expect(
      (
        outline.min,
        outline.max,
        outline.scale,
        outline.divisions,
        outline.unit,
      ),
      (0.0, 64.0, FieldSliderScale.linear, 64, ' px'),
    );
    final line = bar(tester, 'line-height');
    expect(
      (line.min, line.max, line.divisions, line.displayScale, line.unit),
      (0.5, 3.0, 50, 100.0, '%'),
    );
  });

  testWidgets('🚨in the tool settings PANEL the colour window\'s 「현재 색 '
      '반영」 is the BRUSH\'s colour', (tester) async {
    final options = ValueNotifier(const TextToolOptions(letters: plain));
    addTearDown(options.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              height: 640,
              child: ToolSettingsPanel(
                state: BrushToolState.defaults.copyWith(
                  tool: CanvasTool.text,
                  color: 0xFF336699,
                ),
                onChanged: (_) {},
                fillOptions: const FloodFillOptions(),
                onFillOptionsChanged: (_) {},
                textOptions: options,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(row('color'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('color-picker-use-current')),
    );
    await tester.pump();

    expect(options.value.letters.color, 0xFF336699);
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
    expect(pill(tester, 'writing-columns').onTap, isNull);
    expect(tester.widget<PanelFlyoutButton>(row('font')).enabled, isFalse);
    expect(
      tester
          .widget<SettingsSwitchRow>(
            find.ancestor(
              of: row('antialias'),
              matching: find.byType(SettingsSwitchRow),
            ),
          )
          .onChanged,
      isNull,
    );
    expect(intoDrawing(tester).onPressed, isNull);
  });
}
