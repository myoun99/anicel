import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/brush_edit_session_commit.dart';

void main() {
  group('BrushEditSessionState', () {
    const layerId = LayerId('layer-a');
    const frameId = FrameId('frame-a');

    BitmapSurface surface({int width = 4, int height = 4}) => BitmapSurface(
      canvasSize: CanvasSize(width: width, height: height),
      tileSize: 2,
    );

    BrushDabSequence changedSequence() => BrushDabSequence([
      BrushDab(
        center: CanvasPoint(x: 0.5, y: 0.5),
        color: 0xFFFF0000,
        size: 1,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: 0,
      ),
    ]);

    test('stores canvasState and materializationHistoryState', () {
      final canvasState = CanvasSurfaceState(currentSurface: surface());
      final materializationHistoryState =
          BrushBitmapMaterializationHistoryState();
      final state = BrushEditSessionState(
        canvasState: canvasState,
        materializationHistoryState: materializationHistoryState,
      );

      expect(state.canvasState, canvasState);
      expect(state.materializationHistoryState, materializationHistoryState);
    });

    test('a commit never grows the materialization history (R19 P3b: '
        'undo/redo are app-level surface snapshots)', () {
      final committed = commitBrushDabSequenceToBrushEditSession(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        sequence: changedSequence(),
        layerId: layerId,
        frameId: frameId,
      );
      final state = BrushEditSessionState(
        canvasState: committed.canvasState,
        materializationHistoryState: committed.materializationHistoryState,
      );

      expect(committed.historyEntry, isNotNull, reason: 'dirty-tile carrier');
      expect(state.canUndo, isFalse);
      expect(state.canRedo, isFalse);
    });

    test('hasLastEdit delegates to canvasState.hasLastEdit', () {
      final committed = commitBrushDabSequenceToBrushEditSession(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        sequence: changedSequence(),
        layerId: layerId,
        frameId: frameId,
      );
      final state = BrushEditSessionState(
        canvasState: committed.canvasState,
        materializationHistoryState: committed.materializationHistoryState,
      );

      expect(state.hasLastEdit, committed.canvasState.hasLastEdit);
      expect(state.hasLastEdit, isTrue);
    });

    test('copyWith preserves omitted values', () {
      final state = BrushEditSessionState(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
      );

      expect(state.copyWith(), state);
    });

    test('copyWith updates canvasState', () {
      final state = BrushEditSessionState(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
      );
      final nextCanvas = CanvasSurfaceState(
        currentSurface: surface(width: 8, height: 8),
      );

      expect(state.copyWith(canvasState: nextCanvas).canvasState, nextCanvas);
      expect(
        state.copyWith(canvasState: nextCanvas).materializationHistoryState,
        state.materializationHistoryState,
      );
    });

    test('copyWith updates materializationHistoryState', () {
      final committed = commitBrushDabSequenceToBrushEditSession(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        sequence: changedSequence(),
        layerId: layerId,
        frameId: frameId,
      );
      final state = BrushEditSessionState(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
      );

      expect(
        state
            .copyWith(
              materializationHistoryState:
                  committed.materializationHistoryState,
            )
            .materializationHistoryState,
        committed.materializationHistoryState,
      );
      expect(
        state
            .copyWith(
              materializationHistoryState:
                  committed.materializationHistoryState,
            )
            .canvasState,
        state.canvasState,
      );
    });

    test('equality / hashCode / toString', () {
      final canvasState = CanvasSurfaceState(currentSurface: surface());
      final materializationHistoryState =
          BrushBitmapMaterializationHistoryState();
      final a = BrushEditSessionState(
        canvasState: canvasState,
        materializationHistoryState: materializationHistoryState,
      );
      final b = BrushEditSessionState(
        canvasState: canvasState,
        materializationHistoryState: materializationHistoryState,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('BrushEditSessionState'));
      expect(a.toString(), contains('canvasState'));
      expect(a.toString(), contains('materializationHistoryState'));
    });
  });
}
