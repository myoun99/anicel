import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_editing_controller.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_field.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_stage.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_fixture.dart';

/// R9-rest (the text tool): THE FIELD THE KEYBOARD TYPES INTO — there for
/// the keyboard and never seen.
///
/// It is laid out ON THE ARTWORK, where the text is, from the very spans
/// the canvas sets: so the lines it breaks, and the lines its caret moves
/// up and down, are the canvas's. Each thing a stock field does to its own
/// layout that the canvas does not — a strut, the caret's margin, the
/// user's text scale — is switched off, and each is asked here whether it
/// stayed off.
///
/// In the test font a letter is a box its size wide: 「ab」 at 8 is 16
/// wide, and a line is its letters' size times the text's pitch.
void main() {
  const small = TextLetterStyle(fontSize: 8);
  const large = TextLetterStyle(fontSize: 16);

  CelTextContent said(
    List<CelTextSpan> spans, {
    double x = 8,
    double y = 8,
    double? wrapWidth,
    double turn = 0,
    TextCelAlign align = TextCelAlign.left,
    bool vertical = false,
  }) => CelTextContent(
    spans: spans,
    anchor: CanvasPoint(x: x, y: y),
    wrapWidth: wrapWidth,
    rotationDegrees: turn,
    align: align,
    lineHeight: 1,
    vertical: vertical,
  );

  CelTextSpan run(String words, [TextLetterStyle style = small]) =>
      CelTextSpan(text: words, style: style);

  final stage = CelTextStage(
    viewport: CanvasViewport(zoom: 2, panX: 10, panY: 20),
    canvasSize: celTextTestCanvas,
    placement: null,
  );

  /// The letters of the field last mounted.
  late CelTextEditingController mounted;

  /// The field for [content], mounted, and what it was laid out as.
  Future<({RenderEditable field, CelTextLayout layout, List<String> log})>
  pumpField(
    WidgetTester tester,
    CelTextContent content, {
    double textScale = 1,
  }) async {
    final letters = CelTextEditingController(
      content: content,
      nextLetterStyle: small,
    );
    addTearDown(letters.dispose);
    mounted = letters;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final layout = layoutCelText(content, nextLetterStyle: small);
    addTearDown(layout.dispose);
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: CelTextField(
                  letters: letters,
                  focusNode: focus,
                  stage: stage,
                  shown: layout,
                  onEscape: () => log.add('escape'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    return (
      field: tester
          .state<EditableTextState>(
            find.byType(EditableText, skipOffstage: false),
          )
          .renderEditable,
      layout: layout,
      log: log,
    );
  }

  testWidgets('🚨its lines are the canvas\'s: each as tall as its own '
      'letters — no strut holds a line of small letters up', (tester) async {
    // A large line over a small one. A stock field's strut is the height
    // of the style its runs are nested in — the LAST run's, the small one —
    // and holds every line to it: two lines of 8.
    final (:field, :layout, log: _) = await pumpField(
      tester,
      said([run('A', large), run('\nb')]),
    );

    expect(layout.block.height, greaterThan(16), reason: '⛔fixture');
    expect(field.size.height, layout.block.height);
  });

  testWidgets('🚨a box breaks its lines where the canvas breaks them: the '
      'room a field keeps for its caret is not taken out of the width', (
    tester,
  ) async {
    // 「ab」 fills a box 16 wide exactly, and 「c」 goes to the next line.
    final (:field, :layout, log: _) = await pumpField(
      tester,
      said([run('abc')], wrapWidth: 16),
    );

    expect(layout.block.height, 16, reason: '⛔fixture: two lines');
    expect(field.size.height, layout.block.height);
  });

  testWidgets('a text that grows is not forced to the width it is given: '
      'its field is as wide as its letters, and one line a line', (
    tester,
  ) async {
    final (:field, :layout, log: _) = await pumpField(
      tester,
      said([run('ab\nc')]),
    );

    expect(field.size.height, layout.block.height);
    expect(field.size.width, lessThan(layout.block.width + 2));
  });

  testWidgets('🚨a short line in a BOX stands where the alignment puts it '
      'in the box: the caret the IME is told of is the canvas\'s', (
    tester,
  ) async {
    // 「ab」 is 16 wide in a box of 40: set to the right, it starts at 24.
    final (:field, :layout, log: _) = await pumpField(
      tester,
      said([run('ab')], wrapWidth: 40, align: TextCelAlign.right),
    );

    final onCanvas = layout.caretRect(const TextPosition(offset: 0));
    expect(onCanvas.left - layout.block.left, 24, reason: '⛔fixture');
    expect(
      field.getLocalRectForCaret(const TextPosition(offset: 0)).left,
      24,
    );
  });

  testWidgets('the user\'s text scale does not reach it: a text on a cel is '
      'set in canvas pixels', (tester) async {
    final (:field, :layout, log: _) = await pumpField(
      tester,
      said([run('abc')], wrapWidth: 16),
      textScale: 2,
    );

    expect(field.size.height, layout.block.height);
  });

  testWidgets('it stands where the text stands, under the panel\'s view of '
      'the artwork — the IME composes beside the caret', (tester) async {
    final (:field, layout: _, log: _) = await pumpField(
      tester,
      said([run('ab')], x: 6, y: 9),
    );

    // The canvas pixel (6, 9) at two screen pixels a pixel, the view panned
    // by (10, 20).
    final origin = MatrixUtils.transformPoint(
      field.getTransformTo(null),
      Offset.zero,
    );
    expect(origin.dx, closeTo(6 * 2 + 10, 1e-9));
    expect(origin.dy, closeTo(9 * 2 + 20, 1e-9));
    // And as large as the view shows the artwork.
    final right = MatrixUtils.transformPoint(
      field.getTransformTo(null),
      const Offset(16, 0),
    );
    expect(right.dx - origin.dx, closeTo(32, 1e-9));
  });

  testWidgets('a centred text that grows stands about its anchor: the '
      'field starts where its lines do', (tester) async {
    final (:field, layout: _, log: _) = await pumpField(
      tester,
      said([run('ab')], x: 16, y: 9, align: TextCelAlign.center),
    );

    // 「ab」 is 16 wide: its lines start 8 left of the anchor.
    final origin = MatrixUtils.transformPoint(
      field.getTransformTo(null),
      Offset.zero,
    );
    expect(origin.dx, closeTo((16 - 8) * 2 + 10, 1e-9));
  });

  // 세로쓰기 (유저 2026-10-06).
  group('a text in COLUMNS', () {
    testWidgets('🚨its field lies DOWN them: from the block\'s top right '
        'corner, its line runs down the first column — the IME composes '
        'beside the caret there too', (tester) async {
      final (:field, :layout, log: _) = await pumpField(
        tester,
        said([run('ab')], x: 16, y: 9, vertical: true),
      );
      expect(
        layout.block,
        const Rect.fromLTWH(-8, 0, 8, 16),
        reason: '⛔fixture',
      );

      // The canvas pixel (16, 9) — the block's top right — at two screen
      // pixels a pixel, the view panned by (10, 20).
      final origin = MatrixUtils.transformPoint(
        field.getTransformTo(null),
        Offset.zero,
      );
      expect(origin.dx, closeTo(16 * 2 + 10, 1e-9));
      expect(origin.dy, closeTo(9 * 2 + 20, 1e-9));
      // Along the field's line is DOWN the screen.
      final along = MatrixUtils.transformPoint(
        field.getTransformTo(null),
        const Offset(16, 0),
      );
      expect(along.dx, closeTo(origin.dx, 1e-9));
      expect(along.dy - origin.dy, closeTo(32, 1e-9));
    });

    /// 「あい」 in the first column, 「うえ」 in the one to its left.
    Future<void> pumpTwoColumns(WidgetTester tester, {int caret = 0}) async {
      await pumpField(tester, said([run('あい\nうえ')], vertical: true));
      mounted.selection = TextSelection.collapsed(offset: caret);
    }

    testWidgets('🚨the arrows go where the COLUMNS go: down and up are the '
        'next letter and the one before', (tester) async {
      await pumpTwoColumns(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(mounted.selection, const TextSelection.collapsed(offset: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(mounted.selection, const TextSelection.collapsed(offset: 2));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(mounted.selection, const TextSelection.collapsed(offset: 0));
    });

    testWidgets('🚨left is the column AFTER, as far down it; right the '
        'column before — and past the last column, the text\'s end', (
      tester,
    ) async {
      await pumpTwoColumns(tester, caret: 1);

      // Before 「い」, a letter down the first column: before 「え」.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(mounted.selection, const TextSelection.collapsed(offset: 4));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(mounted.selection, const TextSelection.collapsed(offset: 1));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(mounted.selection, const TextSelection.collapsed(offset: 5));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(mounted.selection, const TextSelection.collapsed(offset: 0));
    });

    testWidgets('with Shift the END of the selection goes there', (
      tester,
    ) async {
      await pumpTwoColumns(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(
        mounted.selection,
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );
    });

    testWidgets('⛔CONTROL: in LINES the arrows are the field\'s own — down '
        'is the line below', (tester) async {
      await pumpField(tester, said([run('あい\nうえ')]));
      mounted.selection = const TextSelection.collapsed(offset: 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);

      // Past the break (offset 2): on the second line, wherever the field
      // stands the caret there — and not the next letter, which is what
      // down is in columns.
      expect(mounted.selection.extentOffset, greaterThan(2));
    });
  });

  testWidgets('it is never painted and never pressed', (tester) async {
    await pumpField(tester, said([run('ab')]));

    expect(find.byType(EditableText), findsNothing);
    expect(find.byType(EditableText, skipOffstage: false), findsOneWidget);
  });

  testWidgets('Esc is the text\'s: it tells its owner, and goes no further', (
    tester,
  ) async {
    final (field: _, layout: _, :log) = await pumpField(
      tester,
      said([run('ab')]),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);

    expect(log, ['escape']);
  });
}
