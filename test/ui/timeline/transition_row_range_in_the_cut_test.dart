import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/pill_subject.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_section_policy.dart'
    show sectionedLayerOrder;
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart'
    show StoryboardToolbarPanelContext;

/// transition-row-range-in-the-cut — a RANGE selection holds the transition
/// row's spans the way it holds any row's blocks, and moves and deletes them.
///
/// The cut's row is a projection ([[transition-row-open-in-the-cut]]): its
/// marks are not always where their spans are, so what a range covers there
/// is mapped back to the GLOBAL spans the marks show — an O.L's left out,
/// which the cut draws whole and the storyboard edits (유저 2026-09-26).
/// Before this, a range over the row moved nothing and deleted nothing, on
/// the storyboard as well as in the cut.
void main() {
  /// Two cuts, standing in the SECOND; [spans] places the track's transition
  /// spans given where cut 2 starts on the track.
  EditorSessionManager inCutTwoWith(
    Map<int, InstructionEvent> Function(int cutTwoStart) spans,
  ) {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.cutVerbs.createCut();
    session.selectCut(session.repository.requireProject().tracks.first.cuts[1].id);
    expect(
      session.activeCutFrameCount,
      greaterThanOrEqualTo(16),
      reason: 'premise: cut 2 has room for the spans below',
    );
    session.transitions.updateTransitionInstructions(
      SplayTreeMap<int, InstructionEvent>.from(
        spans(session.activeCutGlobalStartFrame),
      ),
    );
    return session;
  }

  LayerId transitionRowOf(EditorSessionManager session) =>
      session.activeTrack.transitionLayer.id;

  Iterable<int> spanStarts(EditorSessionManager session) =>
      session.activeTrack.transitionLayer.instructions.keys;

  Iterable<int> marks(EditorSessionManager session) =>
      session.transitions.trackTransitionDisplayLayer.instructions.keys;

  void selectOnTheRow(EditorSessionManager session, int from, int to) =>
      session.updateFrameRangeSelectionDrag(
        layerId: transitionRowOf(session),
        anchorIndex: from,
        headIndex: to,
      );

  /// A drag on the rail from [anchorRow] down or up to [headRow]: the rail
  /// hands over the rows it swept, in the order it draws them — the ones in
  /// between carry nothing here.
  void sweepFrom(
    EditorSessionManager session, {
    required LayerId anchorRow,
    required LayerId headRow,
    required int anchorIndex,
    required int headIndex,
  }) {
    final order = [
      for (final layer in sectionedLayerOrder(session.layers)) layer.id,
    ];
    final a = order.indexOf(anchorRow);
    final b = order.indexOf(headRow);
    expect([a, b], everyElement(isNonNegative), reason: 'premise: drawn rows');
    session.updateFrameRangeSelectionDrag(
      layerId: anchorRow,
      anchorIndex: anchorIndex,
      headIndex: headIndex,
      headLayerId: headRow,
      spanRows: [
        for (final id in order.sublist(math.min(a, b), math.max(a, b) + 1))
          LayerRowAddress(id),
      ],
    );
  }

  void moveTheRange(EditorSessionManager session, int frameDelta) {
    expect(
      session.rangeMove.beginFrameRangeMoveDrag(transitionRowOf(session)),
      isTrue,
      reason: 'the range holds something to move',
    );
    session.rangeMove.updateFrameRangeMoveDrag(frameDelta: frameDelta);
    session.rangeMove.endFrameRangeMoveDrag();
  }

  group('a range MOVE in the cut', () {
    test('moves the GLOBAL span a fade\'s mark shows, the mark following the '
        'hand on both rails — one undo puts it back', () {
      late final int cutTwo;
      final session = inCutTwoWith((start) {
        cutTwo = start;
        return {start + 2: const InstructionEvent(instructionId: 'fo', length: 3)};
      });
      final row = transitionRowOf(session);
      expect(marks(session), [2], reason: 'premise: drawn where it is');
      selectOnTheRow(session, 2, 4);

      expect(session.rangeMove.beginFrameRangeMoveDrag(row), isTrue);
      session.rangeMove.updateFrameRangeMoveDrag(frameDelta: 3);
      final preview = session.dragPreview.value! as BlockMoveDragPreview;
      expect(preview.previewLayers[row]!.instructions.keys, [5]);
      expect(preview.previewGlobalLayers[row]!.instructions.keys, [cutTwo + 5]);
      session.rangeMove.endFrameRangeMoveDrag();

      expect(spanStarts(session), [cutTwo + 5]);
      session.undo();
      expect(spanStarts(session), [cutTwo + 2]);
    });

    test('an O.L\'s mark stays put — the storyboard\'s to move — while the '
        'fade beside it moves', () {
      late final int cutTwo;
      final session = inCutTwoWith((start) {
        cutTwo = start;
        return {
          start - 4: const InstructionEvent(instructionId: 'ol', length: 8),
          start + 10: const InstructionEvent(instructionId: 'fo', length: 3),
        };
      });
      expect(marks(session), [0, 10], reason: 'premise: both drawn in cut 2');
      selectOnTheRow(session, 0, 12);

      moveTheRange(session, 2);

      expect(spanStarts(session), [cutTwo - 4, cutTwo + 12]);
    });

    test('a fade that began in cut 1 keeps its head there — its mark is '
        'pinned to frame 0 — while the fade after it moves', () {
      late final int cutTwo;
      final session = inCutTwoWith((start) {
        cutTwo = start;
        return {
          start - 2: const InstructionEvent(instructionId: 'fi', length: 5),
          start + 8: const InstructionEvent(instructionId: 'fo', length: 3),
        };
      });
      expect(marks(session), [0, 8], reason: 'premise: the F.I from frame 0');
      selectOnTheRow(session, 0, 10);

      moveTheRange(session, 2);

      expect(spanStarts(session), [cutTwo - 2, cutTwo + 10]);
    });

    test('a drawing block and a fade in one range move together, and ONE '
        'undo returns both', () {
      late final int cutTwo;
      final session = inCutTwoWith((start) {
        cutTwo = start;
        return {start + 3: const InstructionEvent(instructionId: 'fo', length: 3)};
      });
      final drawing = session.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );
      session.selectLayer(drawing.id);
      session.selectFrameIndex(3);
      session.createDrawingAtCurrentFrame();
      Iterable<int> blockStarts() =>
          session.layers.firstWhere((l) => l.id == drawing.id).timeline.keys;
      expect(blockStarts(), [3], reason: 'premise: one block at 3');
      sweepFrom(
        session,
        anchorRow: drawing.id,
        headRow: transitionRowOf(session),
        anchorIndex: 3,
        headIndex: 5,
      );
      expect(
        session.frameRangeSelection.value!.spanLayerIds,
        contains(transitionRowOf(session)),
        reason: 'premise: the range reaches the transition row',
      );

      expect(session.rangeMove.beginFrameRangeMoveDrag(drawing.id), isTrue);
      session.rangeMove.updateFrameRangeMoveDrag(frameDelta: 2);
      session.rangeMove.endFrameRangeMoveDrag();

      expect(blockStarts(), [5]);
      expect(spanStarts(session), [cutTwo + 5]);
      session.undo();
      expect(blockStarts(), [3]);
      expect(spanStarts(session), [cutTwo + 3]);
    });
  });

  group('a range DELETE', () {
    test('in the cut: the spans the marks show — the one that began in cut 1 '
        'included, as a press on its mark takes it', () {
      late final int cutTwo;
      final session = inCutTwoWith((start) {
        cutTwo = start;
        return {
          start - 2: const InstructionEvent(instructionId: 'fi', length: 5),
          start + 8: const InstructionEvent(instructionId: 'fo', length: 3),
        };
      });
      expect(marks(session), [0, 8], reason: 'premise');
      selectOnTheRow(session, 0, 10);
      expect(session.cells.canDeleteCellForSelection, isTrue);

      session.cells.deleteCellAtCurrentFrame();

      expect(spanStarts(session), isEmpty);
      session.undo();
      expect(spanStarts(session), [cutTwo - 2, cutTwo + 8]);
    });

    test('in the cut: never an O.L\'s', () {
      late final int cutTwo;
      final session = inCutTwoWith((start) {
        cutTwo = start;
        return {
          start - 4: const InstructionEvent(instructionId: 'ol', length: 8),
          start + 10: const InstructionEvent(instructionId: 'fo', length: 3),
        };
      });
      selectOnTheRow(session, 0, 12);

      session.cells.deleteCellAtCurrentFrame();

      expect(spanStarts(session), [cutTwo - 4]);
    });

    test('in the cut: a range that does not reach the transition row holds '
        'none of its spans, whatever frames it covers', () {
      final session = inCutTwoWith(
        (start) => {
          start + 2: const InstructionEvent(instructionId: 'fo', length: 3),
        },
      );
      final drawing = session.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );
      session.updateFrameRangeSelectionDrag(
        layerId: drawing.id,
        anchorIndex: 2,
        headIndex: 4,
      );
      expect(
        session.frameRangeSelection.value!.spanLayerIds,
        isNot(contains(transitionRowOf(session))),
        reason: 'premise: the drawing row alone',
      );

      expect(session.cells.canDeleteCellForSelection, isFalse);
      expect(session.rangeMove.beginFrameRangeMoveDrag(drawing.id), isFalse);
    });

    test('in the cut: a range over an O.L alone holds nothing to delete', () {
      final session = inCutTwoWith(
        (start) => {
          start - 4: const InstructionEvent(instructionId: 'ol', length: 8),
        },
      );
      selectOnTheRow(session, 0, 7);

      expect(session.cells.canDeleteCellForSelection, isFalse);
    });

    test('in the cut: blocks and spans go in ONE undo step', () {
      late final int cutTwo;
      final session = inCutTwoWith((start) {
        cutTwo = start;
        return {start + 3: const InstructionEvent(instructionId: 'fo', length: 3)};
      });
      final drawing = session.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );
      session.selectLayer(drawing.id);
      session.selectFrameIndex(3);
      session.createDrawingAtCurrentFrame();
      Layer drawingNow() =>
          session.layers.firstWhere((l) => l.id == drawing.id);
      sweepFrom(
        session,
        anchorRow: drawing.id,
        headRow: transitionRowOf(session),
        anchorIndex: 3,
        headIndex: 5,
      );

      session.cells.deleteCellAtCurrentFrame();

      expect(drawingNow().timeline, isEmpty);
      expect(spanStarts(session), isEmpty);
      session.undo();
      expect(drawingNow().timeline.keys, [3]);
      expect(spanStarts(session), [cutTwo + 3]);
    });

    test('on the storyboard: every span starting in the range, an O.L\'s '
        'too — through the panel\'s Delete, which takes spans, not a cut', () {
      late final int cutTwo;
      final session = inCutTwoWith((start) {
        cutTwo = start;
        return {
          start - 4: const InstructionEvent(instructionId: 'ol', length: 8),
          start + 8: const InstructionEvent(instructionId: 'fo', length: 3),
        };
      });
      List<Object> cutIds() => [
        for (final cut in session.repository.requireProject().tracks.first.cuts)
          cut.id,
      ];
      final cutsBefore = cutIds();
      session.updateTrackRowRangeSelectionByFrame(
        layerId: transitionRowOf(session),
        anchorGlobalFrame: cutTwo - 4,
        headGlobalFrame: cutTwo + 10,
      );
      final panel = StoryboardToolbarPanelContext(session);
      expect(panel.deleteSubject, PillSubject.cells);
      expect(
        session.deleteSubject,
        PillSubject.cells,
        reason: 'the session\'s own ladder, which the panel hands cut ranges',
      );

      panel.deleteSelectionSubject();

      expect(spanStarts(session), isEmpty);
      expect(
        cutIds(),
        cutsBefore,
        reason: 'a range over the transition row names no cut',
      );
      session.undo();
      expect(spanStarts(session), [cutTwo - 4, cutTwo + 8]);
    });

    test('on the storyboard: a band that holds nothing claims the press — '
        'Delete does nothing at all, and never reaches the cursor\'s block '
        'or the cel under the playhead', () {
      late final int cutTwo;
      final session = inCutTwoWith((start) {
        cutTwo = start;
        return {start + 8: const InstructionEvent(instructionId: 'fo', length: 3)};
      });
      // A cel under the playhead, so a press that fell through to the frame
      // axis would have something to take.
      final drawing = session.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );
      session.selectLayer(drawing.id);
      session.selectFrameIndex(2);
      session.createDrawingAtCurrentFrame();
      final panel = StoryboardToolbarPanelContext(session);
      expect(
        panel.deleteSubject,
        PillSubject.cells,
        reason: 'premise: with no band, the cursor\'s block is the subject',
      );
      session.updateTrackRowRangeSelectionByFrame(
        layerId: transitionRowOf(session),
        anchorGlobalFrame: cutTwo + 1,
        headGlobalFrame: cutTwo + 3,
      );
      expect(session.trackFrameRangeSelection.value, isNotNull);
      final before = session.repository.requireProject();

      expect(panel.deleteSubject, PillSubject.nothing);
      panel.deleteSelectionSubject();

      expect(
        identical(session.repository.requireProject(), before),
        isTrue,
        reason: 'nothing was written — no cut, no cel, no span',
      );
    });
  });
}
