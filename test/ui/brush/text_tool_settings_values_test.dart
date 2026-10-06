import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/brush/text_tool_options.dart';
import 'package:anicel/src/ui/brush/text_tool_settings_values.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_hand.dart';
import '../../helpers/cel_text_held_baker.dart';

/// R9-rest (the text tool): WHAT ITS SETTINGS READ AND WRITE — the one law
/// every row of the panel keeps ([TextToolSettingsValues]).
///
/// 🗣️유저 2026-10-02: 「선택해서 그 상태에서 도구설정에서 폰트바꾸면 해당
/// 텍스트박스 설정 자동으로 바꿈 … 텍스트를 선택하고 조절하면 일부만 텍스트
/// 조절」 · 2026-10-06: 「공용화할 텍스트 도구설정 로직」. Read off the text
/// in hand, or off the next text when there is none; written on BOTH.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const plain = TextLetterStyle(fontSize: 8);
  const red = TextLetterStyle(fontSize: 8, color: 0xFFFF0000);
  const large = TextLetterStyle(fontSize: 16);

  CelTextSpan run(String words, [TextLetterStyle style = plain]) =>
      CelTextSpan(text: words, style: style);

  CelTextContent said(
    List<CelTextSpan> spans, {
    double? wrapWidth,
    TextCelAlign align = TextCelAlign.left,
    double lineHeight = CelTextContent.defaultLineHeight,
    int? background,
  }) => CelTextContent(
    spans: spans,
    anchor: CanvasPoint(x: 8, y: 8),
    wrapWidth: wrapWidth,
    align: align,
    lineHeight: lineHeight,
    backgroundColor: background,
  );

  /// The settings over a hand that holds [text] by its box — or, with
  /// none, nothing — and the next text's values. The engine is HELD: a
  /// test says when a text wanted becomes a text made.
  ({
    TextToolSettingsValues values,
    ValueNotifier<TextToolOptions> options,
    CelTextTool tool,
    TextHandHost host,
    HeldBaker baker,
    CelTextCel cel,
  })
  settings({
    CelTextContent? text,
    TextToolOptions next = const TextToolOptions(letters: plain),
  }) {
    final baker = HeldBaker();
    final (:tool, :host, :options, :cel) = textHand(
      bake: baker.call,
      text: text,
      next: next,
    );
    return (
      values: TextToolSettingsValues(options: options, tool: tool),
      options: options,
      tool: tool,
      host: host,
      baker: baker,
      cel: cel,
    );
  }

  CelTextContent landed(CelTextCel cel) => landedOn(cel);

  group('with NO text in hand', () {
    test('it shows what the next text will start as', () {
      final (:values, options: _, tool: _, host: _, baker: _, cel: _) =
          settings(
            next: const TextToolOptions(
              letters: red,
              align: TextCelAlign.right,
              lineHeight: 2,
              backgroundColor: 0xFF00FF00,
            ),
          );

      expect(values.letter((style) => style.color), (
        value: 0xFFFF0000,
        mixed: false,
      ));
      expect(values.align, TextCelAlign.right);
      expect(values.lineHeight, 2);
      expect(values.backgroundColor, 0xFF00FF00);
    });

    test('a change is the next text\'s — and nothing lands', () {
      final (:values, :options, tool: _, :host, baker: _, cel: _) = settings();

      values
        ..setLetters((style) => style.copyWith(fontSize: 30))
        ..setAlign(TextCelAlign.center)
        ..setLineHeight(1.5)
        ..setBackgroundColor(0xFF112233);

      expect(options.value.letters.fontSize, 30);
      expect(options.value.align, TextCelAlign.center);
      expect(options.value.lineHeight, 1.5);
      expect(options.value.backgroundColor, 0xFF112233);
      expect(host.ran, isEmpty);
    });

    test('🚨whether the next text grows or wraps is not a setting: the '
        'hand says, by a click or a drag', () {
      final (:values, :options, tool: _, :host, baker: _, cel: _) = settings();
      final before = options.value;

      expect(values.wraps, isNull);
      expect(values.canSetWraps(wraps: true), isFalse);
      expect(values.canSetWraps(wraps: false), isFalse);

      values.setWraps(true);

      expect(options.value, before);
      expect(host.ran, isEmpty);
    });
  });

  group('with a text in hand', () {
    test('🚨it shows the TEXT\'s values, whatever the next text\'s are', () {
      final (:values, options: _, tool: _, host: _, baker: _, cel: _) =
          settings(
            text: said(
              [run('ab', large)],
              align: TextCelAlign.center,
              lineHeight: 2,
            ),
            next: const TextToolOptions(
              letters: plain,
              backgroundColor: 0xFF00FF00,
            ),
          );

      expect(values.letter((style) => style.fontSize), (
        value: 16.0,
        mixed: false,
      ));
      expect(values.align, TextCelAlign.center);
      expect(values.lineHeight, 2);
      // ⚠️None is a VALUE: this text has no box behind it, and the next
      // text's green is not shown in its place.
      expect(values.backgroundColor, isNull);
    });

    test('🚨taking a text in hand changes nothing of the next text', () {
      const next = TextToolOptions(letters: plain);

      final (values: _, :options, tool: _, host: _, baker: _, cel: _) =
          settings(text: said([run('ab', large)]), next: next);

      expect(options.value, next);
    });

    test('🚨a setting its runs do not agree on is MIXED, and shows the '
        'first run\'s; one they agree on is not', () {
      final (:values, options: _, tool: _, host: _, baker: _, cel: _) =
          settings(text: said([run('ab', red), run('cd', large)]));

      expect(values.letter((style) => style.color), (
        value: 0xFFFF0000,
        mixed: true,
      ));
      expect(values.letter((style) => style.fontSize), (
        value: 8.0,
        mixed: true,
      ));
      expect(values.letter((style) => style.bold), (
        value: false,
        mixed: false,
      ));
    });

    test('🚨a change is made on BOTH: every letter of the text — each '
        'keeping the rest of what it wore — and the next text', () async {
      final (:values, :options, tool: _, :host, :baker, :cel) = settings(
        text: said([run('ab', red), run('cd', large)]),
      );

      values.setLetters((style) => style.copyWith(bold: true));
      await baker.pending.answer();

      expect(landed(cel).spans, [
        run('ab', red.copyWith(bold: true)),
        run('cd', large.copyWith(bold: true)),
      ]);
      expect(host.ran, hasLength(1));
      expect(options.value.letters, plain.copyWith(bold: true));
      expect(values.letter((style) => style.bold), (value: true, mixed: false));
    });

    test('🚨with letters SELECTED it shows those and reaches those alone', () async {
      final (:values, options: _, :tool, host: _, :baker, :cel) = settings(
        text: said([run('ab', red), run('cd', large)]),
      );
      tool.typeAt(const TextSelection(baseOffset: 2, extentOffset: 4));

      // 「cd」 alone: one run, nothing mixed.
      expect(values.letter((style) => style.fontSize), (
        value: 16.0,
        mixed: false,
      ));

      values.setLetters((style) => style.copyWith(fontSize: 24));
      tool.stopTyping();
      await baker.pending.answer();

      expect(landed(cel).spans, [
        run('ab', red),
        run('cd', large.copyWith(fontSize: 24)),
      ]);
    });

    test('a text with NO letters shows what its first letter will wear, and '
        'a change sets that', () {
      final (:values, :options, :tool, host: _, baker: _, :cel) = settings(
        next: const TextToolOptions(letters: red),
      );
      tool.beginText(cel, CanvasPoint(x: 8, y: 8));

      expect(values.letter((style) => style.color), (
        value: 0xFFFF0000,
        mixed: false,
      ));

      values.setLetters((style) => style.copyWith(color: 0xFF0000FF));

      expect(tool.session!.nextLetterStyle.color, 0xFF0000FF);
      expect(options.value.letters.color, 0xFF0000FF);
      expect(values.letter((style) => style.color).value, 0xFF0000FF);
    });

    test('a setting of the WHOLE text reaches the text and the next one', () async {
      final (:values, :options, tool: _, :host, :baker, :cel) = settings(
        text: said([run('ab')]),
      );

      values.setAlign(TextCelAlign.right);
      await baker.pending.answer();
      values.setBackgroundColor(0xFF445566);
      await baker.pending.answer();

      expect(landed(cel).align, TextCelAlign.right);
      expect(landed(cel).backgroundColor, 0xFF445566);
      expect(host.ran, hasLength(2));
      expect(options.value.align, TextCelAlign.right);
      expect(options.value.backgroundColor, 0xFF445566);
    });

    test('the box behind the letters is taken off the text, and off the '
        'next', () async {
      final (:values, :options, tool: _, host: _, :baker, :cel) = settings(
        text: said([run('ab')], background: 0xFF445566),
        next: const TextToolOptions(letters: plain, backgroundColor: 0xFF1),
      );

      values.setBackgroundColor(null);
      await baker.pending.answer();

      expect(landed(cel).backgroundColor, isNull);
      expect(options.value.backgroundColor, isNull);
    });
  });

  group('a value still being dragged', () {
    test('🚨shows and does not land; the one it comes to rest on lands — '
        'ONE step for the whole drag', () async {
      final (:values, options: _, :tool, :host, :baker, :cel) = settings(
        text: said([run('ab')]),
      );

      values.setLetters(
        (style) => style.copyWith(fontSize: 10),
        settled: false,
      );
      await baker.pending.answer();
      values.setLetters(
        (style) => style.copyWith(fontSize: 12),
        settled: false,
      );
      await baker.pending.answer();

      expect(host.ran, isEmpty);
      expect(landed(cel).spans.single.style.fontSize, 8);
      expect(tool.session!.shown.content.spans.single.style.fontSize, 12);

      values.setLetters((style) => style.copyWith(fontSize: 12));

      expect(host.ran, hasLength(1));
      expect(landed(cel).spans.single.style.fontSize, 12);
    });

    test('🚨a colour comes to rest when its window says so: settle lands '
        'what was shown, once', () async {
      final (:values, options: _, tool: _, :host, :baker, :cel) = settings(
        text: said([run('ab')]),
      );

      values.setLetters(
        (style) => style.copyWith(color: 0xFF010203),
        settled: false,
      );
      await baker.pending.answer();
      values.setBackgroundColor(0xFF040506, settled: false);
      await baker.pending.answer();

      expect(host.ran, isEmpty);

      values.settle();

      expect(host.ran, hasLength(1));
      expect(landed(cel).spans.single.style.color, 0xFF010203);
      expect(landed(cel).backgroundColor, 0xFF040506);

      values.settle();

      expect(host.ran, hasLength(1), reason: 'nothing more to land');
    });

    test('a line pitch dragged is the next text\'s as it goes', () {
      final (:values, :options, tool: _, host: _, baker: _, cel: _) =
          settings();

      values.setLineHeight(1.75, settled: false);

      expect(options.value.lineHeight, 1.75);
    });
  });

  group('a text that grows, and a box', () {
    test('it says which the text in hand is', () {
      expect(settings(text: said([run('ab')])).values.wraps, isFalse);
      expect(
        settings(text: said([run('ab')], wrapWidth: 40)).values.wraps,
        isTrue,
      );
    });

    test('🚨swapped, the text in hand is the other — one step — and the '
        'next text hears nothing of it', () async {
      final (:values, :options, tool: _, :host, :baker, :cel) = settings(
        text: said([run('ab')]),
      );
      final next = options.value;

      values.setWraps(true);
      await baker.pending.answer();

      // 「ab」 at 8 is 16 wide, and a box is a pixel past its longest line.
      expect(landed(cel).wrapWidth, 17);
      expect(host.ran, hasLength(1));
      expect(values.wraps, isTrue);
      expect(options.value, next);

      values.setWraps(false);
      await baker.pending.answer();

      expect(landed(cel).wrapWidth, isNull);
      expect(host.ran, hasLength(2));
    });

    test('swapped to what it already is, nothing lands', () {
      final (:values, options: _, tool: _, :host, :baker, cel: _) = settings(
        text: said([run('ab')], wrapWidth: 40),
      );

      values.setWraps(true);

      expect(baker.asked, isEmpty);
      expect(host.ran, isEmpty);
    });

    test('⛔a text with NO letters cannot be made a box — it has no line to '
        'be as wide as — and can be made to grow', () {
      final (:values, options: _, :tool, host: _, baker: _, :cel) = settings();
      tool.beginText(cel, CanvasPoint(x: 8, y: 8));

      expect(values.wraps, isFalse);
      expect(values.canSetWraps(wraps: true), isFalse);
      expect(values.canSetWraps(wraps: false), isTrue);

      tool
        ..confirm()
        ..beginText(cel, CanvasPoint(x: 8, y: 8), wrapWidth: 40);

      expect(values.wraps, isTrue);
      expect(values.canSetWraps(wraps: true), isTrue);
      expect(values.canSetWraps(wraps: false), isTrue);
    });
  });

  group('where a change can go', () {
    test('a host that owns no settings and holds no text takes none', () {
      const nowhere = TextToolSettingsValues(options: null, tool: null);

      expect(nowhere.writable, isFalse);
      expect(nowhere.letter((style) => style.fontSize), (
        value: TextToolOptions.defaults.letters.fontSize,
        mixed: false,
      ));
      expect(nowhere.align, TextToolOptions.defaults.align);

      // And saying one anyway is nobody's.
      nowhere
        ..setLetters((style) => style.copyWith(bold: true))
        ..setAlign(TextCelAlign.right)
        ..setWraps(true)
        ..settle();
    });

    test('with settings and no canvas, the next text\'s', () {
      final options = ValueNotifier(TextToolOptions.defaults);
      addTearDown(options.dispose);
      final values = TextToolSettingsValues(options: options, tool: null);

      expect(values.writable, isTrue);

      values.setLetters((style) => style.copyWith(bold: true));

      expect(options.value.letters.bold, isTrue);
    });

    test('with a text in hand and no settings of its own, the text', () async {
      final (values: _, options: _, :tool, :host, :baker, :cel) = settings(
        text: said([run('ab')]),
      );
      final values = TextToolSettingsValues(options: null, tool: tool);

      expect(values.writable, isTrue);

      values.setLetters((style) => style.copyWith(bold: true));
      await baker.pending.answer();

      expect(landed(cel).spans.single.style.bold, isTrue);
      expect(host.ran, hasLength(1));
    });
  });
}
