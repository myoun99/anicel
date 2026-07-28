import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_entry.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_edit_session_commit_result.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/brush_bitmap_materialization_history_entry_builder.dart';
import 'package:anicel/src/services/brush_surface_edit_builder.dart';

void main() {
  group('BrushEditSessionCommitResult', () {
    const layerId = LayerId('layer-a');
    const frameId = FrameId('frame-a');

    BitmapSurface surface({int width = 4, int height = 4}) => BitmapSurface(
      canvasSize: CanvasSize(width: width, height: height),
      tileSize: 2,
    );

    BrushDab dab() => BrushDab(
      center: CanvasPoint(x: 0.5, y: 0.5),
      color: 0xFFFF0000,
      size: 1,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.round,
      pressure: 1,
      sequence: 0,
    );

    BrushBitmapMaterializationHistoryEntry entry() {
      final edit = brushSurfaceEditForBrushDabSequenceOnBitmapSurface(
        surface: surface(),
        sequence: BrushDabSequence([dab()]),
        layerId: layerId,
        frameId: frameId,
      );
      return brushBitmapMaterializationHistoryEntryFromBrushSurfaceEdit(
        edit: edit,
        layerId: layerId,
        frameId: frameId,
      )!;
    }

    test('stores canvasState, materializationHistoryState, historyEntry', () {
      final canvasState = CanvasSurfaceState(currentSurface: surface());
      final materializationHistoryState =
          BrushBitmapMaterializationHistoryState();
      final historyEntry = entry();
      final result = BrushEditSessionCommitResult(
        canvasState: canvasState,
        materializationHistoryState: materializationHistoryState,
        historyEntry: historyEntry,
      );

      expect(result.canvasState, canvasState);
      expect(result.materializationHistoryState, materializationHistoryState);
      expect(result.historyEntry, historyEntry);
    });

    test('didCommit false when historyEntry is null', () {
      final result = BrushEditSessionCommitResult(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        historyEntry: null,
      );

      expect(result.didCommit, isFalse);
    });

    test('didCommit true when historyEntry is non-null', () {
      final result = BrushEditSessionCommitResult(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        historyEntry: entry(),
      );

      expect(result.didCommit, isTrue);
    });

    test('copyWith preserves omitted values', () {
      final result = BrushEditSessionCommitResult(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        historyEntry: entry(),
      );

      expect(result.copyWith(), result);
    });

    test('copyWith updates canvasState', () {
      final result = BrushEditSessionCommitResult(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        historyEntry: null,
      );
      final nextCanvas = CanvasSurfaceState(
        currentSurface: surface(width: 8, height: 8),
      );

      expect(result.copyWith(canvasState: nextCanvas).canvasState, nextCanvas);
    });

    test('copyWith updates materializationHistoryState', () {
      final result = BrushEditSessionCommitResult(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        historyEntry: null,
      );
      final nextHistory = BrushBitmapMaterializationHistoryState(
        undoEntries: [entry()],
      );

      expect(
        result
            .copyWith(materializationHistoryState: nextHistory)
            .materializationHistoryState,
        nextHistory,
      );
    });

    test('copyWith can set historyEntry', () {
      final result = BrushEditSessionCommitResult(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        historyEntry: null,
      );
      final historyEntry = entry();

      expect(
        result.copyWith(historyEntry: historyEntry).historyEntry,
        historyEntry,
      );
    });

    test('copyWith can clear historyEntry with null', () {
      final result = BrushEditSessionCommitResult(
        canvasState: CanvasSurfaceState(currentSurface: surface()),
        materializationHistoryState: BrushBitmapMaterializationHistoryState(),
        historyEntry: entry(),
      );

      expect(result.copyWith(historyEntry: null).historyEntry, isNull);
    });

    test('equality / hashCode / toString', () {
      final canvasState = CanvasSurfaceState(currentSurface: surface());
      final historyEntry = entry();
      final materializationHistoryState =
          BrushBitmapMaterializationHistoryState(undoEntries: [historyEntry]);
      final a = BrushEditSessionCommitResult(
        canvasState: canvasState,
        materializationHistoryState: materializationHistoryState,
        historyEntry: historyEntry,
      );
      final b = BrushEditSessionCommitResult(
        canvasState: canvasState,
        materializationHistoryState: materializationHistoryState,
        historyEntry: historyEntry,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('BrushEditSessionCommitResult'));
      expect(a.toString(), contains('historyEntry'));
    });
  });
}
