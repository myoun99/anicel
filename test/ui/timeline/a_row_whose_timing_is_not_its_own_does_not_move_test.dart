import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_repeat.dart'
    show TimelineRunEdgeMode, TimelineRunEdgeSide;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// A PICTURE row (one cel pinned over the cut) keeps its timing: the verbs
/// that move or reshape a block — the block move, the add-frames grip, the
/// run's end behaviour, a range move landing on it, a multi-row shift
/// travelling across it, the shove — all stand it down.
///
/// 🧪Pinned when the audit's nineteenth family (2026-09-28) moved the two
/// halves of this law — `blockMoveEligible` and `standsDownFromRetime` —
/// into a role of their own (`RetimeLaw`): a mutant that answered every row
/// "eligible" at each asker survived every suite, and so did one that let
/// the shove's current-row scope through. Nothing measured the refusals.
void main() {
  /// A session whose active cut holds a picture row, standing on it.
  (EditorSessionManager, Layer) sessionOnAPictureRow() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.layerStack.addLayerOfKind(LayerKind.image);
    final picture = s.activeLayer!;
    expect(picture.timeline[0], isNotNull, reason: '⛔premise: its one cel');
    return (s, picture);
  }

  Layer stored(EditorSessionManager s, LayerId id) =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  test('its block does not pick up for a block move', () {
    final (s, picture) = sessionOnAPictureRow();

    expect(
      s.drawingBlockMove.beginDrawingBlockMoveDrag(
        layerId: picture.id,
        blockStartIndex: 0,
      ),
      isFalse,
    );
  });

  test('its block takes no frames from the add-frames grip', () {
    final (s, picture) = sessionOnAPictureRow();

    expect(
      s.runFramesAdd.beginRunFramesAddDrag(
        layerId: picture.id,
        blockStartIndex: 0,
        atEnd: true,
      ),
      isFalse,
    );
  });

  test('its run keeps the end behaviour it was born with', () {
    final (s, picture) = sessionOnAPictureRow();
    final before = stored(s, picture.id).timeline;

    s.rangeMove.setRunEdgeBehavior(
      layerId: picture.id,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );

    expect(stored(s, picture.id).timeline, before);
  });

  test('the shove has no row to push when the picture row is where you '
      'stand', () {
    final (s, picture) = sessionOnAPictureRow();
    expect(s.frameRangeSelection.value, isNull, reason: '⛔premise');

    expect(
      s.blockShift.canPushFrames(currentRow: LayerRowAddress(picture.id)),
      isFalse,
    );
  });

  test('a drawing block dropped on it stays on its own row', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.selectFrameIndex(3);
    s.createDrawingAtCurrentFrame();
    final drawn = s.activeLayer!;
    final cel = drawn.timeline[3]!.frameId;
    s.layerStack.addLayerOfKind(LayerKind.image);
    final picture = s.activeLayer!;
    final pictureBefore = stored(s, picture.id).timeline;

    s.selectLayer(drawn.id);
    s.updateFrameRangeSelectionDrag(
      layerId: drawn.id,
      anchorIndex: 3,
      headIndex: 3,
    );
    expect(s.rangeMove.beginFrameRangeMoveDrag(), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(
      frameDelta: 0,
      targetLayerId: picture.id,
    );
    s.rangeMove.endFrameRangeMoveDrag();

    expect(stored(s, drawn.id).timeline[3]?.frameId, cel);
    expect(stored(s, picture.id).timeline, pictureBefore);
  });

  test('a multi-row shift does not travel onto it', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.selectFrameIndex(3);
    s.createDrawingAtCurrentFrame(); // a block on A
    final a = s.activeLayer!.id;
    s.layerStack.addLayer();
    final b = s.activeLayer!.id;
    s.selectFrameIndex(3);
    s.createDrawingAtCurrentFrame(); // a block on B
    s.layerStack.addLayerOfKind(LayerKind.image); // the row below B
    final picture = s.activeLayer!.id;
    final pictureBefore = stored(s, picture).timeline;

    s.selectLayer(a);
    s.updateFrameRangeSelectionDrag(
      layerId: a,
      anchorIndex: 3,
      headIndex: 3,
      headLayerId: b,
    );
    expect(s.frameRangeSelection.value!.spanLayerIds, [a, b]);
    if (s.rangeMove.beginFrameRangeMoveDrag()) {
      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: b);
      s.rangeMove.endFrameRangeMoveDrag();
    }

    expect(stored(s, picture).timeline, pictureBefore);
  });
}
