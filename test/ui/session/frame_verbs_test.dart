// THE PLAYHEAD STEPS ONE FRAME AND STOPS AT THE CUT'S EDGES.
//
// The frame verbs became a collaborator of the session manager on
// 2026-09-03 (Round 6 of the audit), and the adversarial check found that
// no test noticed when selectNextFrame stopped doing anything. These pins
// make the forwarders — and the verbs behind them — load-bearing.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

void main() {
  late EditorSessionManager session;
  late int lastFrame;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    lastFrame = session.activeCutOrNull!.duration - 1;
  });

  test('selectNextFrame steps the playhead one frame forward', () {
    expect(session.currentFrameIndex, 0);
    session.selectNextFrame();
    expect(session.currentFrameIndex, 1);
    session.selectNextFrame();
    expect(session.currentFrameIndex, 2);
  });

  test('selectNextFrame stops at the cut\'s last frame', () {
    session.selectFrameIndex(lastFrame);
    session.selectNextFrame();
    expect(session.currentFrameIndex, lastFrame);
  });

  test('selectPreviousFrame steps back and stops at the first frame', () {
    session.selectFrameIndex(2);
    session.selectPreviousFrame();
    expect(session.currentFrameIndex, 1);
    session.selectPreviousFrame();
    expect(session.currentFrameIndex, 0);
    session.selectPreviousFrame();
    expect(session.currentFrameIndex, 0);
  });
}
