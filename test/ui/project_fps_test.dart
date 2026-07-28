import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// R26 #32: the project frame rate is ONE project-wide axis, changed in
/// one undo step.
void main() {
  test('setProjectFps writes the project rate, undoes in one step, and '
      'no-ops on the same value', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final start = session.projectFps;

    session.setProjectFps(12);
    expect(session.projectFps, 12);
    expect(session.repository.requireProject().fps, 12);

    session.undo();
    expect(session.projectFps, start, reason: 'one undo restores the rate');

    // A no-op write must not push an undo entry.
    session.setProjectFps(start);
    expect(session.canUndo, isFalse);
    // Nor an invalid one.
    session.setProjectFps(0);
    expect(session.projectFps, start);
    expect(session.canUndo, isFalse);
  });
}
