import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// D19/D20/D21 (2026-08-18): GHOSTS ARE AUTHORING ROOM — 「데이터가 있는 곳
/// 취급인 듯하나 고스트일 뿐이니 생성 허용」. A ghost is a projection the
/// rederive pass wipes and rebuilds; the creation gate, the divide branch
/// and the range fill all read the same sentence now, so the single-cell
/// verb and the range verb cannot answer "is this cell free" differently.
void main() {
  (EditorSessionManager, LayerId) sessionWithHeldBlock({
    required TimelineRunEdgeMode mode,
  }) {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame(); // 1-cell block at index 0
    final layerId = s.activeLayer!.id;
    s.setRunEdgeBehavior(
      layerId: layerId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: mode,
    );
    return (s, layerId);
  }

  Layer layerOf(EditorSessionManager s, LayerId id) =>
      s.layers.firstWhere((layer) => layer.id == id);

  test('D21: the cell right after a held block CREATES — the hold ghost\'s '
      'start is authoring room, the exact refusal the user hit', () {
    final (s, layerId) = sessionWithHeldBlock(mode: TimelineRunEdgeMode.hold);
    addTearDown(s.dispose);
    expect(
      layerOf(s, layerId).timeline[1]!.ghost,
      isTrue,
      reason: 'fixture premise: the hold ghost starts at index 1',
    );

    s.selectFrameIndex(1);
    expect(
      s.canCreateDrawingAtCurrentFrame,
      isTrue,
      reason: 'D21: 「인덱스1 홀드 + 인덱스2 생성 불가」 was this gate',
    );
    s.createDrawingAtCurrentFrame();

    final layer = layerOf(s, layerId);
    expect(layer.timeline[1]!.ghost, isFalse, reason: 'authored, not ghost');
    expect(layer.timeline[1]!.length, 1, reason: '1-comma block');
  });

  test('D19: creating INSIDE a hold ghost yields a 1-comma block, never '
      'the ghost\'s remainder — and the projection re-clamps around it', () {
    final (s, layerId) = sessionWithHeldBlock(mode: TimelineRunEdgeMode.hold);
    addTearDown(s.dispose);

    s.selectFrameIndex(3);
    expect(s.canCreateDrawingAtCurrentFrame, isTrue);
    s.createDrawingAtCurrentFrame();

    final layer = layerOf(s, layerId);
    expect(layer.timeline[3]!.ghost, isFalse);
    expect(
      layer.timeline[3]!.length,
      1,
      reason: 'D19: 「원래 1칸 블록이어야 하는데 뒤가 쭉 이어진 블록」 — the '
          'ghost divide handed the new cell the remainder to the cut end',
    );
    // The rederive choke point rebuilt the hold ghost clamped to the room
    // BEFORE the new block (the fill stops at the first occupied key).
    final reclamped = layer.timeline[1];
    expect(reclamped, isNotNull);
    expect(reclamped!.ghost, isTrue);
    expect(reclamped.length, 2, reason: 'ghost refills [1,3) only');
  });

  test('D20: a repeat ghost\'s block start CREATES', () {
    final (s, layerId) = sessionWithHeldBlock(
      mode: TimelineRunEdgeMode.repeat,
    );
    addTearDown(s.dispose);
    expect(
      layerOf(s, layerId).timeline[2]?.ghost,
      isTrue,
      reason: 'fixture premise: 1-cell repeat parts — every index a start',
    );

    s.selectFrameIndex(2);
    expect(
      s.canCreateDrawingAtCurrentFrame,
      isTrue,
      reason: 'D20: a ghost block START used to refuse like a real one',
    );
    s.createDrawingAtCurrentFrame();

    final layer = layerOf(s, layerId);
    expect(layer.timeline[2]!.ghost, isFalse);
    expect(layer.timeline[2]!.length, 1);
  });

  test('range-create fills ghost-covered cells too — one coverage answer '
      'for the single-cell verb and the range verb', () {
    final (s, layerId) = sessionWithHeldBlock(mode: TimelineRunEdgeMode.hold);
    addTearDown(s.dispose);

    s.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 1,
      headIndex: 3,
      headLayerId: layerId,
    );
    expect(s.createInstancesForSelection(), isTrue);

    final layer = layerOf(s, layerId);
    final fill = layer.timeline[1];
    expect(fill, isNotNull);
    expect(fill!.ghost, isFalse);
    expect(
      fill.length,
      3,
      reason: 'the ghost tail was authoring room for the whole [1,4) range',
    );
  });
}
