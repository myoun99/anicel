// THE PLAYHEAD STEPS ONE FRAME, AND FRAME 0 IS THE FLOOR.
//
// The frame verbs became a collaborator of the session manager on
// 2026-09-03 (Round 6 of the audit), and the adversarial check found that
// no test noticed when selectNextFrame stopped doing anything. These pins
// make the forwarders — and the verbs behind them — load-bearing.
//
// ↩️**THE CEILING IS GONE (F-148, 2026-09-17).** The header said 「STOPS AT
// THE CUT'S EDGES」 and a pin here held the forward step to
// `cut.duration - 1` — which is exactly what 유저 reported as a bug:
// 「컨트롤+화살표로 1프레임 이동이 **안먹힐때가 있는듯**. 로직 싹 점검하고
// **법 통일할거 통일해서 근본/구조적해결**」. The frame axis has no right
// edge (the timeline papers past the cut and draws it dimmed), so only the
// LEFT edge is an edge. 🪦That pin is not re-homed as its opposite here:
// `the_one_frame_step_lands_where_the_flip_lands_test` measures the new law
// on every row and in a gap, which is more than this file could say.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
  });

  test('selectNextFrame steps the playhead one frame forward', () {
    expect(session.currentFrameIndex, 0);
    session.frameVerbs.selectNextFrame();
    expect(session.currentFrameIndex, 1);
    session.frameVerbs.selectNextFrame();
    expect(session.currentFrameIndex, 2);
  });

  test('selectPreviousFrame steps back and stops at the first frame', () {
    session.selectFrameIndex(2);
    session.frameVerbs.selectPreviousFrame();
    expect(session.currentFrameIndex, 1);
    session.frameVerbs.selectPreviousFrame();
    expect(session.currentFrameIndex, 0);
    session.frameVerbs.selectPreviousFrame();
    expect(session.currentFrameIndex, 0);
  });
}
