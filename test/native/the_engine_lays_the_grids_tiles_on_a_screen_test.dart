import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_ops.dart';

import '../helpers/a_shown_surface.dart';

/// The frame grid's tiles reach a view's screen through the package's Dart
/// (grid-on-the-engine ④): a tile the tile pass draws ([GpuGrid.draw]) is
/// laid ([GpuGridLay.lay]) from the part of it each lay names onto the part
/// of the screen it names, premultiplied, the rest of the rect clear. How a
/// lay lands on pixels between whole ones is the crate's to pin
/// (rust/src/kernels/timeline/grid/lay_tests.rs) — here, what Dart hands it.
void main() {
  late GpuGrid grid;
  late GpuGridLay lay;
  const red = [255, 0, 0, 255];

  setUpAll(() {
    grid = GpuGrid(appGpuEngine);
    lay = GpuGridLay(appGpuEngine);
  });
  tearDownAll(() {
    lay.free();
    grid.free();
  });

  /// A 3 × 2 tile: (200, 100, 50) at 128 over its left two columns, red
  /// over its right one.
  GpuGridPicture aTile() {
    final picture = GpuGridPicture(appGpuEngine, 3, 2);
    addTearDown(picture.free);
    final ops = TimelineGridTileOpWriter()
      ..fillRect(0, 0, 2, 2, timelineGridPackRgba(const Color(0x80C86432)))
      ..fillRect(2, 0, 1, 2, timelineGridPackRgba(const Color(0xFFFF0000)));
    grid.draw(picture, ops.build(), const []);
    return picture;
  }

  test('each lay takes its part of its tile onto its part of the screen', () {
    final tile = aTile();
    final surface = shownSurfaceOf(5, 4);
    addTearDown(surface.free);
    final want = Uint8List(5 * 4 * 4);
    void put(int x, int y, List<int> rgba) {
      final [r, g, b, a] = rgba;
      want.setAll(
        (y * 5 + x) * 4,
        surface.bgra ? [b, g, r, a] : [r, g, b, a],
      );
    }

    // (200, 100, 50) at 128, premultiplied as premultiply.wgsl rounds.
    for (final (x, y) in [(1, 1), (2, 1), (1, 2), (2, 2)]) {
      put(x, y, [100, 50, 25, 128]);
    }
    for (final (x, y) in [(3, 1), (3, 2), (0, 3)]) {
      put(x, y, red);
    }

    lay.lay(surface, (0, 0, 5, 4), [
      (picture: tile, from: (0, 0, 3, 2), onto: (1, 1, 4, 3)),
      (picture: tile, from: (2, 0, 3, 1), onto: (0, 3, 1, 4)),
    ]);

    expect(surface.fingerprint(), fingerprintBytes(want));
  });

  test('a lay past its screen is refused with why', () {
    final surface = shownSurfaceOf(5, 4);
    addTearDown(surface.free);

    expect(
      () => lay.lay(surface, (0, 0, 6, 4), const []),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('is no rectangle of a 5 × 4 screen'),
        ),
      ),
    );
  });
}
