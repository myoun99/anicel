import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// ADD FRAME inside a block DIVIDES it (user's rule 2026-07-27):
/// `1-----` pressed on the third frame reads `1--o--` afterwards, the new
/// drawing taking over the rest of the hold. The frames do not move — the
/// division does.
void main() {
  EditorSessionManager sessionWithHeldBlock({int length = 6}) {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final layerId = session.activeLayerId!;
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    // Hold it out to [0, length).
    session.exposureVerbs.setCommaForSelectionOrCurrent(length);
    expect(
      session.layers.firstWhere((layer) => layer.id == layerId).timeline.keys,
      [0],
    );
    return session;
  }

  SplayTreeMap<int, TimelineExposure> timelineOf(
    EditorSessionManager session,
  ) => session.layers.firstWhere((l) => l.id == session.activeLayerId).timeline;

  test('pressing inside a held block divides it, the new drawing taking '
      'the rest of the hold', () {
    final session = sessionWithHeldBlock();

    session.selectFrameIndex(2);
    expect(session.frameVerbs.canCreateDrawingAtCurrentFrame, isTrue);
    session.createDrawingAtCurrentFrame();

    final timeline = timelineOf(session);
    expect(timeline.keys, [0, 2]);
    expect(timeline[0]!.length, 2);
    expect(timeline[2]!.length, 4);
    // A NEW drawing, not the old one re-exposed: the divide button that
    // duplicates the picture is a separate verb.
    expect(timeline[2]!.frameId, isNot(timeline[0]!.frameId));
  });

  group('F-151: at a HEAD, add pushes what is glued and takes the cell', () {
    // 🗣️유저 2026-09-16: 「프레임 블록의 헤드에 서있을때 프레임 추가버튼은
    // 해당 블록 뒤로 1칸 밀어내고(붙어있는거만 밀어냄. 로직 공용화되있는거?
    // 법 통일해서 사용) 그 자리에 생성. 그러니 추가버튼 사용가능하도록」.
    //
    // ↩️The rule before this read 「the block START refuses: there is
    // nothing there to divide」 — true of a DIVIDE, and the head is exactly
    // where 유저 wanted the button to do something else.

    /// A [0,6) · B GLUED at [6,8) · a two-cell gap · C [10,12).
    EditorSessionManager threeBlocks() {
      final session = sessionWithHeldBlock();
      session.selectFrameIndex(6);
      session.createDrawingAtCurrentFrame();
      session.exposureVerbs.setCommaForSelectionOrCurrent(2);
      session.selectFrameIndex(10);
      session.createDrawingAtCurrentFrame();
      session.exposureVerbs.setCommaForSelectionOrCurrent(2);
      final timeline = timelineOf(session);
      expect(
        {for (final e in timeline.entries) e.key: e.value.length},
        {0: 6, 6: 2, 10: 2},
        reason: '⛔전제: A, B glued to it, a gap, then C',
      );
      return session;
    }

    test('🚨pressing A\'s head: A and B (glued) move back one cell, C (past '
        'a gap) stays, and the new drawing takes the head', () {
      final session = threeBlocks();
      final a = timelineOf(session)[0]!.frameId;
      final c = timelineOf(session)[10]!.frameId;

      session.selectFrameIndex(0);
      expect(session.frameVerbs.canCreateDrawingAtCurrentFrame, isTrue);
      session.createDrawingAtCurrentFrame();

      final timeline = timelineOf(session);
      expect(
        {for (final e in timeline.entries) e.key: e.value.length},
        {0: 1, 1: 6, 7: 2, 10: 2},
        reason: '유저: 「붙어있는거만 밀어냄」 — the gap before C absorbed '
            'the push',
      );
      expect(timeline[1]!.frameId, a, reason: 'A moved, it was not redrawn');
      expect(timeline[10]!.frameId, c, reason: 'C never moved');
      expect(
        timeline[0]!.frameId,
        isNot(anyOf(a, c)),
        reason: 'a NEW drawing at the head',
      );
    });

    test('a head in the middle pushes only what follows it', () {
      final session = threeBlocks();

      session.selectFrameIndex(6);
      expect(session.frameVerbs.canCreateDrawingAtCurrentFrame, isTrue);
      session.createDrawingAtCurrentFrame();

      expect(
        {for (final e in timelineOf(session).entries) e.key: e.value.length},
        {0: 6, 6: 1, 7: 2, 10: 2},
        reason: 'A before the press is untouched; B moved; C still past '
            'its gap',
      );
    });

    test('⛔the CONTROL: a push that reaches the next block pushes it too — '
        'the gap only absorbs what fits', () {
      // Three presses at the head: the first two eat C's two-cell gap
      // (after the second, B ends exactly where C starts — glued), so the
      // third carries C along. A gap absorbs only what fits in it.
      final session = threeBlocks();
      for (var press = 0; press < 3; press += 1) {
        session.selectFrameIndex(0);
        session.createDrawingAtCurrentFrame();
      }

      final starts = timelineOf(session).keys.toList();
      expect(starts.last, 11, reason: 'C was finally pushed by one');
    });

    test('the head push is ONE undo step', () {
      final session = threeBlocks();
      session.selectFrameIndex(0);
      session.createDrawingAtCurrentFrame();
      session.undo();

      expect(
        {for (final e in timelineOf(session).entries) e.key: e.value.length},
        {0: 6, 6: 2, 10: 2},
      );
    });

    test('dots ride inside the block they time', () {
      final session = threeBlocks();
      session.selectFrameIndex(3);
      session.layerMarks.toggleMarkAtCurrentFrame();
      expect(timelineOf(session)[0]!.breakdownOffsets, [3]);

      session.selectFrameIndex(0);
      session.createDrawingAtCurrentFrame();

      expect(
        timelineOf(session)[1]!.breakdownOffsets,
        [3],
        reason: 'the dot still marks A\'s fourth frame, now frame 4',
      );
    });

    test('⚠️a row that covers its cut EDGE TO EDGE still refuses at every '
        'head — there is nowhere to push to', () {
      // 유저 named the storyboard's FIRST head; the reason (the row lives
      // inside its cut, every panel glued to the next) holds for every
      // head, so every head refuses. Reported on the card.
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.layerStack.addLayerOfKind(LayerKind.storyboard);
      session.selectFrameIndex(3);
      session.createDrawingAtCurrentFrame();
      expect(
        timelineOf(session).keys,
        [0, 3],
        reason: '⛔전제: two panels',
      );

      for (final head in [0, 3]) {
        session.selectFrameIndex(head);
        expect(
          session.frameVerbs.canCreateDrawingAtCurrentFrame,
          isFalse,
          reason: 'storyboard head $head',
        );
      }
      session.selectFrameIndex(1);
      expect(
        session.frameVerbs.canCreateDrawingAtCurrentFrame,
        isTrue,
        reason: 'inside a panel it still divides',
      );
    });
  });

  test('an empty cell still just creates, as it always did', () {
    final session = sessionWithHeldBlock(length: 2);

    session.selectFrameIndex(4);
    expect(session.frameVerbs.canCreateDrawingAtCurrentFrame, isTrue);
    session.createDrawingAtCurrentFrame();

    final timeline = timelineOf(session);
    expect(timeline.keys, [0, 4]);
    expect(timeline[0]!.length, 2);
    expect(timeline[4]!.length, 1);
  });

  test('dividing twice keeps dividing — each press splits the block it '
      'lands in, not the first one', () {
    final session = sessionWithHeldBlock();

    session.selectFrameIndex(2);
    session.createDrawingAtCurrentFrame();
    session.selectFrameIndex(4);
    session.createDrawingAtCurrentFrame();

    final timeline = timelineOf(session);
    expect(timeline.keys, [0, 2, 4]);
    expect(timeline[0]!.length, 2);
    expect(timeline[2]!.length, 2);
    expect(timeline[4]!.length, 2);
  });

  test('the division is ONE undo step', () {
    final session = sessionWithHeldBlock();

    session.selectFrameIndex(2);
    session.createDrawingAtCurrentFrame();
    session.undo();

    final timeline = timelineOf(session);
    expect(timeline.keys, [0]);
    expect(timeline[0]!.length, 6);
  });

  test('inbetween dots past the division travel with the half they mark', () {
    final session = sessionWithHeldBlock();
    // Dots at offsets 1 and 4 of the [0,6) block.
    session.selectFrameIndex(1);
    session.layerMarks.toggleMarkAtCurrentFrame();
    session.selectFrameIndex(4);
    session.layerMarks.toggleMarkAtCurrentFrame();
    expect(timelineOf(session)[0]!.breakdownOffsets, [1, 4]);

    session.selectFrameIndex(2);
    session.createDrawingAtCurrentFrame();

    final timeline = timelineOf(session);
    // Offset 1 stays on the left half; offset 4 becomes offset 2 of the
    // right half, marking the same frame it always did.
    expect(timeline[0]!.breakdownOffsets, [1]);
    expect(timeline[2]!.breakdownOffsets, [2]);
  });
}
