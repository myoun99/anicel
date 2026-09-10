// HomePage widget tests — cut notes and the rename dialog.
// Split from widget_test.dart (2026-09-04) so the suite runs across
// isolates; the shared probes live in helpers/home_page_probes.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/models/cut_id.dart';

import 'helpers/home_page_probes.dart';
import 'helpers/app_icon_button_probe.dart';

void main() {
  testWidgets('long multi-line cut note remains editable and savable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    const longNote = '''
Line 1
Line 2
Line 3
Line 4
Line 5
Line 6
Line 7
Line 8''';

    await openCutNoteDialog(tester);
    expect(
      find.byKey(const ValueKey<String>('cut-note-text-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('save-cut-note-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cancel-cut-note-button')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('cut-note-text-field')),
      longNote,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('cancel-cut-note-button')),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('save-cut-note-button')),
    );
    await tapCutNoteSaveButton(tester);

    expect(await currentCutNoteFromDialog(tester), longNote);
    await expectActiveCutName(tester, '1');
  });

  testWidgets('different cuts keep separate cut notes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await createSecondCut(tester);
    await switchToCut(tester, 'default-cut-1');

    await saveCutNote(tester, 'Cut 1 note');
    expect(await currentCutNoteFromDialog(tester), 'Cut 1 note');

    await switchToCut(tester, 'cut-1');
    expect(await currentCutNoteFromDialog(tester), '');

    await saveCutNote(tester, 'Cut 2 note');
    expect(await currentCutNoteFromDialog(tester), 'Cut 2 note');

    await switchToCut(tester, 'default-cut-1');
    expect(await currentCutNoteFromDialog(tester), 'Cut 1 note');
  });

  testWidgets('undo and redo update the correct cut note', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await createSecondCut(tester);
    await switchToCut(tester, 'default-cut-1');

    await saveCutNote(tester, 'Cut 1 note');

    await switchToCut(tester, 'cut-1');
    await saveCutNote(tester, 'Cut 2 old note');
    await saveCutNote(tester, 'Cut 2 new note');
    expect(await currentCutNoteFromDialog(tester), 'Cut 2 new note');
    await expectActiveCutName(tester, '2');
    expect(await activeCutIdOf(tester), const CutId('cut-1'));

    await tapUndoButton(tester);

    expect(await currentCutNoteFromDialog(tester), 'Cut 2 old note');
    await expectActiveCutName(tester, '2');
    expect(await activeCutIdOf(tester), const CutId('cut-1'));

    await switchToCut(tester, 'default-cut-1');
    expect(await currentCutNoteFromDialog(tester), 'Cut 1 note');

    await switchToCut(tester, 'cut-1');
    await tapRedoButton(tester);

    expect(await currentCutNoteFromDialog(tester), 'Cut 2 new note');
    await expectActiveCutName(tester, '2');
    expect(await activeCutIdOf(tester), const CutId('cut-1'));

    await switchToCut(tester, 'default-cut-1');
    expect(await currentCutNoteFromDialog(tester), 'Cut 1 note');
  });

  testWidgets('edit cut note button opens dialog with current note', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await saveCutNote(tester, 'Old note');
    await openCutNoteDialog(tester);

    expect(find.text('Edit cut note'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('cut-note-text-field')),
      findsOneWidget,
    );
    expect(cutNoteFieldText(tester), 'Old note');
    expect(
      find.byKey(const ValueKey<String>('save-cut-note-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cancel-cut-note-button')),
      findsOneWidget,
    );

    await tapCutNoteCancelButton(tester);
  });

  testWidgets(
    'saving cut note supports undo and redo without changing active cut',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      await saveCutNote(tester, 'Old note');
      expect(await currentCutNoteFromDialog(tester), 'Old note');
      await expectActiveCutName(tester, '1');
      expect(await activeCutIdOf(tester), const CutId('default-cut-1'));

      await saveCutNote(tester, 'New note');

      expect(find.text('Edit cut note'), findsNothing);
      expect(await currentCutNoteFromDialog(tester), 'New note');
      await expectActiveCutName(tester, '1');
      expect(await activeCutIdOf(tester), const CutId('default-cut-1'));

      await tapUndoButton(tester);

      expect(await currentCutNoteFromDialog(tester), 'Old note');
      await expectActiveCutName(tester, '1');
      expect(await activeCutIdOf(tester), const CutId('default-cut-1'));

      await tapRedoButton(tester);

      expect(await currentCutNoteFromDialog(tester), 'New note');
      await expectActiveCutName(tester, '1');
      expect(await activeCutIdOf(tester), const CutId('default-cut-1'));
    },
  );

  testWidgets(
    'canceling cut note dialog does not change note or create history',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      await openCutNoteDialog(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('cut-note-text-field')),
        'Canceled note',
      );
      await tapCutNoteCancelButton(tester);

      expect(find.text('Edit cut note'), findsNothing);
      expect(await currentCutNoteFromDialog(tester), '');
      await expectActiveCutName(tester, '1');
      expect(
        await isActionButtonEnabled(
          tester,
          const ValueKey<String>('undo-button'),
        ),
        isFalse,
      );
    },
  );

  testWidgets('saving unchanged cut note skips history entry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await openCutNoteDialog(tester);
    expect(cutNoteFieldText(tester), '');
    await tapCutNoteSaveButton(tester);

    expect(find.text('Edit cut note'), findsNothing);
    expect(await currentCutNoteFromDialog(tester), '');
    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('undo-button'),
      ),
      isFalse,
    );
    await expectActiveCutName(tester, '1');
  });

  testWidgets('opens and cancels rename cut dialog without mutation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await tapCutCommandButton(
      tester,
      const ValueKey<String>('rename-cut-button'),
    );

    expect(
      find.byKey(const ValueKey<String>('rename-cut-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('rename-cut-text-field')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('rename-cut-text-field')),
          )
          .controller
          ?.text,
      '1',
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-cut-text-field')),
      'Canceled Cut',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-cut-cancel-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('rename-cut-dialog')),
      findsNothing,
    );
    await expectCutName(tester, 'default-cut-1', '1');
    await expectCutsNamed(tester, 'Canceled Cut', 0);
    await expectActiveCutName(tester, '1');
  });

  testWidgets('renames active cut and supports undo and redo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await renameActiveCut(tester, 'Scene A');

    await expectCutName(tester, 'default-cut-1', 'Scene A');
    await expectCutsNamed(tester, '1', 0);
    await expectActiveCutName(tester, 'Scene A');
    expect(await activeCutIdOf(tester), const CutId('default-cut-1'));

    await tapUndoButton(tester);

    await expectCutName(tester, 'default-cut-1', '1');
    await expectCutsNamed(tester, 'Scene A', 0);
    await expectActiveCutName(tester, '1');
    expect(await activeCutIdOf(tester), const CutId('default-cut-1'));

    await tapRedoButton(tester);

    await expectCutName(tester, 'default-cut-1', 'Scene A');
    await expectCutsNamed(tester, '1', 0);
    await expectActiveCutName(tester, 'Scene A');
    expect(await activeCutIdOf(tester), const CutId('default-cut-1'));
  });

  testWidgets('ignores empty rename cut input', (WidgetTester tester) async {
    await tester.pumpWidget(const AnicelApp());

    await renameActiveCut(tester, '   ');

    await expectCutName(tester, 'default-cut-1', '1');
    await expectActiveCutName(tester, '1');
    final undoButton = tester.appIconButton(
      find.byKey(const ValueKey<String>('undo-button')),
    );
    expect(undoButton.onPressed, isNull);
  });

  testWidgets('allows duplicate cut names without merging cuts', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await createSecondCut(tester);

    await renameActiveCut(tester, '1');

    await expectCutsNamed(tester, '1', 2);
    await expectCutExists(tester, 'default-cut-1', exists: true);
    await expectCutExists(tester, 'cut-1', exists: true);
    await expectActiveCutName(tester, '1');
    expect(find.textContaining('already'), findsNothing);
    expect(find.textContaining('duplicate'), findsNothing);
  });
}
