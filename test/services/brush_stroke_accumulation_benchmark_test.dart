@Tags(['benchmark'])
library;

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
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/commands/brush_stroke_history_command.dart';
import 'package:anicel/src/services/history_manager.dart';

/// Accumulation microbenchmark (not a correctness test): commits many
/// consecutive strokes through the PRODUCTION wiring (HistoryManager →
/// BrushStrokeHistoryCommand → coordinator, pre-rasterized fast path) and
/// prints the per-stroke commit cost per bucket plus the structures that
/// grow with stroke count — so "draws fine, then gradually lags" is
/// measured, not guessed.
void main() {
  const canvasSize = CanvasSize(width: 2340, height: 1654);
  const frameKey = BrushFrameKey(
    projectId: ProjectId('bench-project'),
    trackId: TrackId('bench-track'),
    cutId: CutId('bench-cut'),
    layerId: LayerId('bench-layer'),
    frameId: FrameId('bench-frame'),
  );

  /// A ~30-dab 60px stroke whose position walks the canvas so consecutive
  /// strokes touch different tiles (like real sketching).
  List<BrushDab> strokeDabs(int strokeIndex) {
    final originX = 120.0 + (strokeIndex * 97) % (canvasSize.width - 500);
    final originY = 120.0 + (strokeIndex * 61) % (canvasSize.height - 500);
    return [
      for (var index = 0; index < 30; index += 1)
        BrushDab(
          center: CanvasPoint(
            x: originX + index * 9.0,
            y: originY + index * 5.0,
          ),
          color: 0xE6224488,
          size: 60,
          opacity: 0.85,
          flow: 0.7,
          hardness: 0.3,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: index,
        ),
    ];
  }

  test(
    'per-stroke commit cost and retained state as strokes accumulate',
    () {
      final store = BrushFrameStore();
      final coordinator = BrushFrameEditingCoordinator(
        initialFrameKey: frameKey,
        frameStore: store,
        sessionStore: BrushFrameEditSessionStore(canvasSize: canvasSize),
        // The main canvas host's production policy.
        historyPolicy: const BrushHistoryPolicy(
          userUndoLimit: 24,
          deferredBakeRatio: 0,
        ),
      );
      final historyManager = HistoryManager();
      final commands = <BrushStrokeHistoryCommand>[];

      const strokesPerBucket = 100;
      const buckets = 6;
      for (var bucket = 0; bucket < buckets; bucket += 1) {
        final watch = Stopwatch();
        for (var s = 0; s < strokesPerBucket; s += 1) {
          final strokeIndex = bucket * strokesPerBucket + s;
          final dabs = strokeDabs(strokeIndex);
          // The live rasterization happens WHILE drawing; only the pen-up
          // commit is timed.
          final rasterizer = BrushLiveStrokeRasterizer(canvasSize: canvasSize)
            ..blendFrom(dabs);
          final data = BrushStrokeCommitData(
            sourceDabs: dabs,
            strokePixels: rasterizer.strokePixelsWithinBounds(),
            strokeBounds: rasterizer.strokeBounds,
          );
          final command = BrushStrokeHistoryCommand(
            coordinator: coordinator,
            strokeData: data,
          );
          commands.add(command);
          watch.start();
          historyManager.execute(command);
          watch.stop();
        }

        // ignore: avoid_print
        print(
          '[accumulation] strokes ${(bucket + 1) * strokesPerBucket}: '
          '${(watch.elapsedMicroseconds / 1000.0 / strokesPerBucket).toStringAsFixed(2)}'
          'ms/commit | undo snapshot bytes '
          '~${(historyManager.retainedBytes / (1024 * 1024)).toStringAsFixed(0)}MB | '
          'app undo stack ${historyManager.undoCount}',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
