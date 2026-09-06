import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/cut/cut_note_dialog.dart';
import 'package:anicel/src/ui/dialogs/delete_layer_dialog.dart';
import 'package:anicel/src/ui/dialogs/frame_name_conflict_dialog.dart';
import 'package:anicel/src/ui/dialogs/rename_cut_dialog.dart';
import 'package:anicel/src/ui/dialogs/rename_frame_dialog.dart';
import 'package:anicel/src/ui/dialogs/rename_layer_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🚨WHAT EACH DIALOG POPS, AND WHICH ONES REFUSE AN EMPTY VALUE.
///
/// Nothing named these (the audit's untested-file pass, 2026-09-05), and
/// the empty-value rule is not the same for all of them — it is a decision
/// per dialog, written in each one's doc:
///
/// * a CUT's name IS its number on every sheet and storyboard page, so an
///   empty one is refused inline;
/// * a LAYER's name is refused for the same reason;
/// * a FRAME's name is the sheet's own text on an SE row, so CLEARING it
///   is a real edit and empty is allowed;
/// * a cut NOTE clears the same way.
///
/// A test that treated them alike would let one drift into the other's
/// rule without anything going red.
void main() {
  group('the rename dialogs', () {
    testWidgets('a cut rename pops the TRIMMED name', (tester) async {
      Object? popped;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showDialog<Object?>(
                      context: context,
                      builder: (_) => const RenameCutDialog(initialName: 'A1'),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('rename-cut-text-field')),
        '  C12  ',
      );
      await tester.tap(find.text(AppText.strings.commonRename));
      await tester.pumpAndSettle();

      expect(popped, 'C12');
    });

    testWidgets('⛔a cut rename REFUSES an empty name inline — the cut\'s '
        'name is its number on every page that prints it', (tester) async {
      Object? popped;
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showDialog<Object?>(
                      context: context,
                      builder: (_) => const RenameCutDialog(initialName: 'A1'),
                    );
                    closed = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('rename-cut-text-field')),
        '   ',
      );
      await tester.tap(find.text(AppText.strings.commonRename));
      await tester.pumpAndSettle();

      expect(closed, isFalse, reason: 'it stayed up');
      expect(popped, isNull);
      expect(find.text(AppText.strings.renameCutEmpty), findsOneWidget);
    });

    testWidgets('⛔a layer rename refuses an empty name too', (tester) async {
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await showDialog<Object?>(
                      context: context,
                      builder: (_) => const RenameLayerDialog(initialName: 'A'),
                    );
                    closed = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('rename-layer-text-field')),
        '',
      );
      await tester.tap(find.text(AppText.strings.commonRename));
      await tester.pumpAndSettle();

      expect(closed, isFalse);
      expect(find.text(AppText.strings.renameLayerEmpty), findsOneWidget);
    });

    testWidgets('🚨a FRAME rename ALLOWS empty — the frame name is the '
        'sheet\'s own text on an SE row, so clearing a cell is a real edit', (
      tester,
    ) async {
      Object? popped;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showDialog<Object?>(
                      context: context,
                      builder: (_) => const RenameFrameDialog(initialName: 'a'),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('rename-frame-text-field')),
        '',
      );
      await tester.tap(find.text(AppText.strings.commonRename));
      await tester.pumpAndSettle();

      expect(popped, '');
    });

    testWidgets('an SE row reuses the frame dialog with SHEET wording', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RenameFrameDialog(
              initialName: 'ドア',
              title: 'SE name',
              fieldLabel: 'Dialogue',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SE name'), findsOneWidget);
      expect(find.text(AppText.strings.renameFrameTitle), findsNothing);
    });

    testWidgets('cancel pops NOTHING, whatever was typed', (tester) async {
      Object? popped;
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showDialog<Object?>(
                      context: context,
                      builder: (_) => const RenameCutDialog(initialName: 'A1'),
                    );
                    closed = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('rename-cut-text-field')),
        'C99',
      );
      await tester.tap(find.text(AppText.strings.commonCancel));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(popped, isNull);
    });
  });

  group('the cut note', () {
    testWidgets('🚨an EMPTY note is popped, not refused — clearing the note '
        'is a real edit', (tester) async {
      Object? popped;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showDialog<Object?>(
                      context: context,
                      builder: (_) =>
                          const CutNoteDialog(initialNote: 'old note'),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('cut-note-text-field')),
        '   ',
      );
      await tester.tap(find.text(AppText.strings.commonSave));
      await tester.pumpAndSettle();

      expect(popped, '');
    });
  });

  group('the confirm dialogs', () {
    testWidgets('deleting a layer NAMES it in the message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DeleteLayerDialog(layerName: 'B셀')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('B셀'), findsOneWidget);
    });

    testWidgets('deleting a layer pops TRUE only on the delete button', (
      tester,
    ) async {
      Object? popped;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showDialog<Object?>(
                      context: context,
                      builder: (_) => const DeleteLayerDialog(layerName: 'B'),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppText.strings.commonCancel));
      await tester.pumpAndSettle();
      expect(popped, isNot(true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppText.strings.commonDelete));
      await tester.pumpAndSettle();
      expect(popped, isTrue);
    });

    testWidgets('the frame-name conflict pops TRUE to LINK — identical '
        'names share the same material', (tester) async {
      Object? popped;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showDialog<Object?>(
                      context: context,
                      builder: (_) => const FrameNameConflictDialog(),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppText.strings.commonLink));
      await tester.pumpAndSettle();

      expect(popped, isTrue);
    });
  });

  /// 🚨THE FOUR KEYS ARE ONE NAME — the prompt family's half of the rule
  /// [confirmDialogKeys] already owns for confirms: `<name>-dialog`,
  /// `-text-field`, `-cancel-button`, `-ok-button`. A window renamed
  /// without its buttons leaves a test finding the window and not its
  /// confirm, which reads as "the button is missing" rather than "the key
  /// drifted".
  ///
  /// ⚠️Two windows are off that convention and keep their own keys: a cut
  /// rename accepts through `-confirm-button` ([confirmDialogKeys]), and
  /// the cut note's buttons are named after the verb rather than the
  /// window. They are listed HERE, spelled out, so that staying off the
  /// convention is a decision the file records rather than a drift.
  group('the keys a prompt window wears', () {
    Future<void> pump(WidgetTester tester, Widget dialog) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: dialog)));
      await tester.pump();
    }

    void expectKeys(WidgetTester tester, List<String> keys) {
      for (final key in keys) {
        expect(
          find.byKey(ValueKey<String>(key)),
          findsOneWidget,
          reason: 'key $key',
        );
      }
    }

    testWidgets('a layer rename: four keys from "rename-layer"', (
      tester,
    ) async {
      await pump(tester, const RenameLayerDialog(initialName: 'A'));
      expectKeys(tester, [
        'rename-layer-dialog',
        'rename-layer-text-field',
        'rename-layer-cancel-button',
        'rename-layer-ok-button',
      ]);
    });

    testWidgets('a frame rename: four keys from "rename-frame"', (
      tester,
    ) async {
      await pump(tester, const RenameFrameDialog(initialName: 'a'));
      expectKeys(tester, [
        'rename-frame-dialog',
        'rename-frame-text-field',
        'rename-frame-cancel-button',
        'rename-frame-ok-button',
      ]);
    });

    testWidgets('a cut rename accepts through -confirm-button, not '
        '-ok-button', (tester) async {
      await pump(tester, const RenameCutDialog(initialName: 'A1'));
      expectKeys(tester, [
        'rename-cut-dialog',
        'rename-cut-text-field',
        'rename-cut-cancel-button',
        'rename-cut-confirm-button',
      ]);
      expect(
        find.byKey(const ValueKey<String>('rename-cut-ok-button')),
        findsNothing,
      );
    });

    testWidgets('the cut note names its buttons after the verb', (
      tester,
    ) async {
      await pump(tester, const CutNoteDialog(initialNote: 'n'));
      expectKeys(tester, [
        'cut-note-dialog',
        'cut-note-text-field',
        'cancel-cut-note-button',
        'save-cut-note-button',
      ]);
    });
  });
}
