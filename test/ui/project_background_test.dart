import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/dialogs/project_background_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// R10-⑥: the project background — model round trip, the session's
/// one-undo setter and the File-menu dialog.
void main() {
  test('json omits the default and round-trips color/transparent', () {
    final project = createDefaultProject();
    expect(project.background, ProjectBackground.defaultBackground);
    expect(project.toJson().containsKey('background'), isFalse);

    final black = project.copyWith(background: ProjectBackground.black);
    final restoredBlack = ProjectBackground.fromJson(
      black.toJson()['background'] as Map<String, dynamic>,
    );
    expect(restoredBlack, ProjectBackground.black);

    final transparent = project.copyWith(
      background: const ProjectBackground.transparent(),
    );
    final restoredTransparent = ProjectBackground.fromJson(
      transparent.toJson()['background'] as Map<String, dynamic>,
    );
    expect(restoredTransparent.transparent, isTrue);
    expect(
      restoredTransparent.argb,
      0xFFFFFFFF,
      reason: 'transparent bakes white in exports',
    );
  });

  test('setProjectBackground is one undo step and no-ops when unchanged', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());

    s.setProjectBackground(ProjectBackground.black);
    expect(s.projectBackground, ProjectBackground.black);
    expect(s.canUndo, isTrue);

    // Unchanged: no extra undo entry.
    s.setProjectBackground(ProjectBackground.black);
    s.undo();
    expect(s.projectBackground, ProjectBackground.defaultBackground);
    expect(s.canUndo, isFalse);

    s.redo();
    expect(s.projectBackground, ProjectBackground.black);
  });

  testWidgets('the dialog applies a preset and a custom hex color', (
    tester,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    Future<void> openDialog() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => ProjectBackgroundDialog(session: s),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await openDialog();
    await tester.tap(find.byKey(const ValueKey<String>('background-black')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('background-apply-button')),
    );
    await tester.pumpAndSettle();
    expect(s.projectBackground, ProjectBackground.black);

    await openDialog();
    await tester.tap(find.byKey(const ValueKey<String>('background-custom')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('background-custom-hex')),
      '3366CC',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('background-apply-button')),
    );
    await tester.pumpAndSettle();
    expect(s.projectBackground, ProjectBackground.color(0xFF3366CC));

    await openDialog();
    await tester.tap(
      find.byKey(const ValueKey<String>('background-transparent')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('background-apply-button')),
    );
    await tester.pumpAndSettle();
    expect(s.projectBackground.transparent, isTrue);
  });
}
