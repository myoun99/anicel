import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project.dart';
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

  test('🚨the outer planes: none takes a plane away, and a pick — even of '
      'the kept colour — brings it back in the same undo step (F-114)', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    Project project() => s.repository.requireProject();
    final keptBackdrop = project().backdropArgb;
    final keptPasteboard = project().pasteboardArgb;

    s.projectSettings.setProjectBackdropNone();
    s.projectSettings.setPasteboardNone();
    expect(project().backdropNone, isTrue);
    expect(project().pasteboardNone, isTrue);
    expect(project().backdropArgb, keptBackdrop, reason: 'the colour stays');

    // The kept colour itself: nothing about the argb changes, and the plane
    // still has to come back.
    s.projectSettings.setProjectBackdrop(keptBackdrop);
    s.projectSettings.setPasteboardColor(keptPasteboard);
    expect(project().backdropNone, isFalse);
    expect(project().pasteboardNone, isFalse);

    s.undo();
    expect(project().pasteboardNone, isTrue, reason: 'one step, undone alone');
    expect(project().backdropNone, isFalse);
  });
}
