import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_entry.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_edit_session_cache_operation_result.dart';
import 'package:anicel/src/models/brush_edit_session_operation_kind.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/cache_invalidation_execution_result.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/brush_edit_session_state_operations.dart';

void main() {
  group('BrushEditSessionCacheOperationResult', () {
    const layerId = LayerId('layer-a');
    const frameId = FrameId('frame-a');

    BrushEditSessionState session() => BrushEditSessionState(
      canvasState: CanvasSurfaceState(
        currentSurface: BitmapSurface(
          canvasSize: CanvasSize(width: 4, height: 4),
          tileSize: 2,
        ),
      ),
      materializationHistoryState: BrushBitmapMaterializationHistoryState(),
    );

    BrushDabSequence sequence() => BrushDabSequence([
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

    BrushBitmapMaterializationHistoryEntry entry() {
      return commitBrushDabSequenceToBrushEditSessionState(
        sessionState: session(),
        sequence: sequence(),
        layerId: layerId,
        frameId: frameId,
      ).historyEntry!;
    }

    CacheInvalidationExecutionResult zeroResult() {
      return CacheInvalidationExecutionResult(
        layerTileCount: 0,
        frameCompositeCount: 0,
        playbackPreviewCount: 0,
      );
    }

    CacheInvalidationExecutionResult nonZeroResult() {
      return CacheInvalidationExecutionResult(
        layerTileCount: 1,
        frameCompositeCount: 2,
        playbackPreviewCount: 3,
      );
    }

    BrushEditSessionCacheOperationResult result({
      BrushEditSessionOperationKind kind = BrushEditSessionOperationKind.commit,
      BrushEditSessionState? sessionState,
      BrushBitmapMaterializationHistoryEntry? affectedEntry,
      CacheInvalidationExecutionResult? cacheInvalidationResult,
    }) {
      return BrushEditSessionCacheOperationResult(
        kind: kind,
        sessionState: sessionState ?? session(),
        affectedEntry: affectedEntry,
        cacheInvalidationResult: cacheInvalidationResult ?? zeroResult(),
      );
    }

    test(
      'stores kind, sessionState, affectedEntry, cacheInvalidationResult',
      () {
        final sessionState = session();
        final affectedEntry = entry();
        final cacheResult = nonZeroResult();
        final value = result(
          kind: BrushEditSessionOperationKind.undo,
          sessionState: sessionState,
          affectedEntry: affectedEntry,
          cacheInvalidationResult: cacheResult,
        );

        expect(value.kind, BrushEditSessionOperationKind.undo);
        expect(value.sessionState, sessionState);
        expect(value.affectedEntry, affectedEntry);
        expect(value.cacheInvalidationResult, cacheResult);
      },
    );

    test('didAffectHistory false when affectedEntry is null', () {
      expect(result().didAffectHistory, isFalse);
    });

    test('didAffectHistory true when affectedEntry is non-null', () {
      expect(result(affectedEntry: entry()).didAffectHistory, isTrue);
    });

    test(
      'didInvalidateCache delegates to cacheInvalidationResult.didInvalidate',
      () {
        expect(
          result(cacheInvalidationResult: zeroResult()).didInvalidateCache,
          isFalse,
        );
        expect(
          result(cacheInvalidationResult: nonZeroResult()).didInvalidateCache,
          isTrue,
        );
      },
    );

    test('copyWith preserves omitted values', () {
      final value = result(
        affectedEntry: entry(),
        cacheInvalidationResult: nonZeroResult(),
      );

      expect(value.copyWith(), value);
    });

    test('copyWith updates kind', () {
      expect(
        result().copyWith(kind: BrushEditSessionOperationKind.redo).kind,
        BrushEditSessionOperationKind.redo,
      );
    });

    test('copyWith updates sessionState', () {
      final newSession = session();

      expect(
        result().copyWith(sessionState: newSession).sessionState,
        newSession,
      );
    });

    test('copyWith can set affectedEntry', () {
      final affectedEntry = entry();

      expect(
        result().copyWith(affectedEntry: affectedEntry).affectedEntry,
        affectedEntry,
      );
    });

    test('copyWith can clear affectedEntry with null', () {
      expect(
        result(
          affectedEntry: entry(),
        ).copyWith(affectedEntry: null).affectedEntry,
        isNull,
      );
    });

    test('copyWith updates cacheInvalidationResult', () {
      final cacheResult = nonZeroResult();

      expect(
        result()
            .copyWith(cacheInvalidationResult: cacheResult)
            .cacheInvalidationResult,
        cacheResult,
      );
    });

    test('equality / hashCode / toString', () {
      final sessionState = session();
      final affectedEntry = entry();
      final cacheResult = nonZeroResult();
      final a = result(
        sessionState: sessionState,
        affectedEntry: affectedEntry,
        cacheInvalidationResult: cacheResult,
      );
      final b = result(
        sessionState: sessionState,
        affectedEntry: affectedEntry,
        cacheInvalidationResult: cacheResult,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('BrushEditSessionCacheOperationResult'));
      expect(a.toString(), contains('affectedEntry'));
    });
  });
}
