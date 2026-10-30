import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_frame_grid_settings.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/inbetween_mark.dart';
import 'package:anicel/src/models/se_dialogue_spacing.dart';
import 'package:anicel/src/models/se_line_type.dart';
import 'package:anicel/src/ui/dialogs/instance_edit_preview.dart';
import 'package:anicel/src/ui/dialogs/instruction_event_dialog.dart';
import 'package:anicel/src/ui/dialogs/se_instance_dialog.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/number_pad_keyboard.dart';

/// The preview's paper — the timeline's own row painter.
TimelineRowCellsPainter previewCellsOf(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey<String>('instance-preview-cells')),
            )
            .painter!
        as TimelineRowCellsPainter;

/// The number a window number [key] shows (`WindowNumber`).
String shownIn(WidgetTester tester, String key) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(Text),
      ),
    )
    .data!;

/// Opens [dialog] through a real route so pops deliver results.
Future<void> _openDialog<T>(
  WidgetTester tester,
  Widget dialog,
  void Function(T? result) onResult,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              onResult(
                await showDialog<T>(context: context, builder: (_) => dialog),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String _previewDialogue(WidgetTester tester) {
  return tester
      .widget<DialogueFitText>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('instance-edit-preview')),
          matching: find.byType(DialogueFitText),
        ),
      )
      .text;
}

void main() {
  testWidgets('SE dialog: shared shell keys, live preview, name box only '
      'when the name is set, result round-trip', (tester) async {
    SeInstanceDialogResult? result;
    await _openDialog<SeInstanceDialogResult>(
      tester,
      const SeInstanceDialog(creating: true),
      (r) => result = r,
    );

    expect(
      find.byKey(const ValueKey<String>('instance-edit-dialog')),
      findsOneWidget,
    );
    expect(find.text('New SE'), findsOneWidget);
    // No delete on SE, and no name box while the name field is blank.
    expect(
      find.byKey(const ValueKey<String>('instance-edit-delete-button')),
      findsNothing,
    );
    expect(find.bySemanticsLabel(RegExp('^SE name')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('se-dialogue-field')),
      '그건 아니라고 생각해',
    );
    await tester.pump();
    expect(_previewDialogue(tester), '그건 아니라고 생각해');

    await tester.enterText(
      find.byKey(const ValueKey<String>('se-name-field')),
      '앨리스',
    );
    await tester.pump();
    expect(find.bySemanticsLabel('SE name 앨리스'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();
    expect(result!.seName, '앨리스');
    expect(result!.dialogue, '그건 아니라고 생각해');
    expect(result!.seTypes.own, SeLineType.on, reason: 'I-20: ON is the default');
  });

  testWidgets('SE dialog: a space shows on the preview as it is typed, at '
      'the ends too, and OK keeps the line as typed (F-484)', (tester) async {
    SeInstanceDialogResult? result;
    await _openDialog<SeInstanceDialogResult>(
      tester,
      const SeInstanceDialog(creating: true),
      (r) => result = r,
    );
    final field = find.byKey(const ValueKey<String>('se-dialogue-field'));

    await tester.enterText(field, 'あ');
    await tester.pump();
    await tester.enterText(field, 'あ ');
    await tester.pump();
    expect(_previewDialogue(tester), 'あ ', reason: 'the space just typed');
    await tester.enterText(field, ' あ ');
    await tester.pump();
    expect(_previewDialogue(tester), ' あ ');

    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();
    expect(result!.dialogue, ' あ ', reason: 'what the preview showed');
  });

  testWidgets('SE dialog: the delivery is one of three pills, opens on the '
      'block\'s own and returns the one picked (I-20)', (tester) async {
    SeInstanceDialogResult? result;
    await _openDialog<SeInstanceDialogResult>(
      tester,
      SeInstanceDialog(initialSeTypes: SeLineTypes(own: SeLineType.mono)),
      (r) => result = r,
    );
    for (final type in SeLineType.values) {
      expect(
        find.byKey(ValueKey<String>('se-type-${type.name}')),
        findsOneWidget,
      );
    }
    await tester.tap(find.byKey(const ValueKey<String>('se-type-off')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();
    expect(result!.seTypes.own, SeLineType.off);
  });

  // 🗣️F-496 (유저 2026-10-28): 「OFF랑 MONO도 se블록에 표시」 — and the
  // preview is the block, in the cut the pills set (F-386).
  testWidgets('SE dialog: the preview writes the delivery of the cut the '
      'pills set, and nothing for ON', (tester) async {
    Cut cut(String id) => Cut(
      id: CutId(id),
      name: id,
      duration: 4,
      canvasSize: const CanvasSize(width: 640, height: 360),
      layers: const [],
    );
    await _openDialog<SeInstanceDialogResult>(
      tester,
      SeInstanceDialog(
        initialSeName: 'A',
        initialSeTypes: SeLineTypes(
          byCut: {const CutId('cut-2'): SeLineType.mono},
        ),
        cuts: [cut('cut-1'), cut('cut-2')],
        initialCutId: const CutId('cut-2'),
      ),
      (_) {},
    );
    final said = find.bySemanticsLabel(RegExp('^SE delivery'));
    expect(find.bySemanticsLabel('SE delivery MONO'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('se-type-on')));
    await tester.pump();
    expect(said, findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('se-type-off')));
    await tester.pump();
    expect(find.bySemanticsLabel('SE delivery OFF'), findsOneWidget);
  });

  // 🗣️F-496 ③ (유저 2026-10-28): 「대사 오프셋/글자별 코마 기능 …
  // 글자별 코마는 기본값 3코마, 오프셋은 기본값 0」.
  testWidgets('SE dialog: the offset and the frames a glyph open on the '
      'block\'s own, lay the preview\'s block as they are typed, and come '
      'back on OK', (tester) async {
    const opened = SeDialogueSpacing(offset: 1, komaPerGlyph: 2);
    const typedIn = SeDialogueSpacing(offset: 4, komaPerGlyph: 5);
    SeInstanceDialogResult? result;
    await _openDialog<SeInstanceDialogResult>(
      tester,
      const SeInstanceDialog(
        initialDialogue: 'あいう',
        initialSpacing: opened,
        blockFrames: 30,
      ),
      (r) => result = r,
    );
    const offset = 'se-dialogue-offset-field';
    const koma = 'se-koma-per-glyph-field';
    DialogueFitText preview() => tester.widget<DialogueFitText>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('instance-edit-preview')),
        matching: find.byType(DialogueFitText),
      ),
    );

    expect((shownIn(tester, offset), shownIn(tester, koma)), ('1', '2'));
    expect(preview().spacing, opened);
    expect(
      preview().frames,
      30,
      reason: 'the block as long as it is — the spacing counts in its frames',
    );

    await typeOnThePad(tester, offset, '4');
    await typeOnThePad(tester, koma, '5');
    expect(preview().spacing, typedIn);

    for (var step = 0; step < 5; step += 1) {
      await tester.tap(find.byKey(const ValueKey<String>('$koma-step-down')));
      await tester.pump();
    }
    const kept = SeDialogueSpacing(offset: 4, komaPerGlyph: 1);
    expect(
      (shownIn(tester, koma), preview().spacing),
      ('1', kept),
      reason: 'a koma per glyph moved under one shows the one it keeps',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();
    expect(result!.spacing, kept);
  });

  testWidgets('SE dialog: a new block opens on the standard — from its '
      'first frame, three a glyph', (tester) async {
    SeInstanceDialogResult? result;
    await _openDialog<SeInstanceDialogResult>(
      tester,
      const SeInstanceDialog(creating: true),
      (r) => result = r,
    );
    expect(
      (
        shownIn(tester, 'se-dialogue-offset-field'),
        shownIn(tester, 'se-koma-per-glyph-field'),
      ),
      ('0', '3'),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();
    expect(result!.spacing, SeDialogueSpacing.standard);
  });

  testWidgets('SE dialog: the window opens with the keyboard on the '
      'dialogue', (tester) async {
    await _openDialog<SeInstanceDialogResult>(
      tester,
      const SeInstanceDialog(creating: true),
      (_) {},
    );
    final dialogue = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('se-dialogue-field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(dialogue.focusNode.hasFocus, isTrue);
  });

  testWidgets('SE dialog cancel pops nothing', (tester) async {
    SeInstanceDialogResult? result = const SeInstanceDialogResult(
      seName: 'sentinel',
      dialogue: 'sentinel',
    );
    await _openDialog<SeInstanceDialogResult>(
      tester,
      const SeInstanceDialog(),
      (r) => result = r,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-cancel-button')),
    );
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('instruction dialog: rides the shared shell and returns what '
      'it was handed; Delete shows when editing', (tester) async {
    InstructionEventDialogResult? result;
    await _openDialog<InstructionEventDialogResult>(
      tester,
      InstructionEventDialog(
        instructionSet: CameraInstructionSet.standard,
        initialInstructionId: 'ol',
        initialValueA: 'C',
        initialValueB: 'D',
        editing: true,
      ),
      (r) => result = r,
    );

    expect(
      find.byKey(const ValueKey<String>('instance-edit-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('instance-edit-delete-button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();
    expect(result!.instructionId, 'ol');
    expect(result!.valueA, 'C');
    expect(result!.valueB, 'D');
  });

  testWidgets('preview grows koma with the available width and clamps at '
      'six', (tester) async {
    Future<int> cellCountAt(double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: width,
              child: const InstanceEditPreview.se(
                axis: Axis.horizontal,
                dialogue: '대사',
                seName: '',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return previewCellsOf(tester).frameEndIndexExclusive;
    }

    expect(await cellCountAt(100), 2);
    expect(await cellCountAt(150), 3);
    expect(await cellCountAt(500), 6);
  });

  testWidgets('preview flips to the vertical axis (X-sheet orientation)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: InstanceEditPreview.se(
            axis: Axis.vertical,
            dialogue: '대사',
            seName: '앨리스',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final preview = tester.getSize(
      find.byKey(const ValueKey<String>('instance-edit-preview')),
    );
    expect(preview.height, greaterThan(preview.width));
    expect(find.bySemanticsLabel('SE name 앨리스'), findsOneWidget);
  });

  // 🚨The preview's paper was a widget twin of the rows that kept a box
  // round every koma (D32/D38 took it off the rows) and ignored the
  // block-frame-lines switch (유저 2026-09-24). It asks the row painter now:
  // one piece of paper, and the sheet's lines on it only where the switch
  // shows them.
  testWidgets('the preview\'s block is ONE piece of paper, crossed by the '
      'frame lines exactly where the switch shows them', (tester) async {
    addTearDown(
      () => AppFrameGridSettings.settings.value = const AppFrameGridSettings(),
    );
    for (final shown in [false, true]) {
      AppFrameGridSettings.settings.value = AppFrameGridSettings(
        blockFrameLines: shown,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 500,
              child: InstanceEditPreview.se(
                axis: Axis.horizontal,
                dialogue: '대사',
                seName: '',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cells = previewCellsOf(tester);
      final koma = cells.frameEndIndexExclusive;
      final substrate = cells.substrateIn(0, koma);
      expect(substrate.paper, hasLength(1), reason: 'switch $shown');
      expect(
        substrate.paper.single.rect,
        cells.paperRectFor(0).expandToInclude(cells.paperRectFor(koma - 1)),
      );
      expect(
        substrate.lines,
        hasLength(shown ? koma - 1 : 0),
        reason: 'switch $shown: a line at each koma boundary inside the '
            'block, or none',
      );
    }
  });

  // 🗣️F-489 — the preview asks the row painter, so it wears the unnamed
  // mark the user picked as the rows do.
  testWidgets('the preview\'s rows wear the unnamed mark picked', (
    tester,
  ) async {
    addTearDown(
      () => AppFrameGridSettings.settings.value = const AppFrameGridSettings(),
    );
    for (final mark in InbetweenMark.values) {
      AppFrameGridSettings.settings.value = AppFrameGridSettings(
        unnamedMark: mark,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 500,
              child: InstanceEditPreview.se(
                axis: Axis.horizontal,
                dialogue: '대사',
                seName: '',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(previewCellsOf(tester).unnamedMark, mark);
    }
  });
}
