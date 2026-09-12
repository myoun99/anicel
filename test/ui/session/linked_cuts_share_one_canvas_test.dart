// A 겸용 GROUP SHARES ONE CANVAS SIZE — from the moment it becomes one.
//
// 🗣️유저 2026-09-12: 「링크컷인데 컷 하나 캔버스크기 바꾸면 다른 링크된컷도
// 바뀌어야 하는데 안바뀌거든? 그러니 이부분 구조/근본적으로 법 하나로
// 만들어서 해결해줘.」
//
// ⚠️THE RESIZE WAS NEVER THE BROKEN HALF — it already walks the 겸용
// siblings (`linkedCutSiblings`), and the first two cases below are the
// measurement that said so. What was missing is the OTHER end: a convert
// left the pair at whatever sizes they happened to have, and the dialog
// merely said the origin's size would win. A pair that starts out of step
// stays out of step, which is what reads as "the other cut does not
// change".
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

void main() {
  CanvasSize sizeOf(EditorSessionManager s, CutId id) =>
      s.cutById(id)!.canvasSize;

  test('a cut made 겸용 by CREATION shares every later resize, both ways', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final source = s.requireActiveCut.id;
    s.cutVerbs.createLinkedCutFromActiveCut();
    final linked = s.requireActiveCut.id;

    s.selectCut(source);
    s.cutVerbs.resizeActiveCutCanvas(const CanvasSize(width: 800, height: 600));
    expect(sizeOf(s, source), const CanvasSize(width: 800, height: 600));
    expect(
      sizeOf(s, linked),
      const CanvasSize(width: 800, height: 600),
      reason: 'the sibling follows the resize',
    );

    s.selectCut(linked);
    s.cutVerbs.resizeActiveCutCanvas(const CanvasSize(width: 640, height: 480));
    expect(
      sizeOf(s, source),
      const CanvasSize(width: 640, height: 480),
      reason: 'and it follows the other way too — neither cut is the master',
    );
  });

  test('CONVERTING a cut to 겸용 brings it to the origin\'s size — the rule '
      'the dialog states is the rule the code keeps', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    // Two plain cuts at different sizes: the target is the one that will
    // be converted, so it is the one that has to move.
    final origin = s.requireActiveCut.id;
    s.cutVerbs.duplicateActiveCut();
    final target = s.requireActiveCut.id;
    s.selectCut(target);
    s.cutVerbs.resizeActiveCutCanvas(
      const CanvasSize(width: 1920, height: 1080),
    );
    final originSize = sizeOf(s, origin);
    expect(
      sizeOf(s, target),
      isNot(originSize),
      reason: 'LIVENESS — the pair must really start out of step',
    );

    s.selectCut(origin);
    final candidates = s.cutVerbs.convertToLinkedCutCandidates;
    expect(
      candidates.map((cut) => cut.id),
      contains(target),
      reason: 'LIVENESS — the convert must really be on offer',
    );
    s.cutVerbs.convertActiveCutToLinked(target);

    expect(
      sizeOf(s, target),
      originSize,
      reason: '⛔the pair is one canvas from the moment it is one group — '
          'starting out of step is what made a later resize look like it '
          'did nothing',
    );

    // ...and from there the shared resize behaves as it always did.
    s.selectCut(target);
    s.cutVerbs.resizeActiveCutCanvas(const CanvasSize(width: 512, height: 512));
    expect(sizeOf(s, origin), const CanvasSize(width: 512, height: 512));
  });

  test('the conversion is ONE undo step, size included', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final origin = s.requireActiveCut.id;
    s.cutVerbs.duplicateActiveCut();
    final target = s.requireActiveCut.id;
    s.selectCut(target);
    s.cutVerbs.resizeActiveCutCanvas(
      const CanvasSize(width: 1920, height: 1080),
    );
    final targetSizeBefore = sizeOf(s, target);

    s.selectCut(origin);
    s.cutVerbs.convertActiveCutToLinked(target);
    expect(sizeOf(s, target), sizeOf(s, origin));

    s.undo();
    expect(
      sizeOf(s, target),
      targetSizeBefore,
      reason: 'one undo puts the size back with the link — the resize and '
          'the convert are one step, not two',
    );
  });
}
