import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// R10-⑥: the project background — model round trip and the session's
/// one-undo setter.
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
      0x00FFFFFF,
      reason:
          'transparent IS alpha-0 paper now (R3b) — the alpha is real, '
          'on screen and in exports alike',
    );
  });

  test('setProjectBackground is one undo step and no-ops when unchanged', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());

    s.projectSettings.setProjectBackground(ProjectBackground.black);
    expect(s.projectSettings.projectBackground, ProjectBackground.black);
    expect(s.canUndo, isTrue);

    // Unchanged: no extra undo entry.
    s.projectSettings.setProjectBackground(ProjectBackground.black);
    s.undo();
    expect(s.projectSettings.projectBackground, ProjectBackground.defaultBackground);
    expect(s.canUndo, isFalse);

    s.redo();
    expect(s.projectSettings.projectBackground, ProjectBackground.black);
  });
}
