import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/import/clip_cel_raster.dart';
import 'package:anicel/src/services/import/clip_document.dart';

import 'clip_test_builder.dart';

/// A CLIP STUDIO picture as the app's cel tiles (card
/// `csp-clip-import-analysis`): straight RGBA in canvas place, what falls
/// off the canvas dropped, a fainter cel's alpha baked, and a dropped
/// picture placed where its transform puts it.
void main() {
  /// A colour picture of two blocks side by side: red counts the picture's
  /// x, green its y.
  ({Uint8List attribute, Uint8List blocks}) picture({
    int width = 300,
    int height = 200,
    int alpha = 255,
  }) => (
    attribute: offscreenAttributeBytes(
      width: width,
      height: height,
      columns: 2,
      rows: 1,
    ),
    blocks: blockRecordsBytes({
      for (final n in [0, 1])
        n: colourBlock((x, y) => ((n * 256 + x) & 0xff, y & 0xff, 7, alpha)),
    }),
  );

  /// The RGBA [tiles] put at canvas ([x], [y]), or null when no tile holds
  /// that pixel.
  List<int>? pixelAt(List<ClipCelTile> tiles, int x, int y) {
    for (final tile in tiles) {
      if (tile.x == x ~/ 128 && tile.y == y ~/ 128) {
        final at = ((y % 128) * 128 + x % 128) * 4;
        return tile.pixels.sublist(at, at + 4);
      }
    }
    return null;
  }
  /// [stored] baked at ([left], [top]) on a [width] × [height] canvas, in
  /// tiles of 128.
  List<ClipCelTile>? bake(
    ({Uint8List attribute, Uint8List blocks}) stored, {
    int left = 0,
    int top = 0,
    int width = 300,
    int height = 200,
    double alpha = 1,
  }) => clipCelTiles(stored.attribute, stored.blocks, (
    left: left,
    top: top,
    canvasWidth: width,
    canvasHeight: height,
    alpha: alpha,
    tileSize: 128,
  ));

  test('🎯the picture lands where it stands, the part off the canvas '
      'dropped, in tiles of the cel\'s size', () {
    final tiles = bake(
      picture(),
      left: -20,
      top: 250,
      width: 256,
      height: 300,
    )!;

    expect(
      {for (final tile in tiles) (tile.x, tile.y)},
      {(0, 1), (1, 1), (0, 2), (1, 2)},
      reason: 'rows 250 … 299 and columns 0 … 255 — the canvas\'s part only',
    );
    expect(pixelAt(tiles, 5, 260), [25, 10, 7, 255], reason: 'picture 25, 10');
    expect(
      pixelAt(tiles, 255, 299),
      [275 & 0xff, 49, 7, 255],
      reason: 'the second block, red past 255 wrapping as it was drawn',
    );
    expect(
      pixelAt(tiles, 5, 249),
      [0, 0, 0, 0],
      reason: 'above the picture the tile is empty',
    );
  });

  test('a picture standing more than a tile off the canvas\'s left edge '
      'makes no tile out there', () {
    final tiles = bake(picture(), left: -200)!;

    expect(
      {for (final tile in tiles) tile.x},
      {0},
      reason: 'its last 100 columns are on the canvas; nothing left of 0',
    );
    expect(pixelAt(tiles, 0, 5), [200, 5, 7, 255], reason: 'picture 200, 5');
  });

  test('a fainter cel is baked fainter, and a tile with no ink is not '
      'there', () {
    expect(pixelAt(bake(picture(), alpha: 0.5)!, 10, 10), [10, 10, 7, 128]);
    expect(bake(picture(alpha: 0)), isEmpty);
  });

  test('a picture that is not colour is not turned into colour', () {
    expect(
      bake((
        attribute: offscreenAttributeBytes(
          width: 10,
          height: 10,
          columns: 1,
          rows: 1,
          colourChannels: 0,
        ),
        blocks: blockRecordsBytes({0: null}),
      )),
      isNull,
    );
  });

  group('where a stored picture stands', () {
    final source = ClipPictureSource(attribute: Uint8List(1), blocksId: 'x');

    ClipLayer layer({
      ClipPictureSource? render,
      ClipPictureSource? original,
      Uint8List? transform,
    }) => ClipLayer(
      id: 1,
      name: 'scan',
      kind: original == null ? ClipLayerKind.raster : ClipLayerKind.picture,
      visibility: 1,
      opacity: 256,
      composite: 0,
      folderFlags: 0,
      isAnimationFolder: false,
      uuid: 'u',
      left: 40,
      top: 50,
      offsetX: 3,
      offsetY: 4,
      render: render,
      original: original,
      originalTransform: transform,
      children: const [],
    );

    /// A `ResizableImageInfo`: scale, turn, the point placed at, and the
    /// point in the picture that goes there.
    Uint8List transform({
      double scaleX = 1,
      double scaleY = 1,
      double degrees = 0,
      required (double, double) placed,
      required (double, double) axis,
    }) {
      final data = ByteData(184)
        ..setFloat64(40, scaleX)
        ..setFloat64(48, scaleY)
        ..setFloat64(56, degrees)
        ..setFloat64(64, placed.$1)
        ..setFloat64(72, placed.$2)
        ..setFloat64(80, axis.$1)
        ..setFloat64(88, axis.$2);
      return data.buffer.asUint8List();
    }

    test('a render stands where the layer stands', () {
      final picture = clipPictureOf(layer(render: source))!;
      expect(
        (picture.source, picture.left, picture.top, picture.moveOnly),
        (source, 40, 50, true),
      );
    });

    test('🎯a dropped picture\'s original goes where its transform takes its '
        'top-left, from the layer\'s own offset', () {
      final picture = clipPictureOf(
        layer(
          original: source,
          transform: transform(placed: (110, 60), axis: (100, 50)),
        ),
      )!;
      expect(
        (picture.source, picture.left, picture.top, picture.moveOnly),
        (source, 3 + 10, 4 + 10, true),
      );
    });

    test('a scale or a turn is said not drawn — the move still is', () {
      for (final turned in [
        transform(scaleX: 2, placed: (0, 0), axis: (0, 0)),
        transform(degrees: 30, placed: (0, 0), axis: (0, 0)),
      ]) {
        final picture = clipPictureOf(
          layer(original: source, transform: turned),
        )!;
        expect(picture.moveOnly, isFalse);
      }
    });

    test('a layer that stores no picture has none', () {
      expect(clipPictureOf(layer()), isNull);
    });
  });
}
