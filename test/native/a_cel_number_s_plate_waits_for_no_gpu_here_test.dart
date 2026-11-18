import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_number_letters.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';

import '../helpers/engine_screen_pins.dart';

/// 🚨★A CEL NUMBER'S PLATE IS THE ENGINE'S TILES, MADE WITH NO WAIT FOR THE
/// GPU ON THE THREAD THAT ASKS (the-ui-thread-never-enters-the-driver B1-c,
/// 2026-11-15): the engine's raster of the letters lands in the pool's
/// slots, as a stroke's result does (`EngineTileLedger.land`). ↩️It was
/// read back to bytes and stored again — 🔬on the Surface Pro 11, 351–425
/// ms of this isolate at its longest, waiting for what the GPU had queued
/// before it (`EngineLetters`). What the plate shows the walk's pins say
/// (the_engine_lays_a_tree_as_the_walk_paints_it_test.dart).
void main() {
  // The letters read their faces from the bundle.
  TestWidgetsFlutterBinding.ensureInitialized();
  final engine = EngineScreenPins('a cel number\'s plate waits for no GPU');
  final row = BitmapSurface(
    canvasSize: const CanvasSize(width: 256, height: 128),
    tileSize: gpuTileSide,
    tiles: const {},
  );
  CelNumberLetters lettersOf(String text) => CelNumberLetters(
    text: text,
    color: 0xFF203040,
    center: CanvasPoint(x: 120, y: 60),
    scale: CanvasPoint(x: 1, y: 1),
  );

  test('🚨a plate is made with no wait for the GPU here, of tiles the engine '
      'alone holds', () {
    final letters = lettersOf('A12');
    final waits = debugWaitsHere;

    final plate = engine.letters.celNumberPlate(letters, row);

    expect(debugWaitsHere, waits, reason: 'a wait for the GPU here');
    expect(plate.tiles, isNotEmpty, reason: 'LIVENESS: its letters cover');
    expect(
      plate.tiles.values.where((tile) => !tile.isOnlyOnEngine),
      isEmpty,
      reason: 'a tile whose bytes are here',
    );
  });

  // Its letters are covered here and its picture laid on the engine's
  // thread, in its turn (the-ui-thread-never-enters-the-driver,
  // 2026-11-18): ↩️both were that thread's while this one waited — 🔬the
  // test VM, a band filled again after a stroke (k921), 17 plates, 58 to
  // 97 ms each, nearly all of it the wait for what was handed it before.
  test('🚨a plate is made while the engine\'s thread stands still — it waits '
      'for no turn there', () {
    // ⛔premise: the pages a plate lands on made — a page is made on the
    // engine's thread, which stands still below.
    engine.letters.celNumberPlate(lettersOf('B1'), row);
    appGpuEngine.debugStandStill(const Duration(seconds: 2));
    final asked = Stopwatch()..start();

    final plate = engine.letters.celNumberPlate(lettersOf('B2'), row);

    expect(
      asked.elapsed,
      lessThan(const Duration(seconds: 1)),
      reason: 'a wait for the engine\'s thread',
    );
    expect(plate.tiles, isNotEmpty, reason: 'LIVENESS: its letters cover');
  });

  // ⚠️Last: a device that is gone is gone for its process.
  test('a plate whose picture the engine did not put is made again where '
      'it is next asked for — its tiles hold no letters', () async {
    final kept = engine.letters.celNumberPlate(lettersOf('C1'), row);
    await pumpEventQueue();
    expect(
      engine.letters.celNumberPlate(lettersOf('C1'), row),
      same(kept),
      reason: '⛔premise: a plate put is kept',
    );
    // Gone at once, as wgpu says it of a device it gave up for want of
    // memory: a loss told at the next wait would come after the plate.
    appGpuEngine.debugLose(forMemory: true);

    final unput = engine.letters.celNumberPlate(lettersOf('C2'), row);
    await pumpEventQueue();

    expect(unput.tiles, isNotEmpty, reason: '⛔premise: its slots told');
    expect(
      engine.letters.celNumberPlate(lettersOf('C2'), row),
      isNot(same(unput)),
    );
    expect(
      engine.letters.celNumberPlate(lettersOf('C1'), row),
      same(kept),
      reason: 'a plate put is not forgotten with it',
    );
  });
}
