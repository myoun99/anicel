// THE INSTRUCTION VOCABULARY EDITOR: DELETE DROPS A DEF, ADD OPENS THE DEF
// WINDOW AND A NAMED DEF JOINS THE SET, SAVE POPS THE EDITED SET, CANCEL
// POPS NOTHING.
//
// No test named this dialog (audit 2026-09-03). These pins drive it as a
// user does, through the keys it gives its rows and buttons.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/ui/dialogs/instruction_set_editor_dialog.dart';

void main() {
  CameraInstructionSet initial() => CameraInstructionSet(
    defs: const [
      CameraInstructionDef(id: 'pan', name: 'PAN', iconKey: 'note'),
      CameraInstructionDef(id: 'zoom', name: 'ZOOM', iconKey: 'note'),
    ],
  );

  Future<List<CameraInstructionSet?>> open(WidgetTester tester) async {
    final results = <CameraInstructionSet?>[];
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                results.add(
                  await showDialog<CameraInstructionSet>(
                    context: context,
                    builder: (context) =>
                        InstructionSetEditorDialog(initialSet: initial()),
                  ),
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
    expect(
      find.byKey(const ValueKey<String>('instruction-set-dialog')),
      findsOneWidget,
    );
    return results;
  }

  testWidgets('delete drops the def and save pops the edited set', (
    tester,
  ) async {
    final results = await open(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('instruction-def-delete-pan')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('instruction-def-row-pan')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('instruction-set-save-button')),
    );
    await tester.pumpAndSettle();
    expect(results.single!.defs.map((def) => def.id), ['zoom']);
  });

  testWidgets('add opens the def window and a named def joins the set', (
    tester,
  ) async {
    final results = await open(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('instruction-def-add-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('instruction-def-dialog')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('instruction-def-name-field')),
      'TRACK',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('instruction-def-save-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('instruction-def-row-custom-1')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('instruction-set-save-button')),
    );
    await tester.pumpAndSettle();
    final added = results.single!.defs.firstWhere(
      (def) => def.id == 'custom-1',
    );
    expect(added.name, 'TRACK');
  });

  testWidgets('cancel pops nothing', (tester) async {
    final results = await open(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('instruction-set-cancel-button')),
    );
    await tester.pumpAndSettle();
    expect(results, [null]);
  });
}
