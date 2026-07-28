import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
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
    session.setCommaForSelectionOrCurrent(length);
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
    expect(session.canCreateDrawingAtCurrentFrame, isTrue);
    session.createDrawingAtCurrentFrame();

    final timeline = timelineOf(session);
    expect(timeline.keys, [0, 2]);
    expect(timeline[0]!.length, 2);
    expect(timeline[2]!.length, 4);
    // A NEW drawing, not the old one re-exposed: the divide button that
    // duplicates the picture is a separate verb.
    expect(timeline[2]!.frameId, isNot(timeline[0]!.frameId));
  });

  test('the block START still refuses: there is nothing there to divide', () {
    final session = sessionWithHeldBlock();

    session.selectFrameIndex(0);

    expect(session.canCreateDrawingAtCurrentFrame, isFalse);
  });

  test('an empty cell still just creates, as it always did', () {
    final session = sessionWithHeldBlock(length: 2);

    session.selectFrameIndex(4);
    expect(session.canCreateDrawingAtCurrentFrame, isTrue);
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
    session.toggleMarkAtCurrentFrame();
    session.selectFrameIndex(4);
    session.toggleMarkAtCurrentFrame();
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
