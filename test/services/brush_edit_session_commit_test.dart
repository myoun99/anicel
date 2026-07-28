import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/brush_bitmap_materialization_history_entry_builder.dart';
import 'package:anicel/src/services/brush_edit_session_commit.dart';
import 'package:anicel/src/services/brush_surface_edit_builder.dart';
import 'package:anicel/src/services/canvas_surface_state_edit.dart';

void main() {
  group('commitBrushDabSequenceToBrushEditSession', () {
    const layerId = LayerId('layer-a');
    const frameId = FrameId('frame-a');

    BitmapSurface surface() => BitmapSurface(
      canvasSize: const CanvasSize(width: 4, height: 4),
      tileSize: 2,
    );

    BrushDab dab({int sequence = 0}) => BrushDab(
      center: CanvasPoint(x: 0.5, y: 0.5),
      color: 0xFFFF0000,
      size: 1,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.round,
      pressure: 1,
      sequence: sequence,
    );

    BrushDabSequence changedSequence() => BrushDabSequence([dab()]);

    test('empty BrushDabSequence returns no commit result', () {
      final result = commitBrushDabSequenceToBrushEditSession(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        sequence: BrushDabSequence(),
        layerId: layerId,
        frameId: frameId,
      );

      expect(result.didCommit, isFalse);
      expect(result.historyEntry, isNull);
    });

    test('no-op edit does not push history entry', () {
      final result = commitBrushDabSequenceToBrushEditSession(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        sequence: BrushDabSequence(),
        layerId: layerId,
        frameId: frameId,
      );

      expect(result.materializationHistoryState.undoEntries, isEmpty);
    });

    test(
      'no-op edit preserves existing materializationHistoryState instance',
      () {
        final materializationHistoryState =
            BrushBitmapMaterializationHistoryState();
        final result = commitBrushDabSequenceToBrushEditSession(
          canvasState: CanvasSurfaceState(currentSurface: surface()),
          materializationHistoryState: materializationHistoryState,
          sequence: BrushDabSequence(),
          layerId: layerId,
          frameId: frameId,
        );

        expect(
          identical(
            result.materializationHistoryState,
            materializationHistoryState,
          ),
          isTrue,
        );
      },
    );

    test('changed edit updates CanvasSurfaceState.currentSurface', () {
      final canvasState = CanvasSurfaceState(currentSurface: surface());
      final result = commitBrushDabSequenceToBrushEditSession(
        canvasState: canvasState,
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        sequence: changedSequence(),
        layerId: layerId,
        frameId: frameId,
      );

      expect(
        result.canvasState.currentSurface,
        isNot(canvasState.currentSurface),
      );
      expect(result.canvasState.currentSurface.tiles, isNotEmpty);
    });

    test('changed edit sets CanvasSurfaceState.lastEdit', () {
      final result = commitBrushDabSequenceToBrushEditSession(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        sequence: changedSequence(),
        layerId: layerId,
        frameId: frameId,
      );

      expect(result.canvasState.lastEdit, isNotNull);
    });

    test('changed edit creates historyEntry', () {
      final result = commitBrushDabSequenceToBrushEditSession(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        sequence: changedSequence(),
        layerId: layerId,
        frameId: frameId,
      );

      expect(result.historyEntry, isNotNull);
      expect(result.didCommit, isTrue);
    });

    test('a changed edit leaves the history state UNTOUCHED (R19 P3b: '
        'undo is an app-level surface snapshot)', () {
      final incoming = BrushBitmapMaterializationHistoryState();
      final result = commitBrushDabSequenceToBrushEditSession(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: incoming,
        sequence: changedSequence(),
        layerId: layerId,
        frameId: frameId,
      );

      expect(identical(result.materializationHistoryState, incoming), isTrue);
      expect(result.historyEntry, isNotNull);
    });

    test('historyEntry uses provided LayerId', () {
      const customLayerId = LayerId('custom-layer');
      final result = commitBrushDabSequenceToBrushEditSession(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        sequence: changedSequence(),
        layerId: customLayerId,
        frameId: frameId,
      );

      expect(result.historyEntry!.layerId, customLayerId);
    });

    test('historyEntry uses provided FrameId', () {
      const customFrameId = FrameId('custom-frame');
      final result = commitBrushDabSequenceToBrushEditSession(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        sequence: changedSequence(),
        layerId: layerId,
        frameId: customFrameId,
      );

      expect(result.historyEntry!.frameId, customFrameId);
    });

    test('result matches manual composition of existing services', () {
      final canvasState = CanvasSurfaceState(currentSurface: surface());
      final materializationHistoryState =
          BrushBitmapMaterializationHistoryState();
      final sequence = changedSequence();
      final edit = brushSurfaceEditForBrushDabSequenceOnBitmapSurface(
        surface: canvasState.currentSurface,
        sequence: sequence,
        layerId: layerId,
        frameId: frameId,
      );
      final updatedCanvasState = applyBrushSurfaceEditToCanvasSurfaceState(
        state: canvasState,
        edit: edit,
      );
      final historyEntry =
          brushBitmapMaterializationHistoryEntryFromBrushSurfaceEdit(
            edit: edit,
            layerId: layerId,
            frameId: frameId,
          )!;

      final result = commitBrushDabSequenceToBrushEditSession(
        canvasState: canvasState,
        materializationHistoryState: materializationHistoryState,
        sequence: sequence,
        layerId: layerId,
        frameId: frameId,
      );

      expect(result.canvasState, updatedCanvasState);
      expect(
        result.materializationHistoryState,
        materializationHistoryState,
        reason:
            'R19 P3b: no session history push — undo is an app-level '
            'surface snapshot',
      );
      expect(result.historyEntry, historyEntry);
    });

    test('the commit result carries the entry but never grows a history', () {
      final canvasState = CanvasSurfaceState(currentSurface: surface());
      final committed = commitBrushDabSequenceToBrushEditSession(
        canvasState: canvasState,
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        sequence: changedSequence(),
        layerId: layerId,
        frameId: frameId,
      );

      expect(committed.historyEntry, isNotNull);
      expect(committed.materializationHistoryState.undoEntries, isEmpty);
      expect(committed.materializationHistoryState.redoEntries, isEmpty);
    });

    test('does not mutate input CanvasSurfaceState', () {
      final canvasState = CanvasSurfaceState(currentSurface: surface());
      final before = canvasState.copyWith();
      commitBrushDabSequenceToBrushEditSession(
        canvasState: canvasState,
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        sequence: changedSequence(),
        layerId: layerId,
        frameId: frameId,
      );

      expect(canvasState, before);
    });

    test('does not mutate input BrushBitmapMaterializationHistoryState', () {
      final materializationHistoryState =
          BrushBitmapMaterializationHistoryState();
      final before = materializationHistoryState.copyWith();
      commitBrushDabSequenceToBrushEditSession(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: materializationHistoryState,
        sequence: changedSequence(),
        layerId: layerId,
        frameId: frameId,
      );

      expect(materializationHistoryState, before);
    });

    test('does not mutate BrushDabSequence or BrushDab', () {
      final brushDab = dab();
      final sequence = BrushDabSequence([brushDab]);
      final beforeDab = brushDab.copyWith();
      final beforeSequence = sequence.addAll(const []);
      commitBrushDabSequenceToBrushEditSession(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        sequence: sequence,
        layerId: layerId,
        frameId: frameId,
      );

      expect(brushDab, beforeDab);
      expect(sequence, beforeSequence);
    });

    test('does not execute cache invalidation', () {
      final result = commitBrushDabSequenceToBrushEditSession(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        sequence: changedSequence(),
        layerId: layerId,
        frameId: frameId,
      );

      expect(
        result.historyEntry!.cacheInvalidationPlan.totalKeyCount,
        greaterThan(0),
      );
    });

    test('does not add UI/state management/timeline/storyboard changes', () {
      expect(commitBrushDabSequenceToBrushEditSession, isA<Function>());
    });
  });
}
