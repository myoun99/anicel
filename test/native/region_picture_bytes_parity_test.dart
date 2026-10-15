import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/ui/canvas/surface_region_picture.dart';

import '../helpers/native_engine_path.dart';

/// A region's picture bytes premultiplied by the engine — every tile it
/// covers laid out of its own memory by `qa_premultiply_rgba_rows` (ABI 46)
/// into the engine's scratch — are the Dart road's: the straight region
/// premultiplied where it lies. The upload reads the first; the test
/// runner's door never does, so only this can see them.
void main() {
  final dllPath = nativeEngineLibraryPathOrNull();

  setUp(() {
    QaNativeEngine.debugResetForTests();
    QaNativeEngine.debugForceDartFallback = false;
    debugQaEngineLibraryPathOverride = dllPath;
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    QaNativeEngine.debugForceDartFallback = false;
    debugQaEngineLibraryPathOverride = null;
  });

  bool engineMissing() {
    if (dllPath != null && QaNativeEngine.instance != null) {
      return false;
    }
    if (nativeEngineRequired) {
      fail(nativeEngineMissingSkipReason);
    }
    markTestSkipped(nativeEngineMissingSkipReason);
    return true;
  }

  const size = 16;

  /// Every alpha regime, and colour under alpha 0 — straight bytes the
  /// premultiply must clear.
  BitmapTile tileOf(int seed) => BitmapTile(
    size: size,
    pixels: Uint8List.fromList([
      for (var index = 0; index < size * size; index += 1) ...[
        (index * 7 + seed * 31) & 0xFF,
        (index * 13 + seed) & 0xFF,
        (index * 29 + seed * 5) & 0xFF,
        (index * 5 + seed * 3) % 256,
      ],
    ]),
  );

  final surface = BitmapSurface(
    canvasSize: const CanvasSize(width: 64, height: 64),
    tileSize: size,
    tiles: {
      TileCoord(x: 0, y: 0): tileOf(1),
      TileCoord(x: 1, y: 0): tileOf(2),
      TileCoord(x: 0, y: 1): tileOf(3),
      TileCoord(x: 2, y: 2): tileOf(4),
      TileCoord(x: -1, y: -1): tileOf(5),
    },
  );

  Uint8List premultiplied(DirtyRegion region) => SurfaceRegionBytes(
    surface,
    region,
  ).readPremultiplied(Uint8List.fromList);

  Uint8List onDart(DirtyRegion region) {
    QaNativeEngine.debugForceDartFallback = true;
    try {
      return premultiplied(region);
    } finally {
      QaNativeEngine.debugForceDartFallback = false;
    }
  }

  test('the engine lays a region the way Dart does: whole tiles, a tile '
      'held in part, the pasteboard\'s, and the gaps between', () {
    if (engineMissing()) {
      return;
    }
    expect(QaNativeEngine.instance, isNotNull);
    expect(kQaEngineAbiVersion, greaterThanOrEqualTo(46));
    final regions = [
      // Two whole tiles: no gap.
      DirtyRegion(left: 0, top: 0, rightExclusive: 32, bottomExclusive: 16),
      // A block with a gap (tile 1,1 is absent) and a lone tile.
      DirtyRegion(left: 0, top: 0, rightExclusive: 48, bottomExclusive: 48),
      // Cut through tiles on every side, the pasteboard's among them.
      DirtyRegion(left: -9, top: -5, rightExclusive: 21, bottomExclusive: 27),
    ];
    for (final region in regions) {
      final dart = onDart(region);
      expect(dart.any((byte) => byte != 0), isTrue, reason: 'fixture');
      expect(premultiplied(region), dart, reason: '$region');
    }
  });

  test('the scratch keeps the last picture, and a gap is cleared of it', () {
    if (engineMissing()) {
      return;
    }
    // Whole: the scratch is filled with ink.
    final whole = DirtyRegion(
      left: 0,
      top: 0,
      rightExclusive: 32,
      bottomExclusive: 32,
    );
    expect(premultiplied(whole), onDart(whole));
    // The same size over a gap: what the last picture left must not show.
    final gapped = DirtyRegion(
      left: 16,
      top: 16,
      rightExclusive: 48,
      bottomExclusive: 48,
    );
    final bytes = premultiplied(gapped);
    expect(bytes, onDart(gapped));
    expect(bytes.sublist(0, 16 * 4), everyElement(0), reason: 'tile 1,1');
  });
}
