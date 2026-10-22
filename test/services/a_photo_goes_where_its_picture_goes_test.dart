import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_photo.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/undo_surface_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cel_photo_fixture.dart';
import '../helpers/cel_text_fixture.dart';

/// I-97 (유저 2026-10-15, I-97-Q1: 「사진으로 남게(셀의 텍스트처럼)」): a
/// sheet's photo is in its ink's picture value, as a cel's texts are, so it
/// travels by every road the picture already has — the store and its
/// emptiness oracle, the saved cel, an undo entry that was parked, a
/// change of the sheet's size. Each is asked here, once, whether the photo
/// arrived.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = celTextTestKey;
  final a = TileCoord(x: 0, y: 0);
  final b = TileCoord(x: 1, y: 0);
  final ink = tileOf({
    (1, 1): [9, 9, 9, 255],
  });

  group('the store', () {
    test('🚨a sheet that holds only a photo is kept, and is a picture — the '
        'oracle every reader of its content asks says so', () {
      final store = BrushFrameStore();
      final onlyPhoto = drawingOf(const {}).withPhotos([photoOf(1)]);

      store.storeBakedSurface(key, onlyPhoto);

      expect(store.bakedSurfaceOrNull(key), same(onlyPhoto));
      expect(store.celHasRenderableContent(key), isTrue);
    });

    test('a cleared drawing over a photo is still a picture: the pixels are '
        'gone and the photo is not', () {
      final store = BrushFrameStore();

      store.storeBakedSurface(
        key,
        drawingOf({
          a: BitmapTile.blank(size: celTextTestTileSize),
        }).withPhotos([photoOf(1)]),
      );

      expect(store.celHasRenderableContent(key), isTrue);
    });
  });

  group('the saved cel', () {
    final picture = drawingOf({a: ink})
        .withTexts([textOf(3, words: 'over it')])
        .withPhotos([
          photoOf(5, center: CanvasPoint(x: 12.5, y: -4)),
          photoOf(2, path: 'C:/pool/사진.png'),
        ]);

    test('🚨reads back with its photos — ids, references and order', () {
      final read = AnicelCelBlob.encode(
        AnicelCelEntry.fromSurface(key, picture),
      ).decode().toSurface();

      expect(read, picture);
      expect(read.photos.map((photo) => photo.id), [5, 2]);
      expect(read.photos.last.reference.assetPath, 'C:/pool/사진.png');
      expect(read.texts.single.content.text, 'over it');
    });

    test('the two ways of writing a cel write the same bytes', () {
      expect(
        encodeCelEntryFromSurface(key, picture),
        encodeCelEntry(AnicelCelEntry.fromSurface(key, picture)),
      );
    });

    final headEnd = celStreamHeadEnd(key);

    test('a cel written before photos existed reads as it always did', () {
      // A v3 stream: the head, then its tiles and its texts — today's with
      // its photos' zero taken out, and the byte at its end that says no
      // file was laid on it (v5).
      final withText = drawingOf({a: ink}).withTexts([textOf(1)]);
      final today = encodeCelEntryFromSurface(key, withText);
      final v3 = Uint8List.fromList([
        ...today.sublist(0, headEnd),
        ...today.sublist(headEnd + 4, today.length - 1),
      ])..[0] = 3;

      final read = decodeCelEntry(v3).toSurface();

      expect(read, withText);
      expect(read.photos, isEmpty);
    });

    test('a cel with no photo writes a zero where its photos would be — '
        'after its head, ahead of its tiles', () {
      final withNone = encodeCelEntryFromSurface(key, drawingOf({a: ink}));

      expect(withNone.first, anicelCelBinaryVersion);
      expect(withNone.sublist(headEnd, headEnd + 4), [0, 0, 0, 0]);
    });
  });

  group('an undo entry that was parked', () {
    test('🚨puts the picture back WITH its photos — beside the tiles that '
        'went to the room', () async {
      final live = drawingOf({a: ink, b: ink});
      final before = drawingOf({
        a: tileOf({
          (0, 0): [1, 2, 3, 255],
        }),
        b: ink,
      }).withPhotos([photoOf(1), photoOf(2)]);
      final snapshot = UndoSurfaceSnapshot(
        key: key,
        snapshot: before,
        sharedWith: live,
      );

      expect(await snapshot.park(), isTrue);
      expect(snapshot.isParked, isTrue, reason: 'fixture: it let go');

      expect(snapshot.surfaceOver(() => live), before);
    });

    test('a snapshot that owned no tile — a photo moved, which changes no '
        'pixel — comes back with its photos too', () async {
      final live = drawingOf({a: ink}).withPhotos([
        photoOf(1, center: CanvasPoint(x: 30, y: 2)),
      ]);
      final before = drawingOf({a: ink}).withPhotos([photoOf(1)]);
      final snapshot = UndoSurfaceSnapshot(
        key: key,
        snapshot: before,
        sharedWith: live,
      );

      expect(await snapshot.park(), isTrue);
      final back = snapshot.surfaceOver(() => live);

      expect(back, before);
      expect(
        back!.photos.single.reference.pose.center,
        CanvasPoint(x: 10, y: 6),
      );
    });
  });

  group('a change of the sheet\'s size', () {
    final center = CanvasPoint(x: 10, y: 6);
    BitmapSurface picture() =>
        drawingOf({a: ink}).withPhotos([photoOf(1, center: center)]);

    test('a crop or an extension leaves a photo where it stands', () {
      const wider = CanvasSize(width: 64, height: 32);

      final resized = resizeBitmapSurfaceCanvas(picture(), wider);

      expect(resized.canvasSize, wider);
      expect(resized.photos, picture().photos);
    });

    test('🚨an anchored resize moves a photo by the offset that moves the '
        'drawing — and nothing else of it', () {
      // A whole tile and a part of one, so both roads of the pass run.
      for (final (dx, dy) in [(8, 16), (3, -5)]) {
        final moved = translateBitmapSurface(
          picture(),
          dx: dx,
          dy: dy,
          canvasSize: celTextTestCanvas,
        );

        final photo = moved.photos.single;
        final was = picture().photos.single.reference;
        expect(photo.id, 1, reason: '($dx, $dy)');
        expect(
          photo.reference,
          was.copyWith(
            pose: was.pose.copyWith(
              center: CanvasPoint(x: center.x + dx, y: center.y + dy),
            ),
          ),
          reason: '($dx, $dy)',
        );
        expect(moved.tiles, isNotEmpty, reason: 'fixture: ($dx, $dy)');
      }
    });

    test('a move that carries a photo off the pasteboard leaves it there — '
        'nothing is clamped', () {
      final gone = translateBitmapSurface(
        picture(),
        dx: 0,
        dy: 1000,
        canvasSize: celTextTestCanvas,
      );

      expect(gone.tiles, isEmpty, reason: 'fixture: the drawing left too');
      expect(
        gone.photos.single.reference.pose.center,
        CanvasPoint(x: 10, y: 1006),
      );
    });
  });

  test('fixture: a photo is a value — the same file standing at the same '
      'place is the same photo', () {
    expect(photoOf(1), photoOf(1));
    expect(photoOf(1), isNot(photoOf(1, path: 'C:/pool/other.png')));
    expect(photoOf(1), isNot(photoOf(2)));
    expect(
      CelPhoto.fromJson(throughJson(photoOf(1).toJson())),
      photoOf(1),
    );
  });
}
