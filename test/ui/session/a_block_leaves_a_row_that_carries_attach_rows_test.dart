import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/widgets/cursor_notice.dart';

/// 🚨F-276 (유저 2026-10-04): 「프레임 블록은 이동가능한곳이라면 어디든
/// 이동가능. 지금 어태치 싱크레이어를 가진 레이어의 블록을 다른 레이어로
/// 이동하는게 불가능한데 가능하도록. 그 경우 물론 싱크 레이어의 그림이
/// 있다면 사라지겠지. 안내문 안띄워도됨」.
///
/// A SYNCED attach row shows its base's blocks again — a MIRROR. The block
/// moved when its base row alone was selected; with the mirror in the
/// selection, or under the hand, the row change was switched off: the
/// mirror was read as a row of its own, and it has no seat a block can land
/// on. A mirror is its base's row shown again, wherever a move meets it.
void main() {
  setUp(cursorNotices.clear);

  Layer stored(EditorSessionManager s, LayerId id) =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  /// The row as the rail shows it — a mirror with the blocks it derives.
  Layer shown(EditorSessionManager s, LayerId id) =>
      s.layers.firstWhere((layer) => layer.id == id);

  LayerId addedRow(EditorSessionManager s, LayerKind kind) {
    s.layerStack.addLayerOfKind(kind);
    return s.activeLayer!.id;
  }

  /// A base row with a block at 3 and its mirror [placement] it, and a
  /// second drawing row above the pair.
  ({EditorSessionManager s, LayerId base, LayerId mirror, LayerId other})
  baseWithAMirror(AttachedPlacement placement) {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final base = s.activeLayer!.id;
    s.selectFrameIndex(3);
    s.createDrawingAtCurrentFrame();
    s.folders.addAttachedLayer(placement);
    final mirror = s.activeLayer!.id;
    s.selectLayer(base);
    final other = addedRow(s, LayerKind.animation);
    s.selectLayer(base);
    return (s: s, base: base, mirror: mirror, other: other);
  }

  /// Selects [base]'s block at 3 together with its [mirror].
  void selectBothFaces(EditorSessionManager s, LayerId base, LayerId mirror) {
    s.updateFrameRangeSelectionDrag(
      layerId: base,
      anchorIndex: 3,
      headIndex: 3,
      headLayerId: mirror,
    );
    expect(
      s.frameRangeSelection.value!.spanLayerIds,
      unorderedEquals([base, mirror]),
      reason: '⛔전제: the block and its mirror, both',
    );
  }

  for (final placement in AttachedPlacement.values) {
    for (final byItsMirror in [false, true]) {
      test('a block selected WITH its mirror (the mirror ${placement.name} '
          'it) leaves for the row the hand points at — grabbed by '
          '${byItsMirror ? 'the mirror' : 'the base'}', () {
        final (:s, :base, :mirror, :other) = baseWithAMirror(placement);
        final cel = stored(s, base).timeline[3]!.frameId!;
        final mirrorCel = stored(s, mirror).baseFrameLinks[cel]!;
        expect(
          shown(s, mirror).timeline[3]?.frameId,
          mirrorCel,
          reason: '⛔전제: the mirror shows the block',
        );
        selectBothFaces(s, base, mirror);
        final steps = s.historyManager.undoCount;

        expect(
          s.rangeMove.beginFrameRangeMoveDrag(byItsMirror ? mirror : base),
          isTrue,
        );
        s.rangeMove.updateFrameRangeMoveDrag(
          frameDelta: 0,
          targetLayerId: other,
        );
        s.rangeMove.endFrameRangeMoveDrag();

        expect(
          stored(s, other).timeline[3]?.frameId,
          cel,
          reason: '「이동가능한곳이라면 어디든」',
        );
        expect(stored(s, base).timeline[3], isNull);
        expect(
          shown(s, mirror).timeline[3],
          isNull,
          reason: '「싱크 레이어의 그림이 있다면 사라지겠지」',
        );
        expect(cursorNotices.message, isNull, reason: '「안내문 안띄워도됨」');
        expect(
          s.frameRangeSelection.value!.spanLayerIds,
          [other],
          reason: 'the selection is where the block went',
        );
        expect(s.historyManager.undoCount, steps + 1, reason: 'one step');

        s.undo();
        expect(stored(s, base).timeline[3]?.frameId, cel);
        expect(
          shown(s, mirror).timeline[3]?.frameId,
          mirrorCel,
          reason: 'the mirror shows the cel it had — its link never left',
        );
      });
    }
  }

  for (final withItsMirror in [false, true]) {
    test('selected ${withItsMirror ? 'with' : 'without'} its mirror, the '
        'block lands the same on a row with a block in the way: that block '
        'makes room', () {
      final (:s, :base, :mirror, :other) = baseWithAMirror(
        AttachedPlacement.above,
      );
      s.selectLayer(other);
      s.selectFrameIndex(3);
      s.createDrawingAtCurrentFrame();
      final inTheWay = stored(s, other).timeline[3]!.frameId!;
      s.selectLayer(base);
      final cel = stored(s, base).timeline[3]!.frameId!;
      if (withItsMirror) {
        selectBothFaces(s, base, mirror);
      } else {
        s.updateFrameRangeSelectionDrag(
          layerId: base,
          anchorIndex: 3,
          headIndex: 3,
        );
      }

      expect(s.rangeMove.beginFrameRangeMoveDrag(base), isTrue);
      s.rangeMove.updateFrameRangeMoveDrag(
        frameDelta: 0,
        targetLayerId: other,
      );
      s.rangeMove.endFrameRangeMoveDrag();

      expect(stored(s, other).timeline[3]?.frameId, cel);
      expect(
        stored(s, other).timeline[4]?.frameId,
        inTheWay,
        reason: 'the one row\'s law (R12-②), whichever faces were selected',
      );
    });
  }

  test('a slide along its own row keeps the mirror it was selected with, '
      'and a move let go of leaves the selection as it was', () {
    final (:s, :base, :mirror, :other) = baseWithAMirror(
      AttachedPlacement.above,
    );
    final cel = stored(s, base).timeline[3]!.frameId!;
    selectBothFaces(s, base, mirror);
    final before = s.frameRangeSelection.value;

    expect(s.rangeMove.beginFrameRangeMoveDrag(mirror), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: other);
    s.rangeMove.cancelFrameRangeMoveDrag();
    expect(s.frameRangeSelection.value, before);
    expect(stored(s, base).timeline[3]?.frameId, cel);

    expect(s.rangeMove.beginFrameRangeMoveDrag(mirror), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 3, targetLayerId: mirror);
    s.rangeMove.endFrameRangeMoveDrag();

    expect(stored(s, base).timeline[6]?.frameId, cel);
    final landed = s.frameRangeSelection.value!;
    expect(landed.startIndex, 6);
    expect(landed.spanLayerIds, unorderedEquals([base, mirror]));
    expect(
      shown(s, mirror).timeline[6],
      isNotNull,
      reason: 'and the mirror shows the block where it went',
    );
  });

  test('carried off by its mirror and brought back to it, the block is home '
      '— the drop moves nothing', () {
    final (:s, :base, :mirror, :other) = baseWithAMirror(
      AttachedPlacement.below,
    );
    final cel = stored(s, base).timeline[3]!.frameId!;
    // Swept from the mirror up: the mirror is the row the selection names.
    s.updateFrameRangeSelectionDrag(
      layerId: mirror,
      anchorIndex: 3,
      headIndex: 3,
      headLayerId: base,
    );
    expect(s.frameRangeSelection.value!.layerId, mirror, reason: '⛔전제');
    final steps = s.historyManager.undoCount;

    expect(s.rangeMove.beginFrameRangeMoveDrag(mirror), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: other);
    expect(s.dragPreview.value, isNotNull, reason: '⛔전제: it was on its way');
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: mirror);
    expect(s.dragPreview.value, isNull, reason: 'R28 #5: back at the start');
    s.rangeMove.endFrameRangeMoveDrag();

    expect(stored(s, base).timeline[3]?.frameId, cel);
    expect(stored(s, other).timeline[3], isNull);
    expect(s.historyManager.undoCount, steps);
  });

  test('the hand over a mirror is over its base: a block dropped on another '
      'row\'s mirror lands on that row', () {
    final (:s, :base, :mirror, :other) = baseWithAMirror(
      AttachedPlacement.above,
    );
    s.selectLayer(other);
    s.selectFrameIndex(8);
    s.createDrawingAtCurrentFrame();
    final cel = stored(s, other).timeline[8]!.frameId!;
    s.updateFrameRangeSelectionDrag(
      layerId: other,
      anchorIndex: 8,
      headIndex: 8,
    );

    expect(s.rangeMove.beginFrameRangeMoveDrag(other), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: mirror);
    s.rangeMove.endFrameRangeMoveDrag();

    expect(stored(s, base).timeline[8]?.frameId, cel);
    expect(stored(s, other).timeline[8], isNull);
  });

  test('…and over its OWN mirror the block still follows the hand along '
      'the frames', () {
    final (:s, :base, :mirror, other: _) = baseWithAMirror(
      AttachedPlacement.below,
    );
    final cel = stored(s, base).timeline[3]!.frameId!;
    s.updateFrameRangeSelectionDrag(
      layerId: base,
      anchorIndex: 3,
      headIndex: 3,
    );

    expect(s.rangeMove.beginFrameRangeMoveDrag(base), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 2, targetLayerId: mirror);
    s.rangeMove.endFrameRangeMoveDrag();

    expect(stored(s, base).timeline[5]?.frameId, cel);
  });

  // The two rows that travel, and the hand that carries them: by the lower
  // row onto the row under it, or by the upper row's mirror onto the lower
  // row — one row down either way, the mirror no step of it.
  for (final byTheMirror in [false, true]) {
    test('two rows travel together past a mirror that sits between them — '
        'carried by ${byTheMirror ? 'that mirror' : 'the lower row'}', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final bottom = s.activeLayer!.id;
      final middle = addedRow(s, LayerKind.animation);
      s.selectFrameIndex(3);
      s.createDrawingAtCurrentFrame();
      final top = addedRow(s, LayerKind.animation);
      s.selectFrameIndex(3);
      s.createDrawingAtCurrentFrame();
      s.folders.addAttachedLayer(AttachedPlacement.below);
      final mirror = s.activeLayer!.id;
      final topCel = stored(s, top).timeline[3]!.frameId!;
      final middleCel = stored(s, middle).timeline[3]!.frameId!;
      s.selectLayer(top);
      s.updateFrameRangeSelectionDrag(
        layerId: top,
        anchorIndex: 3,
        headIndex: 3,
        headLayerId: middle,
      );
      expect(
        s.frameRangeSelection.value!.spanLayerIds,
        [middle, mirror, top],
        reason: '⛔전제: the mirror is BETWEEN the two rows that travel',
      );

      expect(
        s.rangeMove.beginFrameRangeMoveDrag(byTheMirror ? mirror : middle),
        isTrue,
      );
      s.rangeMove.updateFrameRangeMoveDrag(
        frameDelta: 0,
        targetLayerId: byTheMirror ? middle : bottom,
      );
      s.rangeMove.endFrameRangeMoveDrag();

      expect(stored(s, middle).timeline[3]?.frameId, topCel);
      expect(stored(s, bottom).timeline[3]?.frameId, middleCel);
      expect(stored(s, top).timeline[3], isNull);
    });
  }

  test('a picture row in the span keeps no other row from changing rows — '
      'and its own cel stays', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final drawn = s.activeLayer!.id;
    s.selectFrameIndex(3);
    s.createDrawingAtCurrentFrame();
    final cel = stored(s, drawn).timeline[3]!.frameId!;
    final picture = addedRow(s, LayerKind.image);
    final pictureBefore = stored(s, picture).timeline;
    expect(pictureBefore, isNotEmpty, reason: '⛔전제: its one cel');
    final other = addedRow(s, LayerKind.animation);
    s.selectLayer(drawn);
    s.updateFrameRangeSelectionDrag(
      layerId: drawn,
      anchorIndex: 3,
      headIndex: 3,
      headLayerId: picture,
    );
    expect(
      s.frameRangeSelection.value!.spanLayerIds,
      unorderedEquals([drawn, picture]),
      reason: '⛔전제',
    );

    expect(s.rangeMove.beginFrameRangeMoveDrag(drawn), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: other);
    s.rangeMove.endFrameRangeMoveDrag();

    expect(stored(s, other).timeline[3]?.frameId, cel);
    expect(stored(s, drawn).timeline[3], isNull);
    expect(stored(s, picture).timeline, pictureBefore);
  });
}
