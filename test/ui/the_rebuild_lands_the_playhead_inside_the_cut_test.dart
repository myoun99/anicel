import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// WHAT [ActiveCutControllers.rebuild] OWES ITS CALLERS.
///
/// Every caller hands it the frame index it wants KEPT — the one the
/// playhead was on before the command, or the one a run stopped at. That
/// index belongs to the cut as it was, and the cut may have got shorter
/// (a trim) or been swapped for a shorter one. `TimelineController` does
/// not clamp: it takes the index it is given and stores it, so an
/// unclamped rebuild leaves the playhead past the end of the cut it is
/// standing in.
///
/// Neither law below had an observer: `clampedFrameIndex` could be
/// replaced by its argument, and the pair could be rebuilt one at a time,
/// with every suite still green.
void main() {
  test('a rebuild handed an index past the end lands on the last frame', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final duration = session.activeCutOrNull!.duration;
    expect(duration, greaterThan(0), reason: 'fixture premise');

    session.refreshAfterCutCommand(preferredFrameIndex: duration + 50);

    expect(
      session.activeCutControllers.timelineController.currentFrameIndex,
      duration - 1,
      reason:
          'the index a caller wants kept belongs to the cut as it WAS — '
          'nothing downstream clamps it',
    );
  });

  test('the two controllers are replaced together — one fact, one write', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final layersBefore = session.activeCutControllers.layerController;
    final timelineBefore = session.activeCutControllers.timelineController;

    session.refreshAfterCutCommand();

    expect(
      session.activeCutControllers.layerController,
      isNot(same(layersBefore)),
      reason: 'a layer controller kept across a rebuild reads the old cut',
    );
    expect(
      session.activeCutControllers.timelineController,
      isNot(same(timelineBefore)),
      reason:
          'the pair is one fact — the cut being edited — so a rebuild that '
          'replaced only one would leave two answers to it',
    );
  });
}
