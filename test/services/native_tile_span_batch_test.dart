import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/native_engine_path.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/native_tile_span_batch.dart';

/// The span batch (round 8 of the audit): every native landing — generic
/// dab, stamp, stroke blend — stages one span per covered tile through
/// this, so the walk order the changed flags are read back in is written
/// once.
void main() {
  final dllPath = nativeEngineLibraryPathOrNull();
  late QaNativeEngine engine;

  setUp(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
    final loaded = QaNativeEngine.instance;
    if (loaded == null) {
      if (nativeEngineRequired) {
        fail(nativeEngineMissingSkipReason);
      }
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    engine = loaded;
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  if (dllPath == null) {
    test(
      'needs the engine',
      () => markTestSkipped(nativeEngineMissingSkipReason),
    );
    return;
  }

  test('stages one span per covered tile, ROW-MAJOR, asking pointerFor '
      'exactly once per span in that order', () {
    const tileSize = 4;
    final asked = <TileCoord>[];
    final scratch = calloc<Uint8>(tileSize * tileSize * 4);
    addTearDown(() => calloc.free(scratch));
    // (-1, 2)..(6, 5) on a 4-grid: tiles x -1..1, y 0..1 — six spans.
    final coords = stageTileSpans(
      engine,
      clip: DirtyRegion(
        left: -1,
        top: 2,
        rightExclusive: 6,
        bottomExclusive: 5,
      ),
      tileSize: tileSize,
      pointerFor: (coord) {
        asked.add(coord);
        return scratch;
      },
    );
    final expected = [
      TileCoord(x: -1, y: 0),
      TileCoord(x: 0, y: 0),
      TileCoord(x: 1, y: 0),
      TileCoord(x: -1, y: 1),
      TileCoord(x: 0, y: 1),
      TileCoord(x: 1, y: 1),
    ];
    expect(coords, expected);
    expect(asked, expected, reason: 'once per span, in span order');
  });

  test('a rect inside one tile is one span', () {
    final scratch = calloc<Uint8>(16 * 16 * 4);
    addTearDown(() => calloc.free(scratch));
    expect(
      stageTileSpans(
        engine,
        clip: DirtyRegion(
          left: 17,
          top: 20,
          rightExclusive: 30,
          bottomExclusive: 31,
        ),
        tileSize: 16,
        pointerFor: (_) => scratch,
      ),
      [TileCoord(x: 1, y: 1)],
    );
  });

  test('each span is the tile clipped to the rect — an opaque stamp blend '
      'through the batch touches exactly those pixels', () {
    const tileSize = 4;
    const byteLength = tileSize * tileSize * 4;
    // Two tiles side by side, both zeroed.
    final tiles = <TileCoord, Pointer<Uint8>>{
      TileCoord(x: 0, y: 0): calloc<Uint8>(byteLength),
      TileCoord(x: 1, y: 0): calloc<Uint8>(byteLength),
    };
    addTearDown(() {
      for (final pointer in tiles.values) {
        calloc.free(pointer);
      }
    });
    // An opaque 4×2 white stamp at (2, 1): pixels x 2..5, y 1..2 — the
    // right half of tile 0 and the left half of tile 1.
    final stamp = Uint8List(4 * 2 * 4)..fillRange(0, 4 * 2 * 4, 0xFF);
    final upload = engine.uploadStampBytes(stamp);
    final coords = stageTileSpans(
      engine,
      clip: DirtyRegion(left: 2, top: 1, rightExclusive: 6, bottomExclusive: 3),
      tileSize: tileSize,
      pointerFor: (coord) => tiles[coord]!,
    );
    final changed = engine.stampBlendTiles(
      count: coords.length,
      tileSize: tileSize,
      stampBytes: upload,
      stampWidth: 4,
      stampLeft: 2,
      stampTop: 1,
      opacity: 1,
      erase: false,
    );
    expect(changedTileCoords(changed, coords), coords);
    for (final entry in tiles.entries) {
      final pixels = entry.value.asTypedList(byteLength);
      final tileLeft = entry.key.x * tileSize;
      for (var y = 0; y < tileSize; y += 1) {
        for (var x = 0; x < tileSize; x += 1) {
          final worldX = tileLeft + x;
          final inside = worldX >= 2 && worldX < 6 && y >= 1 && y < 3;
          expect(
            pixels[(y * tileSize + x) * 4 + 3],
            inside ? 0xFF : 0,
            reason: 'tile ${entry.key} pixel ($x, $y)',
          );
        }
      }
    }
  });

  test('changedTileCoords keeps the coordinates whose flag is set, in '
      'batch order', () {
    final coords = [
      TileCoord(x: 0, y: 0),
      TileCoord(x: 1, y: 0),
      TileCoord(x: 0, y: 1),
    ];
    expect(changedTileCoords(Uint8List.fromList([1, 0, 1]), coords), [
      coords[0],
      coords[2],
    ]);
    expect(changedTileCoords(Uint8List.fromList([0, 0, 0]), coords), isEmpty);
  });
}
