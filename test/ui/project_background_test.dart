import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// R10-⑥: the project background — model round trip and the session's
/// one-undo setter.
void main() {
  const black = ProjectBackground.color(0xFF000000);

  test('json omits the default and round-trips colour, alpha and none', () {
    final project = createDefaultProject();
    expect(project.background, ProjectBackground.defaultBackground);
    expect(project.toJson().containsKey('background'), isFalse);

    ProjectBackground roundTrip(ProjectBackground background) =>
        ProjectBackground.fromJson(
          project.copyWith(background: background).toJson()['background']
              as Map<String, dynamic>,
        );

    expect(roundTrip(black), black);

    const absent = ProjectBackground.color(0x00FFFFFF, none: true);
    final restored = roundTrip(absent);
    expect(restored.none, isTrue);
    expect(
      restored.argb,
      0x00FFFFFF,
      reason: 'alpha 0 and none are two answers (F-114), and both survive',
    );
  });

  test('setProjectBackground is one undo step and no-ops when unchanged', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());

    s.projectSettings.setProjectBackground(black);
    expect(s.projectSettings.projectBackground, black);
    expect(s.canUndo, isTrue);

    // Unchanged: no extra undo entry.
    s.projectSettings.setProjectBackground(black);
    s.undo();
    expect(
      s.projectSettings.projectBackground,
      ProjectBackground.defaultBackground,
    );
    expect(s.canUndo, isFalse);

    s.redo();
    expect(s.projectSettings.projectBackground, black);

    // The same colour made absent is a change of its own, and undoes alone.
    s.projectSettings.setProjectBackground(
      const ProjectBackground.color(0xFF000000, none: true),
    );
    expect(s.projectSettings.projectBackground.none, isTrue);
    s.undo();
    expect(s.projectSettings.projectBackground, black);
  });
}
