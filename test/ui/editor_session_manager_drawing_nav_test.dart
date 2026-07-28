import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// PEN-8 #2: drawing navigation walks BLOCKS where blocks exist and
/// falls back to ONE-FRAME steps through empty space — the plain-arrow/
/// 파라파라 unit never dead-ends.
void main() {
  EditorSessionManager sessionWithBlock() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    final cut = session.requireActiveCut;
    final layer = cut.layers.first;
    session.repository.replaceLayer(
      layer: layer.copyWith(
        frames: [
          Frame(id: const FrameId('nav-f1'), duration: 1, strokes: const []),
        ],
        timeline: {
          2: TimelineExposure.drawing(const FrameId('nav-f1'), length: 3),
        },
      ),
    );
    session.selectLayer(layer.id);
    return session;
  }

  test('next: jumps to the block start, ESCAPES past the block end, then '
      'steps frames through empty space (PEN-12 #2)', () {
    final session = sessionWithBlock();
    addTearDown(session.dispose);

    session.selectFrameIndex(0);
    session.selectNextDrawing();
    expect(session.currentFrameIndex, 2, reason: 'jumps to the block');

    // ON the last block with no next drawing: one press escapes past its
    // end — never a one-frame crawl through a long tail block.
    session.selectNextDrawing();
    expect(session.currentFrameIndex, 5, reason: 'escapes the block whole');

    // Pure empty space keeps the PEN-8 one-frame walk.
    session.selectNextDrawing();
    expect(session.currentFrameIndex, 6);

    // From INSIDE the block the escape lands past the end too.
    session.selectFrameIndex(3);
    session.selectNextDrawing();
    expect(session.currentFrameIndex, 5, reason: 'mid-block escapes whole');
  });

  test('previous: steps frames through empty space, then jumps to the '
      'block start', () {
    final session = sessionWithBlock();
    addTearDown(session.dispose);

    session.selectFrameIndex(7);
    session.selectPreviousDrawing();
    expect(session.currentFrameIndex, 2, reason: 'jumps back to the block');

    // Before the block there is no earlier drawing — empty space walks
    // one frame at a time (and clamps at 0).
    session.selectPreviousDrawing();
    expect(session.currentFrameIndex, 1);
    session.selectPreviousDrawing();
    expect(session.currentFrameIndex, 0);
    session.selectPreviousDrawing();
    expect(session.currentFrameIndex, 0, reason: 'clamped at the start');
  });
}
