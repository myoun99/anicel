import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_number_letters.dart';

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

  test('🚨a plate is made with no wait for the GPU here, of tiles the engine '
      'alone holds', () {
    final row = BitmapSurface(
      canvasSize: const CanvasSize(width: 256, height: 128),
      tileSize: gpuTileSide,
      tiles: const {},
    );
    final letters = CelNumberLetters(
      text: 'A12',
      color: 0xFF203040,
      center: CanvasPoint(x: 120, y: 60),
      scale: CanvasPoint(x: 1, y: 1),
    );
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
}
