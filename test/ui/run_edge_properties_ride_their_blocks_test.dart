import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../helpers/run_edge_fixtures.dart';

/// 🚨F-134 (유저 2026-09-14), driven through the verbs the user used:
///
/// - 「프레임 복사/붙혀넣기하면 붙여넣어진 프레임의 +버튼이나 성질버튼이 없음」
///   — the chrome half is pinned in `timeline_run_end_handles_test.dart`;
/// - 「D의 1을 복사하고 10쯤의 인덱스에서 붙혀넣기하면 두번째 스샷처럼 1 뒤에
///   2가 생김. 복사할 대상의 뒤 프레임의 뒷성질이 hold인 상태에서만 발생」;
/// - 「프레임 생성하고 거기서 이름바꿔서 링크프레임 작동시키면 성질 사라짐」.
///
/// A run edge property is the BLOCK's (`TimelineRunEdgeMark`): it rides every
/// move, copy and relink the way a memo does, and a ghost is never material
/// a splice can cut a block out of.
void main() {
  late EditorSessionManager session;
  late LayerId rowId;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    rowId = session.activeLayer!.id;
  });

  Layer row() => session.layers.firstWhere((layer) => layer.id == rowId);

  void drawAt(int frame) {
    session.selectFrameIndex(frame);
    session.createDrawingAtCurrentFrame();
  }

  void holdEndOf(int blockStart) => session.rangeMove.setRunEdgeBehavior(
    layerId: rowId,
    blockStartIndex: blockStart,
    side: TimelineRunEdgeSide.end,
    mode: TimelineRunEdgeMode.hold,
  );

  test('a linked paste INSIDE another run\'s hold leaves no real block '
      'behind it', () {
    expect(
      session.requireActiveCut.duration,
      greaterThan(12),
      reason: 'LIVENESS — the cut has room for the scene',
    );
    // The screenshot's row D: 「1」 at 0, 「2」 at 3 holding to the cut end.
    drawAt(0);
    drawAt(3);
    holdEndOf(3);
    expect(row().timeline[4]!.ghostOf, endHoldGhost, reason: 'LIVENESS');

    session.selectFrameIndex(0);
    session.clipboard.copyFrameAtCurrentFrame();
    session.selectFrameIndex(9);
    session.clipboard.pasteLinkedFrameAtCurrentFrame();

    final after = row();
    expect(
      after.timeline[9]?.frameId,
      after.timeline[0]!.frameId,
      reason: 'LIVENESS — the linked paste landed at 9',
    );
    expect(
      [
        for (final entry in after.timeline.entries)
          if (!entry.value.ghost) entry.key,
      ],
      [0, 3, 9],
      reason: '⛔「1 뒤에 2가 생김」: the hold past the paste point must not '
          'come back as an authored block',
    );
    expect(after.timeline[4]!.length, 5, reason: 'the hold stops at the 1');
    expect(after.timeline[10], isNull, reason: 'the pasted 1 holds nothing');
  });

  test('a copy of held cells takes no block out of the hold — a ghost is not '
      'material', () {
    drawAt(0);
    holdEndOf(0);
    expect(row().timeline[1]!.ghostOf, endHoldGhost, reason: 'LIVENESS');

    final timeline = session.activeCutControllers.timelineController;
    final clip = timeline.copyRunForLayer(layerId: rowId, index: 3, count: 3);

    expect(clip.length, 3, reason: 'LIVENESS — the range keeps its length');
    expect(
      clip.exposures,
      isEmpty,
      reason: '⛔the split that made 「2」 after the paste made a real block '
          'of the hold here too',
    );
  });

  test('joining a held block to another drawing by name keeps its hold', () {
    drawAt(0);
    expect(session.frameVerbs.renameSelectedFrame('1'), isNull);
    final one = row().timeline[0]!.frameId;
    drawAt(5);
    holdEndOf(5);
    expect(row().timeline[6]!.ghostOf, endHoldGhost, reason: 'LIVENESS');

    session.selectFrameIndex(5);
    final conflict = session.frameVerbs.renameSelectedFrame('1');
    expect(conflict, one, reason: 'LIVENESS — the name offers the join');
    session.frameVerbs.linkSelectedFrame(conflict!);

    final after = row();
    expect(after.timeline[5]!.frameId, one, reason: 'LIVENESS — joined');
    expect(after.timeline[5]!.endEdge, holdMark, reason: '⛔「성질 사라짐」');
    expect(after.timeline[6]!.ghostOf, endHoldGhost);
    expect(after.timeline[6]!.frameId, one);
    expect(
      after.timeline[1],
      isNull,
      reason: 'the OTHER block showing 「1」 did not take the hold',
    );
  });

  test('a copied block carries its property the way it carries its memo', () {
    drawAt(0);
    holdEndOf(0);
    session.selectFrameIndex(0);
    session.clipboard.copyFrameAtCurrentFrame();
    session.selectFrameIndex(8);
    session.clipboard.pasteIndependentFrameAtCurrentFrame();

    final after = row();
    expect(after.timeline[8]!.ghost, isFalse, reason: 'LIVENESS — pasted');
    expect(after.timeline[8]!.endEdge, holdMark);
    expect(after.timeline[9]!.ghostOf, endHoldGhost);
    expect(after.timeline[1]!.length, 7, reason: 'the original holds to 8');
  });
}
