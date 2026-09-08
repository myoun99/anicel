import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/session/project_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// R26 #32: the project frame rate is ONE project-wide axis, changed in
/// one undo step.
/// The collaborator that owns the rate — named so `tool/mutation_run.dart`
/// has a suite to run for it.
ProjectSettings projectSettingsOf(EditorSessionManager session) =>
    session.projectSettings;

void main() {
  test('setProjectFps writes the project rate, undoes in one step, and '
      'no-ops on the same value', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final settings = projectSettingsOf(session);
    final start = settings.projectFps;

    settings.setProjectFps(12);
    expect(settings.projectFps, 12);
    expect(session.repository.requireProject().fps, 12);

    session.undo();
    expect(settings.projectFps, start, reason: 'one undo restores the rate');

    // A no-op write must not push an undo entry.
    settings.setProjectFps(start);
    expect(session.canUndo, isFalse);
    // Nor an invalid one.
    settings.setProjectFps(0);
    expect(settings.projectFps, start);
    expect(session.canUndo, isFalse);
  });
}
