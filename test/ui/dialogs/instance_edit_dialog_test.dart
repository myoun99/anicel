import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/ui/dialogs/instance_edit_preview.dart';
import 'package:anicel/src/ui/dialogs/instruction_event_dialog.dart';
import 'package:anicel/src/ui/dialogs/se_instance_dialog.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cell.dart';

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

  testWidgets('instruction dialog: memo field rides the shared shell and '
      'returns through the result; Delete shows when editing', (tester) async {
    InstructionEventDialogResult? result;
    await _openDialog<InstructionEventDialogResult>(
      tester,
      InstructionEventDialog(
        instructionSet: CameraInstructionSet.standard,
        initialInstructionId: 'ol',
        initialValueA: 'C',
        initialValueB: 'D',
        initialMemo: 'カットO.L',
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

    await tester.enterText(
      find.byKey(const ValueKey<String>('instruction-memo-field')),
      'カットO.L 강조',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();
    expect(result!.instructionId, 'ol');
    expect(result!.memo, 'カットO.L 강조');
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
      return tester
          .widgetList<TimelineFrameCell>(find.byType(TimelineFrameCell))
          .length;
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
}
