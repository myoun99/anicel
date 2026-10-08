import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/import/clip_cel_raster.dart';
import 'package:anicel/src/services/import/clip_container.dart'
    show ClipFormatException;
import 'package:anicel/src/services/import/clip_vector_raster.dart';

import 'clip_test_builder.dart';

/// A vector layer's strokes, read and drawn (card `csp-clip-import-analysis`
/// — 6-1 item 8: 「벡터 레이어는 래스터로 그려 넣는다」; 유저 10-07 「벡터같은
/// 불가능한건 냅두거나 래스터라이즈시켜서」). The one sample with vectors
/// stores a render beside them with no blocks in the file, so the strokes
/// ARE the picture.
void main() {
  Uint8List body(List<Uint8List> records) =>
      (BytesBuilder()..add([for (final record in records) ...record]))
          .toBytes();

  group('reading', () {
    test('a body is its strokes end to end — the colour, the opacity, and a '
        'width of radius × factor across, under either head', () {
      final read = parseClipVectorBody(
        body([
          vectorStrokeBytes(
            [(1, 2, 1), (3, 4, 0.5)],
            colour: (200, 100, 50),
            opacity: 0.75,
            radius: 3,
            head: 88,
          ),
          vectorStrokeBytes([(5, 6, 2)], radius: 1.5),
        ]),
      );

      expect(read.unread, 0);
      expect(read.strokes, hasLength(2));
      final (first, second) = (read.strokes[0], read.strokes[1]);
      expect(first.color, 0xFFC86432);
      expect(first.opacity, 0.75);
      expect(first.points, [
        (x: 1.0, y: 2.0, width: 6.0),
        (x: 3.0, y: 4.0, width: 3.0),
      ]);
      expect(second.color, 0xFF000000);
      expect(second.points, [(x: 5.0, y: 6.0, width: 6.0)]);
    });

    test('a curve tool\'s point bends toward its control point on its way '
        'to the next, the width going from one end\'s to the other\'s', () {
      final read = parseClipVectorBody(
        vectorStrokeBytes(
          [(0, 0, 1), (40, 0, 3)],
          bends: [(20, 20), null],
        ),
      );

      final points = read.strokes.single.points;
      expect(points.first, (x: 0.0, y: 0.0, width: 4.0));
      expect(points.last, (x: 40.0, y: 0.0, width: 12.0));
      expect(points.length, greaterThan(20), reason: 'a step a pixel or less');
      // Half way along the curve: ¼ p0 + ½ control + ¼ p1.
      final middle = points[points.length ~/ 2];
      expect(middle.x, closeTo(20, 1));
      expect(middle.y, closeTo(10, 1));
      expect(middle.width, closeTo(8, 0.5));
    });

    test('a 104-byte point whose control point is 0,0 steps straight', () {
      final read = parseClipVectorBody(
        vectorStrokeBytes(
          [(0, 0, 1), (40, 0, 1)],
          bends: [(0, 0), null],
        ),
      );
      expect(read.strokes.single.points, hasLength(2));
    });

    test('a record of a kind this reader does not draw is counted, not '
        'drawn — and the flags the sample carries are drawn', () {
      final read = parseClipVectorBody(
        body([
          vectorStrokeBytes([(1, 1, 1)], flags: 2),
          vectorStrokeBytes([(1, 1, 1)], flags: 385),
          vectorStrokeBytes([(1, 1, 1)], flags: 17),
        ]),
      );
      expect(read.unread, 1);
      expect(read.strokes, hasLength(2));
    });

    test('🚨a body that does not end at its last record is refused — and so '
        'is a head of a size nobody has seen', () {
      final stroke = vectorStrokeBytes([(1, 1, 1)]);
      expect(
        () => parseClipVectorBody(body([stroke, Uint8List(8)])),
        throwsA(isA<ClipFormatException>()),
      );
      expect(
        () => parseClipVectorBody(Uint8List.sublistView(stroke, 0, 100)),
        throwsA(isA<ClipFormatException>()),
      );
      // Four bytes longer, so the odd head still ends at the data's end and
      // only its size is what is refused.
      final oddHead = Uint8List.fromList([...stroke, 0, 0, 0, 0]);
      ByteData.sublistView(oddHead).setUint32(0, 96);
      expect(
        () => parseClipVectorBody(oddHead),
        throwsA(isA<ClipFormatException>()),
      );
      final oddPoint = Uint8List.fromList([...stroke, 0, 0, 0, 0, 0, 0, 0, 0]);
      ByteData.sublistView(oddPoint).setUint32(8, 96);
      expect(
        () => parseClipVectorBody(oddPoint),
        throwsA(isA<ClipFormatException>()),
      );
    });

    test('a point that is not a number is refused, not drawn into a crash', () {
      expect(
        () => parseClipVectorBody(vectorStrokeBytes([(double.nan, 1, 1)])),
        throwsA(isA<ClipFormatException>()),
      );
      expect(
        () => parseClipVectorBody(
          vectorStrokeBytes(
            [(0, 0, 1), (9, 0, 1)],
            bends: [(double.infinity, 0), null],
          ),
        ),
        throwsA(isA<ClipFormatException>()),
      );
    });
  });

  group('drawing', () {
    ClipCelTarget canvas({double alpha = 1}) => (
      left: 0,
      top: 0,
      canvasWidth: 64,
      canvasHeight: 64,
      alpha: alpha,
      tileSize: 64,
    );

    /// The pixel (x, y) of [tiles] — one 64 × 64 tile, or none.
    (int, int, int, int) pixel(List<ClipCelTile> tiles, int x, int y) {
      if (tiles.isEmpty) {
        return (0, 0, 0, 0);
      }
      final at = (y * 64 + x) * 4;
      final bytes = tiles.single.pixels;
      return (bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]);
    }

    test('🎯a stroke lands where the layer puts it, as wide as its pen, in '
        'its colour', () {
      final drawn = clipVectorTiles(
        [
          vectorStrokeBytes(
            [(5, 13, 1), (45, 13, 1)],
            colour: (0, 0, 255),
            radius: 3,
          ),
        ],
        (x: 5, y: 7),
        canvas(),
      );

      expect(drawn.unread, 0);
      // The stroke runs 10 … 50 across at row 20, six across — opaque to a
      // level: the brush lands it, and the brush's own rounding is its.
      final (r, g, b, a) = pixel(drawn.tiles, 30, 20);
      expect((r, g, b), (0, 0, 255));
      expect(a, closeTo(255, 1));
      // Its line is row 20's top edge: rows 19 and 20 are its core, and the
      // rows beyond them the pen's soft rim.
      expect(pixel(drawn.tiles, 30, 19).$4, closeTo(255, 1));
      expect(pixel(drawn.tiles, 30, 17).$4, greaterThan(0));
      expect(pixel(drawn.tiles, 30, 22).$4, greaterThan(0));
      expect(pixel(drawn.tiles, 30, 25).$4, 0, reason: 'past its width');
      expect(pixel(drawn.tiles, 30, 14).$4, 0, reason: 'past its width');
      expect(pixel(drawn.tiles, 30, 13).$4, 0, reason: 'not where it is '
          'stored — the layer\'s offset moves it');
      expect(pixel(drawn.tiles, 56, 20).$4, 0, reason: 'past its end');
    });

    test('the layer\'s opacity is baked over the whole picture, and a '
        'stroke\'s own opacity is its ceiling, however its dabs overlap', () {
      final stroke = vectorStrokeBytes(
        [(10, 20, 1), (50, 20, 1)],
        radius: 4,
        opacity: 0.5,
      );
      final full = clipVectorTiles([stroke], (x: 0, y: 0), canvas());
      final faint = clipVectorTiles(
        [stroke],
        (x: 0, y: 0),
        canvas(alpha: 0.5),
      );

      expect(pixel(full.tiles, 30, 20).$4, closeTo(128, 1));
      expect(pixel(faint.tiles, 30, 20).$4, closeTo(64, 1));
    });

    test('a point with no width lays no dab — the rest of its stroke is '
        'still drawn', () {
      final drawn = clipVectorTiles(
        [
          vectorStrokeBytes([
            (10, 20, 1),
            (30, 20, 0),
            (50, 20, -1),
          ], radius: 3),
        ],
        (x: 0, y: 0),
        canvas(),
      );
      expect(
        pixel(drawn.tiles, 10, 19).$4,
        greaterThan(100),
        reason: 'the one dab the point with a width lays',
      );
      expect(pixel(drawn.tiles, 40, 19).$4, 0, reason: 'nothing past the '
          'last point with a width');
    });

    test('a stroke off the canvas lands nothing — and the strokes it cannot '
        'read are counted', () {
      final drawn = clipVectorTiles(
        [
          body([
            vectorStrokeBytes([(-300, 10, 1), (-200, 10, 1)]),
            vectorStrokeBytes([(1, 1, 1)], flags: 2),
          ]),
        ],
        (x: 0, y: 0),
        canvas(),
      );
      expect(drawn.tiles, isEmpty);
      expect(drawn.unread, 1);
    });
  });
}
