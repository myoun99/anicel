import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_tile_cache_key.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/commands/brush_stroke_history_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';

/// Accumulation regression guards (R8-B): every per-stroke structure the
/// brush stack retains must stay BOUNDED as strokes pile up — "draws fine,
/// then gradually lags" was heap ballooning from exactly these lists, not
/// per-dab blend cost (see brush_stroke_accumulation_benchmark_test.dart
/// for the measured curve).
void main() {
  group('brush stroke accumulation stays bounded', () {
    test('the SESSION retains zero per-stroke history — undo weight lives '
        'only on the app stack as surface snapshots (R19 P3b)', () {
      final coordinator = _coordinator(userUndoLimit: 8);
      for (var stroke = 0; stroke < 40; stroke += 1) {
        coordinator.commitSourceStroke(sourceDabs: [_dab(stroke % 6)]);
      }

      expect(
        coordinator.activeSessionState.materializationHistoryState.undoEntries,
        isEmpty,
        reason:
            'commits never push session history anymore — 40 strokes '
            'retain nothing in the session beyond the current surface',
      );
    });

    test('the app history command drops its one-shot commit payload after '
        'the first execute', () {
      final coordinator = _coordinator(userUndoLimit: 8);
      final history = HistoryManager();
      final command = BrushStrokeHistoryCommand(
        coordinator: coordinator,
        strokeData: BrushStrokeCommitData(sourceDabs: [_dab(0), _dab(1)]),
      );
      expect(command.retainsCommitPayload, isTrue);

      history.execute(command);
      expect(
        command.retainsCommitPayload,
        isFalse,
        reason:
            'the stroke pixel buffer is megabytes and the command sits on '
            'the app undo stack for the session — retaining it accumulated '
            'hundreds of MB over a drawing run',
      );

      // Undo/redo keep working through the surface snapshots without it.
      history.undo();
      expect(
        coordinator.frameStore.celHasRenderableContent(
          coordinator.activeFrameKey,
        ),
        isFalse,
      );
      history.redo();
      expect(
        coordinator.frameStore.celHasRenderableContent(
          coordinator.activeFrameKey,
        ),
        isTrue,
      );
    });

    test('the app undo stack is depth-capped (oldest fall off)', () {
      final history = HistoryManager(maxEntries: 3);
      final log = <String>[];
      for (var index = 0; index < 6; index += 1) {
        history.execute(_ProbeCommand(index, log));
      }
      expect(history.undoCount, 3);

      history.undo();
      history.undo();
      history.undo();
      expect(history.canUndo, isFalse);
      expect(log, [
        'execute 0',
        'execute 1',
        'execute 2',
        'execute 3',
        'execute 4',
        'execute 5',
        'undo 5',
        'undo 4',
        'undo 3',
      ]);
    });

    test('the standalone recorder sink bounds its key log', () {
      final sink = BrushEditCacheInvalidationSink();
      final overflow = BrushEditCacheInvalidationSink.maxRecordedKeys + 50;
      for (var index = 0; index < overflow; index += 1) {
        sink.invalidateLayerTile(
          LayerTileCacheKey(
            layerId: const LayerId('layer'),
            frameId: const FrameId('frame'),
            tileCoord: TileCoord(x: index, y: 0),
          ),
        );
      }
      expect(
        sink.layerTiles.length,
        BrushEditCacheInvalidationSink.maxRecordedKeys,
      );
      // Newest keys win.
      expect(sink.layerTiles.last.tileCoord.x, overflow - 1);
    });
  });
}

class _ProbeCommand implements Command {
  _ProbeCommand(this.index, this.log);

  final int index;
  final List<String> log;

  @override
  String get description => 'probe $index';

  @override
  void execute() => log.add('execute $index');

  @override
  void undo() => log.add('undo $index');
}

BrushFrameEditingCoordinator _coordinator({required int userUndoLimit}) {
  final key = BrushFrameKey(
    projectId: const ProjectId('project'),
    trackId: const TrackId('track'),
    cutId: const CutId('cut'),
    layerId: const LayerId('layer'),
    frameId: const FrameId('frame'),
  );
  return BrushFrameEditingCoordinator(
    initialFrameKey: key,
    frameStore: BrushFrameStore(),
    sessionStore: BrushFrameEditSessionStore(
      canvasSize: const CanvasSize(width: 8, height: 8),
    ),
    historyPolicy: BrushHistoryPolicy(
      userUndoLimit: userUndoLimit,
      deferredBakeRatio: 0,
    ),
  );
}

BrushDab _dab(int sequence) {
  return BrushDab(
    // Pixel-center coordinates: the commit rasterizer samples pixel centers,
    // so a size-1 dab must sit on x.5 to paint (WYSIWYG semantics).
    center: CanvasPoint(x: sequence + 0.5, y: sequence + 0.5),
    color: 0xFF000000,
    size: 1,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
  );
}
