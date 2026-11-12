// The first stroke compiles the executor and the stroke's kernels: 40 s on
// a machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/import/clip_cel_raster.dart';
import 'package:anicel/src/services/import/clip_container.dart'
    show ClipFormatException;
import 'package:anicel/src/services/import/clip_vector_raster.dart';

import '../../helpers/collect_garbage.dart';
import 'clip_test_builder.dart';

/// A vector layer's strokes, read and drawn (card `csp-clip-import-analysis`
/// — 6-1 item 8: 「벡터 레이어는 래스터로 그려 넣는다」; 유저 10-07 「벡터같은
/// 불가능한건 냅두거나 래스터라이즈시켜서」). The one sample with vectors
/// stores a render beside them with no blocks in the file, so the strokes
/// ARE the picture.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    // The app's grid — the one the engine lays on.
    const side = 128;

    ClipCelTarget canvas({double alpha = 1, int across = 64}) => (
      left: 0,
      top: 0,
      canvasWidth: across,
      canvasHeight: 64,
      alpha: alpha,
      tileSize: side,
    );

    /// The pixel (x, y) of [tiles] — the one tile a 64 × 64 canvas has, or
    /// none.
    (int, int, int, int) pixel(List<ClipCelTile> tiles, int x, int y) {
      if (tiles.isEmpty) {
        return (0, 0, 0, 0);
      }
      final at = (y * side + x) * 4;
      final bytes = tiles.single.pixels;
      return (bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]);
    }

    /// The tiles the cut reads back from the engine while [draw] runs: what
    /// the strokes landed in.
    Future<List<BitmapTile>> readBackWhile(Future<void> Function() draw) async {
      final asked = <BitmapTile>[];
      EngineTileLedger.debugBeforeRead = asked.addAll;
      addTearDown(() => EngineTileLedger.debugBeforeRead = null);
      await draw();
      EngineTileLedger.debugBeforeRead = null;
      return asked;
    }

    test('🎯a stroke lands where the layer puts it, as wide as its pen, in '
        'its colour', () async {
      final drawn = await clipVectorTiles(
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
        'stroke\'s own opacity is its ceiling, however its dabs '
        'overlap', () async {
      final stroke = vectorStrokeBytes(
        [(10, 20, 1), (50, 20, 1)],
        radius: 4,
        opacity: 0.5,
      );
      final full = await clipVectorTiles([stroke], (x: 0, y: 0), canvas());
      final faint = await clipVectorTiles(
        [stroke],
        (x: 0, y: 0),
        canvas(alpha: 0.5),
      );

      expect(pixel(full.tiles, 30, 20).$4, closeTo(128, 1));
      expect(pixel(faint.tiles, 30, 20).$4, closeTo(64, 1));
    });

    test('the picture is baked through the layer\'s mask as a stored one '
        'is — where the mask stands on the canvas', () async {
      // The mask stands from x 20, hiding its first 16 columns; past its
      // edges its fill shows everything.
      final block = Uint8List(256 * 256);
      for (var y = 0; y < 256; y += 1) {
        for (var x = 16; x < 256; x += 1) {
          block[y * 256 + x] = 255;
        }
      }
      final drawn = await clipVectorTiles(
        [
          vectorStrokeBytes([(10, 20, 1), (50, 20, 1)], radius: 3),
        ],
        (x: 0, y: 0),
        canvas(),
        mask: (
          attribute: offscreenAttributeBytes(
            width: 64,
            height: 64,
            columns: 1,
            rows: 1,
            colourChannels: 0,
            fill: 1,
          ),
          blocks: blockRecordsBytes({0: block}),
          left: 20,
          top: 0,
        ),
      );

      expect(pixel(drawn.tiles, 30, 20).$4, 0, reason: 'the mask\'s x 10');
      expect(pixel(drawn.tiles, 40, 20).$4, closeTo(255, 1));
      expect(
        pixel(drawn.tiles, 15, 20).$4,
        closeTo(255, 1),
        reason: 'left of the mask',
      );
    });

    test('a line narrows toward a thin point as a pressed pen\'s does — and '
        'a point with no width, or less, lays nothing', () async {
      final drawn = await clipVectorTiles(
        [
          body([
            vectorStrokeBytes([
              (10, 20, 2),
              (40, 20, 0),
              (55, 20, -0.5),
            ], radius: 3),
            // A stroke with no width anywhere — nothing to size a pen by.
            vectorStrokeBytes([(10, 50, 0), (50, 50, 0)], radius: 3),
          ]),
        ],
        (x: 0, y: 0),
        canvas(),
      );
      /// How many rows of column [x] carry ink.
      int across(int x) => [
        for (var y = 0; y < 64; y += 1) pixel(drawn.tiles, x, y).$4,
      ].where((alpha) => alpha > 0).length;

      expect(across(12), greaterThan(across(25)), reason: 'twelve wide here');
      expect(across(25), greaterThan(across(36)), reason: 'narrower on');
      expect(across(36), greaterThan(0), reason: 'still a line');
      expect(across(48), 0, reason: 'nothing past the point with no width');
    });

    // 🗣️size-rack-0-7-under-the-brush-floor (유저 2026-10-17 「다른부분
    // 발견되는거있으면 법 통일」): a stroke under a pixel lands as the brush
    // lands one.
    test('a stroke narrower than a pixel lands as the one-pixel stroke '
        'does, lighter by its width', () async {
      // Below row 20's centre by more than a 0.6 dab's reach — ↩️where a
      // stroke that thin landed nothing.
      Future<int Function(int, int)> drawn(double width) async {
        final tiles = (await clipVectorTiles(
          [
            vectorStrokeBytes([
              (10.2, 20.85, 1),
              (50.2, 20.85, 1),
            ], radius: width / 2),
          ],
          (x: 0, y: 0),
          canvas(),
        )).tiles;
        return (x, y) => pixel(tiles, x, y).$4;
      }

      final whole = await drawn(1);
      expect(whole(30, 20), greaterThan(0), reason: 'premise: it draws');
      for (final width in [0.2, 0.6]) {
        final thin = await drawn(width);
        for (var x = 12; x < 49; x += 1) {
          for (final y in [19, 20, 21]) {
            expect(
              thin(x, y),
              closeTo(whole(x, y) * width, 2),
              reason: '$width wide at $x, $y',
            );
          }
        }
      }
    });

    test('a stroke off the canvas lands nothing, takes no tile of the '
        'engine\'s — and the strokes it cannot read are counted', () async {
      late final ({List<ClipCelTile> tiles, int unread}) drawn;
      final readBack = await readBackWhile(() async {
        drawn = await clipVectorTiles(
          [
            body([
              // Off the canvas, on the pasteboard a cel's own picture has.
              vectorStrokeBytes([(-30, 10, 1), (-20, 10, 1)]),
              vectorStrokeBytes([(1, 1, 1)], flags: 2),
            ]),
          ],
          (x: 0, y: 0),
          canvas(),
        );
      });
      expect(drawn.tiles, isEmpty);
      expect(drawn.unread, 1);
      expect(readBack, isEmpty, reason: 'the picture is the canvas\'s alone');
    });

    // 🗣️clip-vector-import-draws-with-the-c-brush-Q1 (유저 2026-11-11).
    test('🚨the strokes land on the engine — the picture handed on to be '
        'cut is tiles the engine made, none the C brush\'s', () async {
      late final ({List<ClipCelTile> tiles, int unread}) drawn;
      final readBack = await readBackWhile(() async {
        drawn = await clipVectorTiles(
          [
            vectorStrokeBytes([(10, 20, 1), (50, 20, 1)], radius: 3),
          ],
          (x: 0, y: 0),
          canvas(),
        );
      });
      expect(pixel(drawn.tiles, 30, 20).$4, closeTo(255, 1));
      expect(readBack, hasLength(1));
      expect(readBack.single.isOnEngine, isTrue);
    });

    test('a later stroke lies over the ones before it, in the file\'s '
        'order', () async {
      final drawn = await clipVectorTiles(
        [
          body([
            vectorStrokeBytes(
              [(10, 30, 1), (50, 30, 1)],
              colour: (255, 0, 0),
              radius: 4,
            ),
            vectorStrokeBytes(
              [(30, 10, 1), (30, 50, 1)],
              colour: (0, 0, 255),
              radius: 4,
            ),
          ]),
        ],
        (x: 0, y: 0),
        canvas(),
      );
      final (r, g, b, _) = pixel(drawn.tiles, 30, 30);
      expect((r, g, b), (0, 0, 255), reason: 'where the two cross');
      expect(pixel(drawn.tiles, 15, 30).$1, 255, reason: 'the first, alone');
    });

    // 🔬6,000 strokes at half opacity held 38,750 slots — 2,432 MB of the
    // pool — for a picture of 247 tiles (main PC, 2340 × 1654): each tile
    // laid over stayed as long as the one over it was the engine's alone.
    test('🚨a tile a stroke lays over is let go then: a layer holds its '
        'picture\'s tiles of the pool, not a tile for each stroke', () async {
      final ledger = EngineTileLedger.instance;
      // What earlier tests left goes first: the slots counted are this
      // layer's.
      await collectGarbageUntil(() => ledger.slotCount == 0);
      int? held;
      EngineTileLedger.debugBeforeRead = (_) => held = ledger.slotCount;
      addTearDown(() => EngineTileLedger.debugBeforeRead = null);

      final drawn = await clipVectorTiles(
        [
          body([
            for (var k = 0; k < 20; k += 1)
              vectorStrokeBytes(
                [(10, 12.0 + 2 * k, 1), (50, 12.0 + 2 * k, 1)],
                opacity: 0.5,
                radius: 3,
              ),
          ]),
        ],
        (x: 0, y: 0),
        canvas(),
      );

      expect(drawn.tiles, hasLength(1), reason: 'premise: one tile, drawn');
      expect(held, 1, reason: 'the slots held as the picture is read out');
    });

    group('🚨on the road the app takes — planned on a worker of its own, '
        'laid on this isolate', () {
      setUp(() => debugWorkersRunHere = false);
      tearDown(() => debugWorkersRunHere = true);

      /// Twelve strokes, none over another, each inside one tile of a
      /// canvas four tiles across.
      List<Uint8List> twelve() => [
        body([
          for (var k = 0; k < 12; k += 1)
            vectorStrokeBytes([
              (k % 4 * side + 20.0, 15.0 + k ~/ 4 * 17, 1),
              (k % 4 * side + 90.0, 15.0 + k ~/ 4 * 17, 1),
            ], radius: 3),
        ]),
      ];

      test('the picture is the one drawn here', () async {
        Future<List<ClipCelTile>> drawn() async => (await clipVectorTiles(
          twelve(),
          (x: 0, y: 0),
          canvas(across: 4 * side),
        )).tiles;

        final there = await drawn();
        debugWorkersRunHere = true;
        final here = await drawn();

        expect(there, hasLength(4), reason: 'premise: every tile is drawn in');
        expect(
          [for (final tile in there) (tile.x, tile.y)],
          [for (final tile in here) (tile.x, tile.y)],
        );
        expect(
          [for (final tile in there) tile.pixels],
          [for (final tile in here) tile.pixels],
        );
      });

      test('the worker hands over a stroke at a time: the app has its turn '
          'between any two it lays', () async {
        // The first stroke of a run opens the engine's kernels: out of the
        // way, so the strokes counted land a turn each.
        await clipVectorTiles(twelve(), (x: 0, y: 0), canvas(across: 4 * side));
        final ledger = EngineTileLedger.instance;
        // A turn of this isolate's each time it has one, and how many slots
        // the ledger has then: the first stroke in a tile takes one, and a
        // stroke over it takes one as it lets one go.
        final turns = <int>[];
        var turning = true;
        void turn() {
          turns.add(ledger.slotCount);
          if (turning) {
            Timer.run(turn);
          }
        }

        turn();
        await clipVectorTiles(twelve(), (x: 0, y: 0), canvas(across: 4 * side));
        turning = false;

        final most = [
          for (var at = 1; at < turns.length; at += 1)
            turns[at] - turns[at - 1],
        ].reduce((a, b) => a > b ? a : b);
        expect(most, 1, reason: 'the most strokes laid between two turns');
      });

      test('strokes that would not read are refused by name', () async {
        await expectLater(
          clipVectorTiles(
            [
              body([vectorStrokeBytes([(1, 1, 1)]), Uint8List(8)]),
            ],
            (x: 0, y: 0),
            canvas(),
          ),
          throwsA(isA<ClipFormatException>()),
        );
      });
    });
  });
}
