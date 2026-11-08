import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_ops.dart';

import '../helpers/a_shown_surface.dart';

/// The frame grid's tiles reach a view's screen through the package's Dart
/// (grid-on-the-engine ④): a tile the tile pass draws ([GpuGrid.draw]) —
/// its letters read from the atlas it is handed — is
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

  /// A tile [width] × [height] of [fills] — (x, y, w, h, colour) each.
  GpuGridPicture aTile(
    int width,
    int height,
    List<(int, int, int, int, Color)> fills,
  ) {
    final picture = GpuGridPicture(appGpuEngine, width, height);
    addTearDown(picture.free);
    final ops = TimelineGridTileOpWriter();
    for (final (x, y, w, h, colour) in fills) {
      ops.fillRect(x, y, w, h, timelineGridPackRgba(colour));
    }
    grid.draw(picture, ops.build());
    return picture;
  }

  test('each lay takes its part of its tile onto its part of the screen', () {
    // (200, 100, 50) at 128 over the left two columns, red over the right.
    final tile = aTile(3, 2, [
      (0, 0, 2, 2, const Color(0x80C86432)),
      (2, 0, 1, 2, const Color(0xFFFF0000)),
    ]);
    final green = aTile(1, 1, [(0, 0, 1, 1, const Color(0xFF00FF00))]);
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
    put(3, 1, red);
    put(3, 2, red);
    put(0, 3, [0, 255, 0, 255]);

    lay.lay(surface, (0, 0, 5, 4), [
      (picture: tile, from: (0, 0, 3, 2), onto: (1, 1, 4, 3)),
      (picture: green, from: (0, 0, 1, 1), onto: (0, 3, 1, 4)),
    ]);

    expect(surface.fingerprint(), fingerprintBytes(want));
  });

  test('a tile reads its letters from the atlas it is handed', () {
    final tile = GpuGridPicture(appGpuEngine, 1, 2);
    addTearDown(tile.free);
    // 2 × 3: a letter of 255 over 128 down its last column, below its top
    // row — so an atlas read a side for the other has no such letter.
    final ops = TimelineGridTileOpWriter()
      ..glyph(0, 0, 1, 1, 1, 2, timelineGridPackRgba(const Color(0xFFFFFFFF)));
    grid.draw(
      tile,
      ops.build(),
      atlas: (
        alpha: Uint8List.fromList([0, 0, 0, 255, 0, 128]),
        width: 2,
        height: 3,
      ),
    );
    final surface = shownSurfaceOf(1, 2);
    addTearDown(surface.free);

    lay.lay(surface, (0, 0, 1, 2), [
      (picture: tile, from: (0, 0, 1, 2), onto: (0, 0, 1, 2)),
    ]);

    // White at 255 and at 128, premultiplied.
    expect(
      surface.fingerprint(),
      fingerprintBytes(
        Uint8List.fromList([255, 255, 255, 255, 128, 128, 128, 128]),
      ),
    );
  });

  test('an atlas its bytes do not match is refused before it is read', () {
    final tile = GpuGridPicture(appGpuEngine, 1, 1);
    addTearDown(tile.free);

    for (final length in [5, 7]) {
      expect(
        () => grid.draw(
          tile,
          Int32List(0),
          atlas: (alpha: Uint8List(length), width: 3, height: 2),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            'an atlas 3 × 2 of $length bytes',
          ),
        ),
      );
    }
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
