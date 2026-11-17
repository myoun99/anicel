// Each scene's first stroke compiles the executor and the stroke's kernels
// on an engine of its own — the one before it lost its device.
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuRefused;

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/services/import/clip_vector_raster.dart';

import 'clip_test_builder.dart';

/// 🚨A vector layer whose device goes as its picture lands fails the
/// import whole, told as the device's refusal ([clipVectorTiles]) — the end
/// a layer refused at its first stroke has, which the app answers by
/// opening another engine (`EngineRefusals`).
///
/// ↩️브러시 measured it otherwise (main PC, 2026-11-13, board
/// `a-vector-layer-read-as-its-device-goes-opens-blank`): a tile one stroke
/// painted read back as nothing, and the layer opened empty with no word;
/// one a stroke had lain over threw a bare [StateError], which is no
/// refusal. Those two were measured where the picture was read back to be
/// cut; it lands where it lies now (card
/// a-clip-vector-layer-is-read-back-to-be-tiled-again, 2026-11-16), and the
/// device goes as it is about to ([debugBeforeTheLayerLands]). On the app's
/// own engine, which each scene loses: the next opens another.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The app's grid: a 64 × 64 canvas is one tile of it.
  const canvas = (
    left: 0,
    top: 0,
    wall: PasteboardWall(
      CanvasSize(width: 64, height: 64),
      PasteboardReach.none,
    ),
    alpha: 1.0,
    tileSize: 128,
  );

  late int lost;

  setUp(() {
    lost = 0;
    debugBeforeTheLayerLands = () {
      lost += 1;
      appGpuEngine.debugLose();
    };
    addTearDown(() {
      debugBeforeTheLayerLands = null;
      // No test leaves the app on a device that is gone.
      letTheGoneAppGpuEngineGo();
    });
  });

  test('a layer whose tile one stroke painted is refused — not opened '
      'empty', () async {
    await expectLater(
      clipVectorTiles(
        [
          vectorStrokeBytes([(10, 20, 1), (50, 20, 1)], radius: 3),
        ],
        (x: 0, y: 0),
        canvas,
      ),
      throwsA(isA<GpuRefused>()),
    );
    expect(lost, 1, reason: '⛔premise: it went as the picture landed');
  });

  test('a layer with a tile one stroke lay over another\'s is refused — '
      'not failed by a bare StateError', () async {
    await expectLater(
      clipVectorTiles(
        [
          vectorStrokeBytes([(10, 20, 1), (50, 20, 1)], radius: 3),
          vectorStrokeBytes([(30, 5, 1), (30, 50, 1)], radius: 3),
        ],
        (x: 0, y: 0),
        canvas,
      ),
      throwsA(isA<GpuRefused>()),
    );
    expect(lost, 1, reason: '⛔premise: it went as the picture landed');
  });
}
