import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The active cut's controllers are replaced in ONE place
/// (`ActiveCutControllers.rebuild`), and that place is also where the
/// editing frame cursor learns the frame they landed on — the cursor layer,
/// the frame counter and the canvas scrub preview all follow that notifier
/// rather than the session.
///
/// 🧪Pinned because a mutant that handed the controllers a cursor of their
/// own survived every suite: nothing checked that a rebuild's landing
/// reaches the session's cursor (ARCH-session-state, the sixteenth family).
void main() {
  test('a rebuild publishes the frame it landed on to the frame cursor', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    expect(session.editingFrameCursor.value, 0, reason: '⛔premise');

    session.refreshAfterCutCommand(preferredFrameIndex: 3);

    expect(
      session.currentFrameIndex,
      3,
      reason: '⛔premise: the controllers landed on frame 3',
    );
    expect(session.editingFrameCursor.value, 3);
  });
}
