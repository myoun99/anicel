@Tags(['benchmark'])
library;

import 'dart:io';

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

/// CROSS-CEL accumulation microbenchmark (not a correctness test): an
/// animation working session draws on many different cels, and the
/// single-cel benchmark can never see what accumulates PER CEL. Commits a
/// dozen strokes on each of dozens of cels through the production wiring
/// and prints, per bucket: commit cost, live session count and process RSS
/// — the memory curve behind "the longer I draw, the slower the whole app
/// gets".
void main() {
  const canvasSize = CanvasSize(width: 2340, height: 1654);

  BrushFrameKey celKey(int index) => BrushFrameKey(
    projectId: const ProjectId('bench-project'),
    trackId: const TrackId('bench-track'),
    cutId: const CutId('bench-cut'),
    layerId: const LayerId('bench-layer'),
    frameId: FrameId('bench-frame-$index'),
  );

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
    'per-stroke cost, session count and RSS as CELS accumulate',
    () {
      final store = BrushFrameStore();
      final sessionStore = BrushFrameEditSessionStore(canvasSize: canvasSize);
      final coordinator = BrushFrameEditingCoordinator(
        initialFrameKey: celKey(0),
        frameStore: store,
        sessionStore: sessionStore,
        historyPolicy: const BrushHistoryPolicy(
          userUndoLimit: 24,
          deferredBakeRatio: 0,
        ),
      );
      final historyManager = HistoryManager();

      const celsPerBucket = 8;
      const buckets = 5;
      const strokesPerCel = 12;
      var strokeIndex = 0;

      for (var bucket = 0; bucket < buckets; bucket += 1) {
        final watch = Stopwatch();
        for (var c = 0; c < celsPerBucket; c += 1) {
          final cel = bucket * celsPerBucket + c;
          coordinator.selectFrame(celKey(cel));
          for (var s = 0; s < strokesPerCel; s += 1) {
            final dabs = strokeDabs(strokeIndex++);
            final rasterizer = BrushLiveStrokeRasterizer(canvasSize: canvasSize)
              ..blendFrom(dabs);
            final data = BrushStrokeCommitData(
              sourceDabs: dabs,
              strokePixels: rasterizer.strokePixelsWithinBounds(),
              strokeBounds: rasterizer.strokeBounds,
            );
            watch.start();
            historyManager.execute(
              BrushStrokeHistoryCommand(
                coordinator: coordinator,
                strokeData: data,
              ),
            );
            watch.stop();
          }
        }

        // ignore: avoid_print
        print(
          '[cross-cel] cels ${(bucket + 1) * celsPerBucket} '
          '(${(bucket + 1) * celsPerBucket * strokesPerCel} strokes): '
          '${(watch.elapsedMicroseconds / 1000.0 / (celsPerBucket * strokesPerCel)).toStringAsFixed(2)}ms/commit '
          '| live sessions ${sessionStore.sessionCount} '
          '| rss ${(ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(0)}MB',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
