@Tags(['benchmark'])
library;

import 'package:flutter_test/flutter_test.dart';

import '../helpers/a_canvas_standing_on_a_frame.dart';
import '../helpers/a_fill_on_the_engine.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
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
import 'package:anicel/src/services/canvas_flood_fill.dart';

/// R21 fill verdict bench (user report: fill still slow at 2340×1654):
/// the whole tap — the frame's picture and its flood on the engine, the
/// range cut into stamp pieces, their commit — timed per stage at the
/// user's canvas size. Prints FILL2340 lines, each tap twice: its first
/// compiles the flood's kernels, its second is the tap a user repeats. Run
/// with `--dart-define=BRUSH_LAB_PROFILE=true` for the inner probes too.
void main() {
  opensTheEnginesScreens();

  test(
    'fill tap staged timings at 2340x1654',
    () {
      const canvasSize = CanvasSize(width: 2340, height: 1654);
      const key = BrushFrameKey(
        projectId: ProjectId('p'),
        trackId: TrackId('t'),
        cutId: CutId('c'),
        layerId: LayerId('ink'),
        frameId: FrameId('f'),
      );

      // Ink: a big box outline 40px from the edges — the fill floods the
      // interior (~3.6MP), the realistic "paint the cel" tap.
      const black = [0, 0, 0, 255];
      final picture = fillPictureOfRows([
        fillRow(
          celOfPixels(canvasSize, {
            for (var x = 40; x < canvasSize.width - 40; x += 1) ...{
              (x, 40): black,
              (x, canvasSize.height - 41): black,
            },
            for (var y = 40; y < canvasSize.height - 40; y += 1) ...{
              (40, y): black,
              (canvasSize.width - 41, y): black,
            },
          }),
        ),
      ], canvasSize: canvasSize);

      for (final gapClose in [0, 4]) {
        for (final tap in ['first', 'again']) {
          final floodWatch = Stopwatch()..start();
          final range = fillRangeAt(
            canvasSize: canvasSize,
            pictureOver: picture,
            point: CanvasPoint(
              x: canvasSize.width / 2,
              y: canvasSize.height / 2,
            ),
            options: FloodFillOptions(gapClosePx: gapClose),
          );
          floodWatch.stop();
          final piecesWatch = Stopwatch()..start();
          final dabs = range?.dabsIn(0xFF3366CC) ?? const [];
          piecesWatch.stop();

          final coordinator = BrushFrameEditingCoordinator(
            initialFrameKey: key,
            frameStore: BrushFrameStore(),
            sessionStore: BrushFrameEditSessionStore(
              canvasSize: canvasSize,
              tileSize: 256,
            ),
            historyPolicy: const BrushHistoryPolicy(),
          );
          final commitWatch = Stopwatch()..start();
          coordinator.commitSourceStroke(sourceDabs: dabs);
          commitWatch.stop();

          // ignore: avoid_print
          print(
            'FILL2340 gapClose=$gapClose $tap '
            'flood=${floodWatch.elapsedMilliseconds}ms '
            'pieces=${piecesWatch.elapsedMilliseconds}ms '
            'commit=${commitWatch.elapsedMilliseconds}ms '
            'count=${dabs.length}',
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
