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

  group('🎯through its mask, as Photoshop\'s is baked (보드 the-clip-import-'
      'leaves-masks-and-locks-unsaid)', () {
    /// A one-byte mask of [width] × [height] standing at ([left], [top]):
    /// [coverage] in its one block — or no block stored — and [fill] past
    /// its edges.
    ClipStoredMask mask({
      required int left,
      required int top,
      int width = 64,
      int height = 64,
      int fill = 1,
      int Function(int x, int y)? coverage,
      int colourChannels = 0,
    }) {
      final block = Uint8List(256 * 256);
      if (coverage != null) {
        for (var y = 0; y < 256; y += 1) {
          for (var x = 0; x < 256; x += 1) {
            block[y * 256 + x] = coverage(x, y);
          }
        }
      }
      return (
        attribute: offscreenAttributeBytes(
          width: width,
          height: height,
          columns: 1,
          rows: 1,
          colourChannels: colourChannels,
          fill: fill,
        ),
        blocks: blockRecordsBytes({0: coverage == null ? null : block}),
        left: left,
        top: top,
      );
    }

    /// [picture] standing at (4, 6), baked through [mask].
    List<ClipCelTile>? bakeThrough(ClipStoredMask mask) {
      final stored = picture();
      return clipCelTiles(
        stored.attribute,
        stored.blocks,
        (
          left: 4,
          top: 6,
          canvasWidth: 300,
          canvasHeight: 200,
          alpha: 1,
          tileSize: 128,
        ),
        mask: mask,
      );
    }

    test('its alpha times the mask where the mask stands on the canvas — '
        'and past the mask\'s edges, the mask\'s fill', () {
      final tiles = bakeThrough(
        mask(left: 10, top: 20, coverage: (x, y) => x < 32 ? 0 : 128),
      )!;

      expect(
        pixelAt(tiles, 12, 25),
        [0, 0, 0, 0],
        reason: 'the mask\'s (2, 5) hides it',
      );
      expect(
        pixelAt(tiles, 50, 30),
        [46, 24, 7, 128],
        reason: 'the mask\'s (40, 10) halves it — picture 46, 24',
      );
      expect(
        pixelAt(tiles, 8, 8),
        [4, 2, 7, 255],
        reason: 'left of the mask its fill shows all',
      );
      expect(pixelAt(tiles, 80, 30), [76, 24, 7, 255], reason: 'right of it');
    });

    test('a mask wider than it is tall stops at its own last row', () {
      final tiles = bakeThrough(
        mask(left: 10, top: 20, height: 16, coverage: (x, y) => 128),
      )!;

      expect(
        pixelAt(tiles, 50, 30),
        [46, 24, 7, 128],
        reason: 'the mask\'s (40, 10) halves it',
      );
      expect(
        pixelAt(tiles, 50, 40),
        [46, 34, 7, 255],
        reason: 'the mask\'s 16 rows end above it — its fill shows all',
      );
    });

    test('where it stores no block it is its fill — 0 hides everything', () {
      expect(bakeThrough(mask(left: 0, top: 0, fill: 0)), isEmpty);
      expect(
        pixelAt(bakeThrough(mask(left: 0, top: 0))!, 20, 20),
        [16, 14, 7, 255],
      );
    });

    test('one that is not one byte a pixel is not baked', () {
      expect(
        pixelAt(
          bakeThrough(mask(left: 0, top: 0, fill: 0, colourChannels: 4))!,
          20,
          20,
        ),
        [16, 14, 7, 255],
      );
    });

    group('as the engine lays a picture under it (clipMaskPlaneOver) — a '
        'vector layer\'s, which lands where it lies', () {
      const within = (left: 0, top: 0, right: 128, bottom: 128);

      /// The byte at canvas pixel (x, y) of [plane], or none past it.
      int? byteAt(ClipMaskPlane plane, int x, int y) {
        final (dx, dy) = (x - plane.left, y - plane.top);
        if (dx < 0 || dy < 0 || dx >= plane.width || dy >= plane.height) {
          return null;
        }
        return plane.bytes[dy * plane.width + dx];
      }

      test('one that hides what lies past it is its own box, as it is', () {
        final plane = clipMaskPlaneOver(
          mask(left: 10, top: 20, fill: 0, coverage: (x, y) => x),
          within,
        )!;

        expect(
          (plane.left, plane.top, plane.width, plane.height),
          (10, 20, 64, 64),
        );
        expect(byteAt(plane, 15, 21), 5);
        expect(byteAt(plane, 9, 21), isNull, reason: 'read as nothing');
      });

      test('one that shows what lies past it spans where the picture '
          'stands: its bytes where they lie, the rest whole', () {
        final plane = clipMaskPlaneOver(
          mask(left: 10, top: 20, coverage: (x, y) => x < 32 ? 0 : 128),
          within,
        )!;

        expect(
          (plane.left, plane.top, plane.width, plane.height),
          (0, 0, 128, 128),
        );
        expect(byteAt(plane, 12, 25), 0, reason: 'the mask\'s (2, 5)');
        expect(byteAt(plane, 50, 30), 128, reason: 'the mask\'s (40, 10)');
        expect(byteAt(plane, 8, 8), 255, reason: 'left of the mask');
        expect(byteAt(plane, 80, 30), 255, reason: 'right of it');
        expect(byteAt(plane, 40, 100), 255, reason: 'below it');
      });

      test('of a mask that stands partly past where the picture does, the '
          'part where it does; of one that stands wholly past, none', () {
        final part = clipMaskPlaneOver(
          mask(left: -20, top: -10, coverage: (x, y) => x + y),
          within,
        )!;
        expect(byteAt(part, 0, 0), 30, reason: 'the mask\'s (20, 10)');
        expect(byteAt(part, 43, 53), 126, reason: 'the mask\'s (63, 63)');
        expect(byteAt(part, 44, 20), 255, reason: 'right of it');

        final past = clipMaskPlaneOver(
          mask(left: 200, top: 0, coverage: (x, y) => 0),
          within,
        )!;
        expect(past.bytes.every((byte) => byte == 255), isTrue);
      });

      test('none of one that is not one byte a pixel', () {
        expect(
          clipMaskPlaneOver(
            mask(left: 0, top: 0, colourChannels: 4),
            within,
          ),
          isNull,
        );
      });
    });

    group('which mask a layer\'s picture is baked through', () {
      final oneByte = ClipPictureSource(
        attribute: offscreenAttributeBytes(
          width: 4,
          height: 4,
          columns: 1,
          rows: 1,
          colourChannels: 0,
        ),
        blocksId: 'm',
      );

      ClipLayer layer(ClipLayerKind kind, ClipLayerMask? mask) => ClipLayer(
        id: 1,
        name: 'masked',
        kind: kind,
        visibility: 3,
        opacity: 256,
        composite: 0,
        folderFlags: kind == ClipLayerKind.folder ? 1 : 0,
        isAnimationFolder: false,
        uuid: 'u',
        left: 0,
        top: 0,
        offsetX: 0,
        offsetY: 0,
        render: null,
        original: null,
        originalTransform: null,
        mask: mask,
        children: const [],
      );

      test('a stored picture\'s — a raster layer\'s, a dropped picture\'s '
          '— and a vector layer\'s, where it stands; no other layer bakes '
          'a picture through one', () {
        final mask = (source: oneByte, left: 3, top: -2);
        expect(
          {
            for (final kind in ClipLayerKind.values)
              kind: clipBakedMaskOf(layer(kind, mask)) != null,
          },
          {
            for (final kind in ClipLayerKind.values)
              kind:
                  kind == ClipLayerKind.raster ||
                  kind == ClipLayerKind.picture ||
                  kind == ClipLayerKind.vector,
          },
        );
        final baked = clipBakedMaskOf(layer(ClipLayerKind.raster, mask))!;
        expect(
          (baked.source, baked.left, baked.top),
          (oneByte, 3, -2),
        );
      });

      test('none for a layer with none on, one the file holds no picture '
          'of, and one that is not one byte a pixel', () {
        final colour = ClipPictureSource(
          attribute: offscreenAttributeBytes(
            width: 4,
            height: 4,
            columns: 1,
            rows: 1,
          ),
          blocksId: 'c',
        );
        for (final mask in <ClipLayerMask?>[
          null,
          (source: null, left: 0, top: 0),
          (source: colour, left: 0, top: 0),
          (
            source: ClipPictureSource(attribute: Uint8List(3), blocksId: 'b'),
            left: 0,
            top: 0,
          ),
        ]) {
          expect(
            clipBakedMaskOf(layer(ClipLayerKind.raster, mask)),
            isNull,
            reason: '$mask',
          );
        }
      });
    });
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

    test('🎯a dropped picture declares a render the file never stores — its '
        'ORIGINAL is the picture (「A / 1: 그림을 읽지 못했습니다」, 10-09: '
        'all 22 of the samples\' picture layers)', () {
      final declared = ClipPictureSource(
        attribute: Uint8List(1),
        blocksId: 'never stored',
      );
      final picture = clipPictureOf(
        layer(
          render: declared,
          original: source,
          transform: transform(placed: (110, 60), axis: (100, 50)),
        ),
      )!;
      expect(
        (picture.source, picture.left, picture.top),
        (source, 3 + 10, 4 + 10),
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
