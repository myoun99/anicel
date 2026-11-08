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
  // 192 pixels past the wall on the left: on the test grid (512 × 512 in
  // tiles of 128) the pasteboard's first tile is -4, so the file's reaches
  // two beyond it.
  final laid = DirtyRegion(
    left: -704,
    top: 0,
    rightExclusive: 64,
    bottomExclusive: 128,
  );
  final beyond = TileCoord(x: -6, y: 0);
  final inside = TileCoord(x: 0, y: 0);
  const pastTheWall = [9, 9, 9, 255];
  const withinIt = [7, 7, 7, 255];
  // Its ink at world (-688, 16) — inside the file's rect, past the wall.
  final edge = tileOf({(80, 16): pastTheWall});
  final ink = tileOf({(16, 16): withinIt});
  BitmapSurface laidPicture() => BitmapSurface(
    canvasSize: celTextTestCanvas,
    tileSize: celTextTestTileSize,
    tiles: {beyond: edge, inside: ink},
    laidBounds: laid,
  );

  group('the saved cel', () {
    test('🚨reads back whole — the tiles past the wall, and where the file '
        'lies', () {
      final read = AnicelCelBlob.ofSurface(
        key,
        laidPicture(),
      ).toSurface();

      expect(read, laidPicture());
      expect(read.tileAt(beyond)!.pixels, edge.pixels);
    });

    test('where the file lies ends the stream — a one, then its four '
        'edges', () {
      final bytes = encodeCelEntryFromSurface(key, laidPicture());
      final end = ByteData.sublistView(bytes, bytes.length - 17);

      expect(end.getUint8(0), 1);
      expect([
        for (var i = 0; i < 4; i += 1) end.getInt32(1 + i * 4, Endian.little),
      ], [-704, 0, 64, 128]);
    });

    test('a cel no file was laid on ends in a zero', () {
      final withNone = encodeCelEntryFromSurface(key, drawingOf({inside: ink}));

      expect(withNone.first, anicelCelBinaryVersion);
      expect(withNone.last, 0);
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

      expect(snapshot.surfaceOver(() => live), before);
    });
  });

  group('a change of the sheet\'s size', () {
    test('🚨a crop keeps a laid picture whole, and cuts the drawing at the '
        'new wall', () {
      // A sheet of 256: its pasteboard's tiles are -2 to 3.
      const smaller = CanvasSize(width: 256, height: 256);
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
      // 96, a part that carries the file's pixel into a tile it held none
      // of before.
      for (final (dx, dy) in [(-128, 0), (-48, 0), (-96, 0), (-48, 32)]) {
        final moved = translateBitmapSurface(
          laidPicture(),
          dx: dx,
          dy: dy,
          canvasSize: celTextTestCanvas,
        );

        expect(
          moved.laidBounds,
          DirtyRegion(
            left: -704 + dx,
            top: dy,
            rightExclusive: 64 + dx,
            bottomExclusive: 128 + dy,
          ),
          reason: '($dx, $dy)',
        );
        expect(
          pixelAt(moved, -688 + dx, 16 + dy),
          pastTheWall,
          reason: '($dx, $dy)',
        );
        expect(
          pixelAt(moved, 16 + dx, 16 + dy),
          withinIt,
          reason: '($dx, $dy)',
        );
      }
    });

    test('a move cuts what is not the file at the wall, as ever', () {
      // A drawn pixel at world (-496, 16) — sixteen columns into the
      // pasteboard — is carried 48 left, past the wall, where no file lies.
      final drawn = tileOf({
        (16, 16): [5, 5, 5, 255],
      });
      final picture = drawingOf({TileCoord(x: -4, y: 0): drawn});

      final moved = translateBitmapSurface(
        picture,
        dx: -48,
        dy: 0,
        canvasSize: celTextTestCanvas,
      );

      expect(moved.laidBounds, isNull);
      expect(moved.tiles, isEmpty);
    });

    // Card `a-resize-redo-moves-every-cel-on-the-ui-thread`: the file's
    // pass keeps the tiles its rect touches, so only the rect's own bottom
    // tells a drawn row below it from the file.
    test('a move carries past the wall the file\'s rect to the row, and '
        'not the drawn row below it', () {
      // The file's rect ends 32 rows short of its tile's bottom, and a
      // drawn pixel sits on the first row below it, inside the wall:
      // (-496, 96).
      final shallow = DirtyRegion(
        left: -704,
        top: 0,
        rightExclusive: 64,
        bottomExclusive: 96,
      );
      final drawn = tileOf({
        (16, 96): [5, 5, 5, 255],
      });
      final picture = BitmapSurface(
        canvasSize: celTextTestCanvas,
        tileSize: celTextTestTileSize,
        tiles: {beyond: edge, TileCoord(x: -4, y: 0): drawn},
        laidBounds: shallow,
      );

      // 48 left puts it past the wall, sixteen down on the rect's new
      // bottom row — the first the file does not cover, in a tile it does.
      final moved = translateBitmapSurface(
        picture,
        dx: -48,
        dy: 16,
        canvasSize: celTextTestCanvas,
      );

      expect(pixelAt(moved, -688 - 48, 16 + 16), pastTheWall);
      expect(pixelAt(moved, -544, 112) ?? const [0, 0, 0, 0], [0, 0, 0, 0]);
    });
  });

  group('a file\'s picture laid on the cel', () {
    // 2560 × 128 laid 1:1 at x -1024: 512 past the wall on each side of the
    // test grid's pasteboard (-512 to 1024).
    Future<ui.Image> strip() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 2560, 128),
        ui.Paint()..color = const ui.Color(0xFF336699),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(2560, 128);
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
          placement: const GuideTransform(1, 0, 0, 1, -1024, 0),
          tileSize: celTextTestTileSize,
          whole: true,
        );
        image.dispose();

        expect(
          surface.laidBounds,
          DirtyRegion(
            left: -1024,
            top: 0,
            rightExclusive: 1536,
            bottomExclusive: 128,
          ),
        );
        final columns = surface.tiles.keys.map((coord) => coord.x).toList()
          ..sort();
        expect(columns.first, -8);
        expect(columns.last, 11);
        expect(pixelAt(surface, -1024, 0), [0x33, 0x66, 0x99, 255]);
        expect(pixelAt(surface, 1535, 127), [0x33, 0x66, 0x99, 255]);
      });
    });

    testWidgets('lies on the whole pixels it touches when it is placed '
        'between them', (tester) async {
      await tester.runAsync(() async {
        final image = await strip();

        final surface = await layCelPicture(
          picture: EnginePicture(image),
          canvas: celTextTestCanvas,
          placement: const GuideTransform(1, 0, 0, 1, -1024.5, 0.25),
          tileSize: celTextTestTileSize,
          whole: true,
        );
        image.dispose();

        expect(
          surface.laidBounds,
          DirtyRegion(
            left: -1025,
            top: 0,
            rightExclusive: 1536,
            bottomExclusive: 129,
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
          placement: const GuideTransform(1, 0, 0, 1, -1024, 0),
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
