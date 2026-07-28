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
import 'package:anicel/src/services/brush_edit_session_state_operations.dart';

/// The session-state commit facade (R19 P3b: undo/redo retired from the
/// session — the commit is the only session-state operation left).
void main() {
  group('brush edit session state operations', () {
    const layerId = LayerId('layer-a');
    const frameId = FrameId('frame-a');

    BitmapSurface surface() => BitmapSurface(
      canvasSize: const CanvasSize(width: 4, height: 4),
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

    BrushEditSessionState emptySession() => BrushEditSessionState(
      canvasState: CanvasSurfaceState(currentSurface: surface()),
      materializationHistoryState: BrushBitmapMaterializationHistoryState(),
    );

    test('commit facade returns same result as '
        'commitBrushDabSequenceToBrushEditSession', () {
      final sessionState = emptySession();
      final sequence = changedSequence();
      final direct = commitBrushDabSequenceToBrushEditSession(
        canvasState: sessionState.canvasState,
        materializationHistoryState: sessionState.materializationHistoryState,
        sequence: sequence,
        layerId: layerId,
        frameId: frameId,
      );
      final facade = commitBrushDabSequenceToBrushEditSessionState(
        sessionState: sessionState,
        sequence: sequence,
        layerId: layerId,
        frameId: frameId,
      );

      expect(facade, direct);
    });

    test('commit facade no-op behavior matches existing commit service', () {
      final sessionState = emptySession();
      final direct = commitBrushDabSequenceToBrushEditSession(
        canvasState: sessionState.canvasState,
        materializationHistoryState: sessionState.materializationHistoryState,
        sequence: BrushDabSequence(),
        layerId: layerId,
        frameId: frameId,
      );
      final facade = commitBrushDabSequenceToBrushEditSessionState(
        sessionState: sessionState,
        sequence: BrushDabSequence(),
        layerId: layerId,
        frameId: frameId,
      );

      expect(facade, direct);
      expect(facade.didCommit, isFalse);
    });

    test('a changed commit lands pixels and carries its entry WITHOUT '
        'growing any session history (R19 P3b)', () {
      final sessionState = emptySession();
      final facade = commitBrushDabSequenceToBrushEditSessionState(
        sessionState: sessionState,
        sequence: changedSequence(),
        layerId: layerId,
        frameId: frameId,
      );

      expect(facade.didCommit, isTrue);
      expect(facade.historyEntry, isNotNull, reason: 'dirty-tile carrier');
      expect(facade.materializationHistoryState.undoEntries, isEmpty);
      expect(facade.canvasState.hasLastEdit, isTrue);
    });

    test('sessionStateFromCommitResult wraps the result fields', () {
      final committed = commitBrushDabSequenceToBrushEditSessionState(
        sessionState: emptySession(),
        sequence: changedSequence(),
        layerId: layerId,
        frameId: frameId,
      );
      final state = sessionStateFromCommitResult(committed);

      expect(state.canvasState, committed.canvasState);
      expect(
        state.materializationHistoryState,
        committed.materializationHistoryState,
      );
    });
  });
}
