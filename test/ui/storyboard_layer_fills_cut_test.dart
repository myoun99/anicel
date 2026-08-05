import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/storyboard_coverage.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

/// The storyboard row lives INSIDE its cut, edge to edge, from the first
/// instant: born covering it, and the cut cannot then shrink past the
/// drawings on it. The two halves together are what leave the coverage
/// rule with no hole to repair.
void main() {
  EditorSessionManager sessionFor() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    return session;
  }

  test('a new storyboard row covers the whole cut with ONE cell', () {
    final session = sessionFor();
    final duration = session.requireActiveCut.duration;

    session.addLayerOfKind(LayerKind.storyboard);

    final layer = storyboardLayerForCut(session.requireActiveCut)!;
    expect(layer.timeline.keys, [0]);
    expect(layer.timeline[0]!.length, duration);
    // And it reads as exactly one panel over the cut.
    final cells = storyboardCoverageCells(
      timeline: layer.timeline,
      cutDuration: duration,
    );
    expect(cells, hasLength(1));
    expect(cells.single.startIndex, 0);
    expect(cells.single.endIndexExclusive, duration);
    expect(cells.single.frameId, layer.timeline[0]!.frameId);
  });

  test('the cell carries a real drawing, so the row is drawable at once', () {
    final session = sessionFor();

    session.addLayerOfKind(LayerKind.storyboard);

    final layer = storyboardLayerForCut(session.requireActiveCut)!;
    expect(layer.frames, hasLength(1));
    expect(layer.frames.single.id, layer.timeline[0]!.frameId);
  });

  test('a plain cel row still starts EMPTY — this is the storyboard row\'s '
      'rule, not a new rule for everyone', () {
    final session = sessionFor();

    session.addLayerOfKind(LayerKind.animation);

    final added = session.layers.firstWhere(
      (layer) => layer.id == session.activeLayerId,
    );
    expect(added.timeline, isEmpty);
  });

  test('the row can be DIVIDED from the moment it is made: add-frame '
      'inside its one cell splits it', () {
    final session = sessionFor();
    session.addLayerOfKind(LayerKind.storyboard);
    final duration = session.requireActiveCut.duration;

    session.selectFrameIndex(3);
    expect(session.canCreateDrawingAtCurrentFrame, isTrue);
    session.createDrawingAtCurrentFrame();

    final layer = storyboardLayerForCut(session.requireActiveCut)!;
    expect(layer.timeline.keys, [0, 3]);
    expect(
      storyboardCoverageCells(
        timeline: layer.timeline,
        cutDuration: duration,
      ).map((cell) => cell.endIndexExclusive),
      [3, duration],
    );
  });

  group('the cut cannot shrink past the row', () {
    test('with no storyboard row the floor is one frame', () {
      final session = sessionFor();

      expect(minimumCutDurationFor(session.requireActiveCut), 1);
    });

    test('the floor is the LAST division plus one', () {
      final session = sessionFor();
      session.addLayerOfKind(LayerKind.storyboard);
      session.selectFrameIndex(5);
      session.createDrawingAtCurrentFrame();

      expect(minimumCutDurationFor(session.requireActiveCut), 6);
    });

    test('an END trim stops at that floor instead of at one frame', () {
      final session = sessionFor();
      session.addLayerOfKind(LayerKind.storyboard);
      session.selectFrameIndex(5);
      session.createDrawingAtCurrentFrame();
      final cutId = session.activeCutId!;

      session.beginCutEdgeDrag(cutId: cutId, edge: TimelineBlockEdge.end);
      // Drag far past the floor: it holds at 6.
      session.updateCutEdgeDrag(-100);
      session.endCutEdgeDrag();

      expect(session.requireActiveCut.duration, 6);
      // The drawings are all still inside the cut, which is the point.
      expect(
        storyboardLayerForCut(session.requireActiveCut)!.timeline.keys.last,
        lessThan(session.requireActiveCut.duration),
      );
    });

    test('a LEAD drag is floored by the panel it GRABBED, not by the last '
        'one — the grabbed panel keeps one frame', () {
      final session = sessionFor();
      session.addLayerOfKind(LayerKind.storyboard);
      session.selectFrameIndex(5);
      session.createDrawingAtCurrentFrame();
      final cutId = session.activeCutId!;
      final duration = session.requireActiveCut.duration;
      // Row {0: 5, 5: 19} — a SHORT first panel and a long last one, which
      // is the shape that tells the two floors apart. The last division sits
      // at 5, so [minimumCutDurationFor] would let the cut shrink to 6; the
      // first panel has 4 frames to give, so the real floor is 4 less than
      // the duration.
      expect(minimumCutDurationFor(session.requireActiveCut), 6);

      session.beginCutEdgeDrag(cutId: cutId, edge: TimelineBlockEdge.start);
      session.updateCutEdgeDrag(100);
      session.endCutEdgeDrag();

      expect(session.requireActiveCut.duration, duration - 4);
      expect(
        session.requireActiveCut.leadingGapFrames,
        4,
        reason: 'the head takes exactly what the cut gave up',
      );
      // The panel the grip sat on is the one that gave the frames up, and
      // it stopped at one. Every other panel kept its commas.
      final row = storyboardLayerForCut(session.requireActiveCut)!;
      expect(row.timeline.keys, [0, 1]);
      expect(row.timeline[0]!.length, 1);
      expect(row.timeline[1]!.length, 19);
      final lastKey = row.timeline.keys.last;
      expect(
        lastKey + row.timeline[lastKey]!.length!,
        session.requireActiveCut.duration,
      );
    });

    test('R10 R4: a lead drag that GROWS the cut leaves the row still '
        'covering it — the tiling invariant survives the new verb', () {
      final session = sessionFor();
      session.addLayerOfKind(LayerKind.storyboard);
      session.selectFrameIndex(5);
      session.createDrawingAtCurrentFrame();
      final cutId = session.activeCutId!;

      // Open room in front so the lead edge has somewhere to grow into.
      session.beginCutEdgeDrag(cutId: cutId, edge: TimelineBlockEdge.start);
      session.updateCutEdgeDrag(3);
      session.endCutEdgeDrag();
      final shrunk = session.requireActiveCut.duration;

      // …then pull it back out. The cut grows from the front.
      session.beginCutEdgeDrag(cutId: cutId, edge: TimelineBlockEdge.start);
      session.updateCutEdgeDrag(-3);
      session.endCutEdgeDrag();
      final cut = session.requireActiveCut;
      expect(cut.duration, shrunk + 3);
      expect(cut.leadingGapFrames, 0);

      // The invariant this whole file is about: the row's cells still
      // reach the cut's end, so the timeline row shows no uncovered
      // frames where the strip shows a full panel.
      final stored = storyboardLayerForCut(cut)!.timeline;
      final cells = storyboardCoverageCells(
        timeline: stored,
        cutDuration: cut.duration,
      );
      expect(cells, isNotEmpty);
      expect(
        cells.last.endIndexExclusive,
        cut.duration,
        reason: 'a storyboard row TILES its cut, on either side of the drag',
      );
      // ⚠️ The derived cells above say nothing about WHICH panel absorbed —
      // they read the same whoever did. The STORE is what tells a symmetric
      // verb from a sign-blind one: shrink 3 then grow 3 must land on the
      // row it started from, or the commas drift a little every round trip
      // while the cut length keeps looking correct.
      expect(
        {for (final key in stored.keys) key: stored[key]!.length},
        {0: 5, 5: 19},
        reason: 'a round trip through the lead edge is the identity',
      );
    });

    test('R10 R4: after a LEAD drag the stored row still ends where the cut '
        'ends, so the NEXT end drag does not snap the cut back', () {
      final session = sessionFor();
      session.addLayerOfKind(LayerKind.storyboard);
      session.selectFrameIndex(5);
      session.createDrawingAtCurrentFrame();
      final cutId = session.activeCutId!;

      session.beginCutEdgeDrag(cutId: cutId, edge: TimelineBlockEdge.start);
      session.updateCutEdgeDrag(2);
      session.endCutEdgeDrag();
      final trimmed = session.requireActiveCut.duration;

      // "The cut ENDS WHERE THE ROW ENDS" — the invariant the end/comma
      // verb derives the duration FROM. A lead drag that moved only the
      // duration would leave the row ending 2 frames late, and the very
      // next end drag would snap the cut back to it.
      final row = storyboardLayerForCut(session.requireActiveCut)!;
      final lastKey = row.timeline.keys.last;
      expect(
        lastKey + row.timeline[lastKey]!.length!,
        trimmed,
        reason: 'the row still ends exactly where the cut does',
      );
      expect(
        row.timeline.keys,
        [0, 3],
        reason: 'the GRABBED panel gave up the 2 frames — 5 becomes 3 — and '
            'the division behind it rode along keeping its own comma',
      );
      expect(row.timeline[0]!.length, 3);
      expect(
        row.timeline[3]!.length,
        19,
        reason: 'nobody else changed length; that is the whole rule',
      );

      // Undo takes the row and the duration back together, in ONE step.
      session.undo();
      final restored = storyboardLayerForCut(session.requireActiveCut)!;
      final restoredLast = restored.timeline.keys.last;
      expect(session.requireActiveCut.duration, trimmed + 2);
      expect(
        restoredLast + restored.timeline[restoredLast]!.length!,
        trimmed + 2,
      );
    });

    test('a cut with no storyboard row still trims down to one frame', () {
      final session = sessionFor();
      final cutId = session.activeCutId!;

      session.beginCutEdgeDrag(cutId: cutId, edge: TimelineBlockEdge.end);
      session.updateCutEdgeDrag(-100);
      session.endCutEdgeDrag();

      expect(session.requireActiveCut.duration, 1);
    });
  });
}
