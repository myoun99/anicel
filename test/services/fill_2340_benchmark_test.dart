@Tags(['benchmark'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/native_engine_path.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';

/// R21 fill verdict bench (user report: fill still slow at 2340×1654):
/// the whole tap — lazy raster → flood → finish → stamp build → commit —
/// timed per stage at the user's canvas size, with the native engine
/// loaded. Prints FILL2340 lines; run with
/// `--dart-define=BRUSH_LAB_PROFILE=true` for the inner probes too.
void main() {
  // R26/2A: resolved per platform (and via QA_ENGINE_PATH on CI) so this
  // benchmark can run wherever an engine was built.
  final dllPath = nativeEngineLibraryPathOrNull();
  final available = dllPath != null;

  setUp(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  test(
    'fill tap staged timings at 2340x1654',
    () {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      const canvasSize = CanvasSize(width: 2340, height: 1654);
      const key = BrushFrameKey(
        projectId: ProjectId('p'),
        trackId: TrackId('t'),
        cutId: CutId('c'),
        layerId: LayerId('ink'),
        frameId: FrameId('f'),
      );

      // Ink surface: a big box outline 40px from the edges — the fill
      // floods the interior (~3.6MP), the realistic "paint the cel" tap.
      final rowBytes = <TileCoord, Uint8List>{};
      void inkFast(int x, int y) {
        final coord = TileCoord(x: x ~/ 256, y: y ~/ 256);
        final buffer = rowBytes.putIfAbsent(
          coord,
          () => Uint8List(256 * 256 * 4),
        );
        buffer[((y % 256) * 256 + (x % 256)) * 4 + 3] = 255;
      }

      for (var x = 40; x < canvasSize.width - 40; x += 1) {
        inkFast(x, 40);
        inkFast(x, canvasSize.height - 41);
      }
      for (var y = 40; y < canvasSize.height - 40; y += 1) {
        inkFast(40, y);
        inkFast(canvasSize.width - 41, y);
      }
      final surface = BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 256,
        tiles: {
          for (final entry in rowBytes.entries)
            entry.key: BitmapTile(
              coord: entry.key,
              size: 256,
              pixels: entry.value,
            ),
        },
      );
      final layer = Layer(
        id: const LayerId('ink'),
        name: 'Ink',
        frames: [Frame(id: const FrameId('f'), duration: 1, strokes: const [])],
        timeline: {0: TimelineExposure.drawing(const FrameId('f'), length: 1)},
      );
      final cut = Cut(
        id: const CutId('c'),
        name: 'Cut',
        layers: [layer],
        duration: 24,
        canvasSize: canvasSize,
      );

      for (final gapClose in [0, 4]) {
        final tapWatch = Stopwatch()..start();
        final dab = buildFillDab(
          cut: cut,
          frameIndex: 0,
          surfaceResolver: (_, _) => surface,
          point: CanvasPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
          color: 0xFF3366CC,
          options: FloodFillOptions(gapClosePx: gapClose),
        )!;
        tapWatch.stop();

        final coordinator = BrushFrameEditingCoordinator(
          initialFrameKey: key,
          frameStore: BrushFrameStore(),
          sessionStore: BrushFrameEditSessionStore(
            canvasSize: canvasSize,
            tileSize: 256,
          ),
          historyPolicy: const BrushHistoryPolicy(
            userUndoLimit: 8,
            deferredBakeRatio: 0,
          ),
        );
        final commitWatch = Stopwatch()..start();
        coordinator.commitSourceStroke(sourceDabs: [dab]);
        commitWatch.stop();

        // ignore: avoid_print
        print(
          'FILL2340 gapClose=$gapClose tap=${tapWatch.elapsedMilliseconds}ms '
          'commit=${commitWatch.elapsedMilliseconds}ms '
          'stamp=${dab.stamp!.width}x${dab.stamp!.height}',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
