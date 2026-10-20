import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/guide_geometry.dart' show GuideTransform;
import 'package:anicel/src/services/import/cel_picture.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/undo_surface_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cel_text_fixture.dart';

/// F-374-Q8 (유저 2026-10-17: 「맞춘다 — 참조 그림은 벽 밖까지 통째로」): a
/// file's picture is laid on its cel whole, past the pasteboard where it is
/// larger, and the picture's own value says where it lies
/// ([BitmapSurface.laidBounds]) — so it travels by every road the picture
/// already has: the saved cel, an undo entry that was parked, a change of
/// the sheet's size. Each is asked here whether it arrived whole.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = celTextTestKey;
  // Twelve pixels past the wall on the left: on the test grid (32 × 32 in
  // tiles of 8) the pasteboard's first tile is -4, so the file's reaches
  // two beyond it.
  final laid = DirtyRegion(
    left: -44,
    top: 0,
    rightExclusive: 4,
    bottomExclusive: 8,
  );
  final beyond = TileCoord(x: -6, y: 0);
  final inside = TileCoord(x: 0, y: 0);
  const pastTheWall = [9, 9, 9, 255];
  const withinIt = [7, 7, 7, 255];
  // Its ink at world (-43, 1) — inside the file's rect, past the wall.
  final edge = tileOf({(5, 1): pastTheWall});
  final ink = tileOf({(1, 1): withinIt});
  BitmapSurface laidPicture() => BitmapSurface(
    canvasSize: celTextTestCanvas,
    tileSize: celTextTestTileSize,
    tiles: {beyond: edge, inside: ink},
    laidBounds: laid,
  );

  group('the saved cel', () {
    test('🚨reads back whole — the tiles past the wall, and where the file '
        'lies', () {
      final read = AnicelCelBlob.encode(
        AnicelCelEntry.fromSurface(key, laidPicture()),
      ).decode().toSurface();

      expect(read, laidPicture());
      expect(read.tileAt(beyond)!.pixels, edge.pixels);
    });

    test('the two ways of writing a cel write the same bytes', () {
      expect(
        encodeCelEntryFromSurface(key, laidPicture()),
        encodeCelEntry(AnicelCelEntry.fromSurface(key, laidPicture())),
      );
    });

    test('where the file lies ends the stream — a one, then its four '
        'edges', () {
      final bytes = encodeCelEntryFromSurface(key, laidPicture());
      final end = ByteData.sublistView(bytes, bytes.length - 17);

      expect(end.getUint8(0), 1);
      expect([
        for (var i = 0; i < 4; i += 1) end.getInt32(1 + i * 4, Endian.little),
      ], [-44, 0, 4, 8]);
    });

    test('a cel no file was laid on ends in a zero', () {
      final withNone = encodeCelEntryFromSurface(key, drawingOf({inside: ink}));

      expect(withNone.first, anicelCelBinaryVersion);
      expect(withNone.last, 0);
    });

    test('a cel written before a file could lie past the wall reads as it '
        'always did', () {
      // A v4 stream: today's with the byte at its end taken off.
      final drawn = drawingOf({inside: ink}).withTexts([textOf(1)]);
      final today = encodeCelEntryFromSurface(key, drawn);
      final v4 = Uint8List.fromList(today.sublist(0, today.length - 1))
        ..[0] = 4;

      final read = decodeCelEntry(v4).toSurface();

      expect(read, drawn);
      expect(read.laidBounds, isNull);
    });
  });

  group('an undo entry that was parked', () {
    test('🚨puts the picture back whole — where the file lies, beside the '
        'tiles that went to the room', () async {
      final live = drawingOf({inside: ink});
      final before = laidPicture();
      final snapshot = UndoSurfaceSnapshot(
        key: key,
        snapshot: before,
        sharedWith: live,
      );

      expect(await snapshot.park(), isTrue);
      expect(snapshot.isParked, isTrue, reason: 'fixture: it let go');

      expect(snapshot.surfaceOver(live), before);
    });
  });

  group('a change of the sheet\'s size', () {
    test('🚨a crop keeps a laid picture whole, and cuts the drawing at the '
        'new wall', () {
      // A sheet of 16: its pasteboard's tiles are -2 to 3.
      const smaller = CanvasSize(width: 16, height: 16);
      final drawn = TileCoord(x: 5, y: 2);

      final cropped = resizeBitmapSurfaceCanvas(
        laidPicture().putTiles([(coord: drawn, tile: ink)]),
        smaller,
      );

      expect(cropped.laidBounds, laid);
      expect(cropped.tileAt(beyond), same(edge));
      expect(cropped.tileAt(drawn), isNull, reason: 'past the new wall');
    });

    test('🚨an anchored resize carries a laid picture with the drawing, and '
        'keeps it whole', () {
      // A whole tile and a part of one, so both roads of the pass run — and
      // six, a part that carries the file's pixel into a tile it held none
      // of before.
      for (final (dx, dy) in [(-8, 0), (-3, 0), (-6, 0), (-3, 2)]) {
        final moved = translateBitmapSurface(
          laidPicture(),
          dx: dx,
          dy: dy,
          canvasSize: celTextTestCanvas,
        );

        expect(
          moved.laidBounds,
          DirtyRegion(
            left: -44 + dx,
            top: dy,
            rightExclusive: 4 + dx,
            bottomExclusive: 8 + dy,
          ),
          reason: '($dx, $dy)',
        );
        expect(
          pixelAt(moved, -43 + dx, 1 + dy),
          pastTheWall,
          reason: '($dx, $dy)',
        );
        expect(pixelAt(moved, 1 + dx, 1 + dy), withinIt, reason: '($dx, $dy)');
      }
    });

    test('a move cuts what is not the file at the wall, as ever', () {
      // A drawn pixel at world (-31, 1) — the pasteboard's first column but
      // one — is carried three past the wall, where no file lies.
      final drawn = tileOf({
        (1, 1): [5, 5, 5, 255],
      });
      final picture = drawingOf({TileCoord(x: -4, y: 0): drawn});

      final moved = translateBitmapSurface(
        picture,
        dx: -3,
        dy: 0,
        canvasSize: celTextTestCanvas,
      );

      expect(moved.laidBounds, isNull);
      expect(moved.tiles, isEmpty);
    });
  });

  group('a file\'s picture laid on the cel', () {
    // 160 × 8 laid 1:1 at x -64: 32 past the wall on each side of the
    // test grid's pasteboard (-32 to 64).
    Future<ui.Image> strip() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 160, 8),
        ui.Paint()..color = const ui.Color(0xFF336699),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(160, 8);
      picture.dispose();
      return image;
    }

    testWidgets('🚨lies whole — every pixel of it, past the wall on both '
        'sides', (tester) async {
      await tester.runAsync(() async {
        final image = await strip();

        final surface = await layCelPicture(
          picture: EnginePicture(image),
          canvas: celTextTestCanvas,
          placement: const GuideTransform(1, 0, 0, 1, -64, 0),
          tileSize: celTextTestTileSize,
          whole: true,
        );
        image.dispose();

        expect(
          surface.laidBounds,
          DirtyRegion(
            left: -64,
            top: 0,
            rightExclusive: 96,
            bottomExclusive: 8,
          ),
        );
        final columns = surface.tiles.keys.map((coord) => coord.x).toList()
          ..sort();
        expect(columns.first, -8);
        expect(columns.last, 11);
        expect(pixelAt(surface, -64, 0), [0x33, 0x66, 0x99, 255]);
        expect(pixelAt(surface, 95, 7), [0x33, 0x66, 0x99, 255]);
      });
    });

    testWidgets('lies on the whole pixels it touches when it is placed '
        'between them', (tester) async {
      await tester.runAsync(() async {
        final image = await strip();

        final surface = await layCelPicture(
          picture: EnginePicture(image),
          canvas: celTextTestCanvas,
          placement: const GuideTransform(1, 0, 0, 1, -64.5, 0.25),
          tileSize: celTextTestTileSize,
          whole: true,
        );
        image.dispose();

        expect(
          surface.laidBounds,
          DirtyRegion(
            left: -65,
            top: 0,
            rightExclusive: 96,
            bottomExclusive: 9,
          ),
        );
      });
    });

    testWidgets('not asked to lie whole, it is cut at the wall as it was', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final image = await strip();

        final surface = await layCelPicture(
          picture: EnginePicture(image),
          canvas: celTextTestCanvas,
          placement: const GuideTransform(1, 0, 0, 1, -64, 0),
          tileSize: celTextTestTileSize,
        );
        image.dispose();

        expect(surface.laidBounds, isNull);
        final columns = surface.tiles.keys.map((coord) => coord.x).toList()
          ..sort();
        expect(columns.first, -4);
        expect(columns.last, 7);
      });
    });
  });
}

/// The pixel of [surface] at canvas ([x], [y]), straight RGBA — null where
/// it holds no tile there.
List<int>? pixelAt(BitmapSurface surface, int x, int y) {
  final size = surface.tileSize;
  final coord = TileCoord(x: (x / size).floor(), y: (y / size).floor());
  return pixelOf(surface, coord, x - coord.x * size, y - coord.y * size);
}
