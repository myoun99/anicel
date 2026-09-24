import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_marker.dart';

/// 🚨★★★R27 — A DIRECTION ROW'S BLOCK IS ITS SPAN.
///
/// 유저 2026-09-12 (Q1): 「**블록 = 스팬, 스팬마다 제 그림 한 장**」 — and
/// what was wrong with the row, in the user's words: 「디렉션레이어 그림
/// 그려지지도않고 프레임 삭제나 그런 버튼 비활성화된상태」 (09-11), and
/// 「추가로 디렉션 레이어의 프레임블록이 삭제안됨. 삭제버튼 활성화안됨.
/// 복사든 뭐든 싹다」 (09-12).
///
/// The span lived beside the blocks, where no block verb looked, so none of
/// them found anything. Each case below drives the verb a press drives and
/// reads the row back — the brush target, delete, the instruction's own
/// delete, an edit, duplicate, copy and paste, and the names the row hides.
void main() {
  late EditorSessionManager session;

  Layer direction() => session.requireActiveCut.layers.firstWhere(
    (layer) => layer.kind == LayerKind.instruction,
  );

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    session.selectLayer(direction().id);
  });

  tearDown(() => session.dispose());

  /// The ＋ on frame [at]: the dialog-free creation.
  void plus(int at) {
    session.selectFrameIndex(at);
    session.instructionVerbs.createDefaultInstructionEventAtCurrentFrame();
  }

  /// A span of [length] frames at [at], through the dialog's commit.
  void span(int at, int length, {String id = 'pan'}) =>
      session.instructionVerbs.upsertInstructionEventAt(
        direction().id,
        at,
        InstructionEvent(instructionId: id, length: length),
        createLengthFrames: length,
      );

  FrameId celAt(int frame) => direction().timeline[frame]!.frameId!;

  group('the span is a block', () {
    test('＋ makes a span that IS a block, on a cel of its own', () {
      plus(2);

      final row = direction();
      final block = row.timeline[2];
      expect(block, isNotNull, reason: 'the span is a block on the row');
      expect(block!.instruction, isNotNull);
      expect(row.frames.map((frame) => frame.id), contains(block.frameId));
      expect(row.instructions.keys, [2]);
      expect(
        session.frameVerbs.selectedFrame?.id,
        block.frameId,
        reason: '「프레임이 존재하지 않습니다」 was the brush finding no cel '
            'under a span',
      );
    });

    test('every cell of a span shows its one drawing', () {
      span(2, 4);

      final cel = celAt(2);
      for (var frame = 2; frame < 6; frame += 1) {
        session.selectFrameIndex(frame);
        expect(session.frameVerbs.selectedFrame?.id, cel, reason: '$frame');
      }
      expect(direction().instructions[2]?.length, 4);
    });

    test('two spans are two drawings', () {
      plus(0);
      plus(3);

      expect(celAt(0), isNot(celAt(3)));
    });
  });

  group('deleting', () {
    test('🚨the delete button takes the span and its drawing, and undo '
        'brings both back', () {
      span(2, 3);
      final cel = celAt(2);
      session.selectFrameIndex(3);

      expect(
        session.cells.canDeleteCellAtCurrentFrame,
        isTrue,
        reason: '「삭제버튼 활성화안됨」',
      );
      session.cells.deleteCellAtCurrentFrame();

      expect(direction().instructions, isEmpty);
      expect(direction().timeline, isEmpty);
      expect(direction().frameById(cel), isNull, reason: 'its drawing too');

      session.undo();
      expect(direction().instructions.keys, [2]);
      expect(direction().frameById(cel), isNotNull);
    });

    test("the instruction's own delete is the block's delete", () {
      span(2, 3);
      final cel = celAt(2);

      session.instructionVerbs.removeInstructionEventAt(direction().id, 3);

      expect(direction().instructions, isEmpty);
      expect(direction().timeline, isEmpty);
      expect(direction().frameById(cel), isNull);
    });
  });

  test('editing the instruction keeps its drawing', () {
    plus(2);
    final cel = celAt(2);

    session.instructionVerbs.upsertInstructionEventAt(
      direction().id,
      2,
      const InstructionEvent(instructionId: 'fo', length: 1),
    );

    expect(celAt(2), cel);
    expect(direction().instructions[2]?.instructionId, 'fo');
  });

  group('copying', () {
    test('🚨a duplicate carries the span — with a drawing of its own, or '
        'the same one when linked', () {
      span(2, 2);
      session.selectFrameIndex(2);

      expect(session.frameVerbs.canDuplicateActiveBlock, isTrue);
      session.frameVerbs.duplicateActiveBlock(linked: false);
      expect(direction().instructions.keys, [2, 4]);
      expect(direction().instructions[4]?.instructionId, 'pan');
      expect(celAt(4), isNot(celAt(2)));

      session.selectFrameIndex(2);
      session.frameVerbs.duplicateActiveBlock(linked: true);
      final spans = direction().instructions;
      expect(spans, hasLength(3));
      expect(
        spans.values.every((span) => span.instructionId == 'pan'),
        isTrue,
        reason: 'each linked block keeps its own span',
      );
    });

    test('a copied block pastes as the span it is', () {
      span(2, 2);
      session.selectFrameIndex(2);
      session.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: direction().id,
        startIndex: 2,
        endIndexExclusive: 4,
      );
      expect(session.clipboard.canCopyFrameAtCurrentFrame, isTrue);
      session.clipboard.copyFrameAtCurrentFrame();
      session.frameRangeSelection.value = null;

      session.selectFrameIndex(8);
      expect(session.clipboard.canPasteIndependentFrameAtCurrentFrame, isTrue);
      session.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(direction().instructions[8]?.instructionId, 'pan');
      expect(direction().instructions[8]?.length, 2);
      expect(celAt(8), isNot(celAt(2)));
    });
  });

  group('moving — the drawing goes where the span goes', () {
    test('a comma drag retimes the block, and the span with it', () {
      span(2, 2);
      final cel = celAt(2);

      expect(
        session.edgeDrag.beginExposureEdgeDrag(
          layerId: direction().id,
          blockStartIndex: 2,
          edge: TimelineBlockEdge.end,
        ),
        isTrue,
      );
      session.edgeDrag.updateExposureEdgeDrag(3);
      session.edgeDrag.endExposureEdgeDrag();

      expect(direction().instructions[2]?.length, 5);
      expect(celAt(2), cel);
    });

    test('a slide moves the block, drawing and span together', () {
      span(2, 2);
      final cel = celAt(2);

      session.updateFrameRangeSelectionDrag(
        layerId: direction().id,
        anchorIndex: 2,
        headIndex: 3,
      );
      expect(session.rangeMove.beginFrameRangeMoveDrag(), isTrue);
      session.rangeMove.updateFrameRangeMoveDrag(frameDelta: 3);
      session.rangeMove.endFrameRangeMoveDrag();

      expect(direction().instructions.keys, [5]);
      expect(celAt(5), cel);
    });

    test('🚨a drop on another direction row carries the drawing there', () {
      span(2, 2);
      final source = direction();
      final cel = celAt(2);
      session.layerStack.addLayerOfKind(LayerKind.instruction);
      final target = session.requireActiveCut.layers.lastWhere(
        (layer) =>
            layer.kind == LayerKind.instruction && layer.id != source.id,
      );

      session.updateFrameRangeSelectionDrag(
        layerId: source.id,
        anchorIndex: 2,
        headIndex: 3,
      );
      expect(session.rangeMove.beginFrameRangeMoveDrag(), isTrue);
      session.rangeMove.updateFrameRangeMoveDrag(
        frameDelta: 0,
        targetLayerId: target.id,
      );
      session.rangeMove.endFrameRangeMoveDrag();

      Layer row(Layer of) => session.requireActiveCut.layers.firstWhere(
        (layer) => layer.id == of.id,
      );
      expect(row(source).instructions, isEmpty);
      expect(row(source).frameById(cel), isNull, reason: 'the drawing left');
      expect(row(target).instructions[2]?.instructionId, 'pan');
      expect(row(target).frameById(cel), isNotNull, reason: 'and landed');
    });
  });

  group('names (유저 2026-09-12: 「이름을 안보이게, 수정못하게」)', () {
    test('a direction block shows no name — not even the mark', () {
      plus(2);
      for (final name in [null, 'A1']) {
        expect(
          timelineCellMarker(
            layer: direction(),
            exposureState: TimelineCellExposureState.drawingStart,
            emptyRunStart: false,
            frameName: name,
          ),
          timelineCellWritesNothing,
          reason: 'name $name',
        );
      }
    });

    test('and its name cannot be edited', () {
      plus(2);
      session.selectFrameIndex(2);
      expect(session.frameVerbs.canRenameFrameAtCurrentFrame, isFalse);
    });
  });

  group('the write-time law', () {
    test('a cel made on an empty direction cell is a span — the ＋ one', () {
      session.selectFrameIndex(5);
      session.createDrawingAtCurrentFrame();

      final spans = direction().instructions;
      expect(spans.keys, [5], reason: 'a block there IS a span');
      expect(
        spans[5]!.instructionId,
        session.camera.cameraInstructionSet.defs.first.id,
      );
    });

    test('a direction block pasted onto a drawing row brings its picture, '
        'not its span', () {
      span(2, 2);
      session.selectFrameIndex(2);
      session.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: direction().id,
        startIndex: 2,
        endIndexExclusive: 4,
      );
      session.clipboard.copyFrameAtCurrentFrame();
      session.frameRangeSelection.value = null;

      final drawing = session.requireActiveCut.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );
      session.selectLayer(drawing.id);
      session.selectFrameIndex(10);
      session.clipboard.pasteIndependentFrameAtCurrentFrame();

      final landed = session.requireActiveCut.layers
          .firstWhere((layer) => layer.id == drawing.id)
          .timeline[10];
      expect(landed, isNotNull, reason: 'the block landed');
      expect(landed!.instruction, isNull, reason: 'and put its span down');
    });

    test('the predicate is derived — spans ride blocks on a row that '
        'carries instructions AND has cels, and nowhere else', () {
      for (final kind in LayerKind.values) {
        expect(
          kind.spansRideBlocks,
          kind.carriesInstructions && kind.isDrawingCel,
          reason: '$kind',
        );
      }
      expect(LayerKind.instruction.spansRideBlocks, isTrue);
      expect(LayerKind.transition.spansRideBlocks, isFalse);
    });
  });

  group('the file', () {
    test("a direction row's spans travel as its blocks, and come back", () {
      span(2, 3);
      final row = direction();

      final json = row.toJson();
      expect(
        json.containsKey('instructions'),
        isFalse,
        reason: 'no span map beside the blocks — the blocks carry them',
      );
      final back = Layer.fromJson(json);
      expect(back.instructions, row.instructions);
      expect(back.timeline[2]?.frameId, row.timeline[2]?.frameId);
    });

    test('a row from before R27 opens with each span a block on a blank '
        'cel of its own', () {
      final legacy = {
        ...Layer(
          id: direction().id,
          name: 'D1',
          kind: LayerKind.instruction,
          frames: const [],
        ).toJson(),
        'instructions': [
          {'index': 1, 'instructionId': 'pan', 'length': 4},
          {'index': 7, 'instructionId': 'fi', 'length': 2},
        ],
      };

      final opened = Layer.fromJson(legacy);

      expect(opened.instructions.keys, [1, 7]);
      expect(opened.instructions[1]?.length, 4);
      final cels = {
        for (final start in [1, 7]) opened.timeline[start]!.frameId!,
      };
      expect(cels, hasLength(2), reason: 'a drawing each');
      for (final cel in cels) {
        expect(opened.frameById(cel)?.strokes, isEmpty, reason: 'blank');
      }
    });
  });
}
