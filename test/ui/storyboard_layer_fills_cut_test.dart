import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/controllers/default_project_helpers.dart';
import 'package:quick_animaker_v2/src/models/layer_kind.dart';
import 'package:quick_animaker_v2/src/models/storyboard_coverage.dart';
import 'package:quick_animaker_v2/src/models/timeline_coverage.dart';
import 'package:quick_animaker_v2/src/ui/editor_session_manager.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_layer_policy.dart';

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

    test('a START trim stops there too', () {
      final session = sessionFor();
      session.addLayerOfKind(LayerKind.storyboard);
      session.selectFrameIndex(5);
      session.createDrawingAtCurrentFrame();
      final cutId = session.activeCutId!;

      session.beginCutEdgeDrag(cutId: cutId, edge: TimelineBlockEdge.start);
      session.updateCutEdgeDrag(100);
      session.endCutEdgeDrag();

      expect(session.requireActiveCut.duration, 6);
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
