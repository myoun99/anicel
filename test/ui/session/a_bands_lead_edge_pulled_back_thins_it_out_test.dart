import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

/// I-179-Q1 — A BAND'S LEAD EDGE PULLED BACK THINS IT OUT, on every row it
/// spans, whichever of its blocks the hand holds: counted in blocks from
/// the band's first, one in every pull + 1 stays and runs on over the ones
/// after it.
///
/// 유저 2026-11-19: 「12345678 이렇게 1장씩있고 8장선택하고 1의 앞엣지 뒤로
/// 1칸밀면 1-3-5-7- … 총 2칸밀면 1--4--7-」 — answered 「솎아내기 — 당긴 칸
/// 수만큼 건너뛰며 남긴다」. Each case drives the edge a press drives.
void main() {
  /// The default project's cut with its animation row drawn at [frames],
  /// one frame each, and stood on.
  (EditorSessionManager, LayerId) drawnAt(List<int> frames) {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final rowId = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    session.selectLayer(rowId);
    for (final frame in frames) {
      session.selectFrameIndex(frame);
      session.createDrawingAtCurrentFrame();
    }
    return (session, rowId);
  }

  Map<int, int?> rowOf(EditorSessionManager session, LayerId id) => {
    for (final MapEntry(:key, :value) in session.layers
        .firstWhere((layer) => layer.id == id)
        .timeline
        .entries)
      key: value.length,
  };

  int celsOf(EditorSessionManager session, LayerId id) =>
      session.layers.firstWhere((layer) => layer.id == id).frames.length;

  void sweep(EditorSessionManager session, LayerId rowId, int from, int to) =>
      session.updateFrameRangeSelectionDrag(
        layerId: rowId,
        anchorIndex: from,
        headIndex: to,
      );

  /// [rowId]'s block at [blockStart] held by its lead edge and dragged
  /// through [steps], then let go.
  void pull(
    EditorSessionManager session,
    LayerId rowId,
    int blockStart,
    List<int> steps,
  ) {
    expect(
      session.edgeDrag.beginExposureEdgeDrag(
        layerId: rowId,
        blockStartIndex: blockStart,
        edge: TimelineBlockEdge.start,
      ),
      isTrue,
      reason: 'fixture: the grip takes',
    );
    steps.forEach(session.edgeDrag.updateExposureEdgeDrag);
    session.edgeDrag.endExposureEdgeDrag();
  }

  const eight = [0, 1, 2, 3, 4, 5, 6, 7];

  test('🗣️eight on ones pulled one frame: 「1-3-5-7-」 — and the cels of the '
      'ones that went, with them', () {
    final (session, rowId) = drawnAt(eight);
    sweep(session, rowId, 0, 7);

    pull(session, rowId, 0, [1]);

    expect(rowOf(session, rowId), {0: 2, 2: 2, 4: 2, 6: 2});
    expect(celsOf(session, rowId), 4, reason: 'F-136: none holds them now');
  });

  test('🗣️two frames: 「1--4--7-」', () {
    final (session, rowId) = drawnAt(eight);
    sweep(session, rowId, 0, 7);

    pull(session, rowId, 0, [2]);

    expect(rowOf(session, rowId), {0: 3, 3: 3, 6: 2});
  });

  test('whichever of the band\'s blocks the hand holds, the same row', () {
    for (final held in [0, 5, 7]) {
      final (session, rowId) = drawnAt(eight);
      sweep(session, rowId, 0, 7);

      pull(session, rowId, held, [1]);

      expect(
        rowOf(session, rowId),
        {0: 2, 2: 2, 4: 2, 6: 2},
        reason: 'held at $held',
      );
    }
  });

  test('the drag thins as far as the hand is now: pulled back in, the row '
      'is as that step has it, and at none it is as it was', () {
    final (session, rowId) = drawnAt(eight);
    sweep(session, rowId, 0, 7);
    pull(session, rowId, 0, [3, 2, 1]);
    expect(rowOf(session, rowId), {0: 2, 2: 2, 4: 2, 6: 2});

    final (again, againId) = drawnAt(eight);
    sweep(again, againId, 0, 7);
    pull(again, againId, 0, [2, 0]);
    expect(rowOf(again, againId), {for (final frame in eight) frame: 1});
  });

  test('one undo puts every block back', () {
    final (session, rowId) = drawnAt(eight);
    sweep(session, rowId, 0, 7);
    pull(session, rowId, 0, [2]);
    expect(rowOf(session, rowId), {0: 3, 3: 3, 6: 2}, reason: 'fixture');

    session.undo();

    expect(rowOf(session, rowId), {for (final frame in eight) frame: 1});
    expect(celsOf(session, rowId), 8);
  });

  test('nothing outside the band moves', () {
    final (session, rowId) = drawnAt(eight);
    sweep(session, rowId, 2, 5);

    pull(session, rowId, 3, [1]);

    expect(rowOf(session, rowId), {0: 1, 1: 1, 2: 2, 4: 2, 6: 1, 7: 1});
  });

  test('every row the band spans thins out, counted on its own', () {
    final (session, rowId) = drawnAt([0, 1, 2, 3]);
    session.layerStack.addLayerOfKind(LayerKind.animation);
    final otherId = session.activeLayerId!;
    for (final frame in [0, 1]) {
      session.selectFrameIndex(frame);
      session.createDrawingAtCurrentFrame();
    }
    expect(rowOf(session, otherId), {0: 1, 1: 1, 2: 1}, reason: 'fixture');
    session.updateFrameRangeSelectionDrag(
      layerId: rowId,
      anchorIndex: 0,
      headIndex: 3,
      spanRows: [LayerRowAddress(rowId), LayerRowAddress(otherId)],
    );

    pull(session, otherId, 1, [1]);

    expect(rowOf(session, rowId), {0: 2, 2: 2});
    expect(rowOf(session, otherId), {0: 2, 2: 1}, reason: 'three: one left');
  });

  test('pushed forward it still drives the blocks in front down to one '
      'each (I-21) — only a pull back thins', () {
    final (session, rowId) = drawnAt([0, 2, 4, 6]);
    for (final start in [0, 2, 4, 6]) {
      session.edgeDrag.beginExposureEdgeDrag(
        layerId: rowId,
        blockStartIndex: start,
        edge: TimelineBlockEdge.end,
      );
      session.edgeDrag.updateExposureEdgeDrag(1);
      session.edgeDrag.endExposureEdgeDrag();
    }
    expect(rowOf(session, rowId), {0: 2, 2: 2, 4: 2, 6: 2}, reason: 'fixture');
    sweep(session, rowId, 0, 7);

    pull(session, rowId, 6, [-3]);

    expect(rowOf(session, rowId), {0: 1, 1: 1, 2: 1, 3: 5});
  });

  test('the conte row thins out as a cel row does, and its cut keeps its '
      'length', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    for (final frame in [6, 12, 18]) {
      session.selectFrameIndex(frame);
      session.createDrawingAtCurrentFrame();
    }
    final conteId = storyboardLayerForCut(session.requireActiveCut)!.id;
    expect(
      rowOf(session, conteId),
      {0: 6, 6: 6, 12: 6, 18: 6},
      reason: 'fixture',
    );
    expect(session.requireActiveCut.duration, 24, reason: 'fixture');
    sweep(session, conteId, 0, 23);

    pull(session, conteId, 12, [1]);

    expect(rowOf(session, conteId), {0: 12, 12: 12});
    expect(session.requireActiveCut.duration, 24);
  });
}
