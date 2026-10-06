import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/anicel_payload_codec.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/undo_surface_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cel_text_fixture.dart';

/// R9-rest (the text tool, 유저 2026-10-06: 「주인은 셀임 … 셀의 그림이랑 정확히
/// 동일. 복사/링크도 같이감」): a text is in the picture's own value, so it
/// travels by every road the picture already has — the store and its
/// emptiness oracle, the saved cel, an undo entry that was parked, a canvas
/// resize. Each of those is asked here, once, whether the text arrived.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );
  final a = TileCoord(x: 0, y: 0);
  final b = TileCoord(x: 1, y: 0);
  final ink = tileOf({
    (1, 1): [9, 9, 9, 255],
  });
  final letters = tileOf({
    (2, 2): [200, 0, 0, 255],
    (3, 2): [200, 0, 0, 128],
  });

  group('the store', () {
    test('🚨a cel that is only a text is kept, and is a picture — the '
        'oracle every row, block and button reads says so', () {
      final store = BrushFrameStore();
      final onlyText = drawingOf(const {}).withTexts([
        textOf(1, plate: {a: letters}),
      ]);

      store.storeBakedSurface(key, onlyText);

      expect(store.bakedSurfaceOrNull(key), same(onlyText));
      expect(store.celHasRenderableContent(key), isTrue);
    });

    test('a text whose plate is empty is still a text the cel carries', () {
      final store = BrushFrameStore();

      store.storeBakedSurface(key, drawingOf(const {}).withTexts([textOf(1)]));

      expect(store.bakedSurfaceOrNull(key)!.texts, hasLength(1));
      expect(store.celHasRenderableContent(key), isTrue);
    });

    test('a cel with nothing at all is still let go', () {
      final store = BrushFrameStore()..storeBakedSurface(key, drawingOf({a: ink}));

      store.storeBakedSurface(key, drawingOf(const {}));

      expect(store.bakedSurfaceOrNull(key), isNull);
      expect(store.celHasRenderableContent(key), isFalse);
    });

    test('the first text on an empty cel crosses the line the timeline '
        'tints by, and taking it off crosses back', () {
      final store = BrushFrameStore();
      final crossings = <int>[];
      store.celContentRevision.addListener(
        () => crossings.add(store.celContentRevision.value),
      );

      store.storeBakedSurface(key, drawingOf(const {}).withTexts([textOf(1)]));
      expect(crossings, hasLength(1));

      store.storeBakedSurface(key, drawingOf(const {}));
      expect(crossings, hasLength(2));
    });

    test('a cleared drawing under a text is still a picture: the pixels '
        'are gone and the letters are not', () {
      final store = BrushFrameStore();

      store.storeBakedSurface(
        key,
        drawingOf({a: BitmapTile.blank(size: celTextTestTileSize)}).withTexts([
          textOf(1, plate: {b: letters}),
        ]),
      );

      expect(store.celHasRenderableContent(key), isTrue);
    });

    test('a plate weighs in the hot tier as the tiles it is', () {
      final store = BrushFrameStore();
      final tileBytes = BitmapTile.bytesFor(celTextTestTileSize);

      store.storeBakedSurface(key, drawingOf({a: ink}));
      expect(store.hotBakedBytes, tileBytes);

      store.storeBakedSurface(
        key,
        drawingOf({a: ink}).withTexts([
          textOf(1, plate: {a: letters, b: letters}),
        ]),
      );
      expect(store.hotBakedBytes, tileBytes * 3);
    });
  });

  group('the coordinator — the road an edit and an undo take', () {
    BrushFrameEditingCoordinator coordinatorOver(BrushFrameStore store) =>
        BrushFrameEditingCoordinator(
          initialFrameKey: key,
          frameStore: store,
          sessionStore: BrushFrameEditSessionStore(
            canvasSize: celTextTestCanvas,
            tileSize: celTextTestTileSize,
          ),
          historyPolicy: const BrushHistoryPolicy(),
        );

    test('a picture put back with its texts is the cel: the session, the '
        'store and the revision all follow', () {
      final store = BrushFrameStore();
      final coordinator = coordinatorOver(store);
      final before = store.getOrCreateFrame(key).sourceRevision;
      final withText = drawingOf({a: ink}).withTexts([
        textOf(1, plate: {b: letters}),
      ]);

      coordinator.restoreSurfaceSnapshot(key, withText);

      expect(coordinator.currentSurfaceOf(key), same(withText));
      expect(store.bakedSurfaceOrNull(key), same(withText));
      expect(store.getOrCreateFrame(key).sourceRevision, greaterThan(before));
    });

    test('a session whose cel is only a text is not taken for an empty one '
        'the store moved past', () {
      final store = BrushFrameStore();
      final coordinator = coordinatorOver(store);
      final onlyText = drawingOf(const {}).withTexts([
        textOf(1, plate: {a: letters}),
      ]);
      coordinator.restoreSurfaceSnapshot(key, onlyText);

      // Another coordinator empties the cel behind this one's back.
      store.storeBakedSurface(key, drawingOf(const {}));

      expect(
        coordinator.currentSurfaceOf(key).holdsNothing,
        isTrue,
        reason: 'the session held a text, so it reseeds from the store',
      );
    });
  });

  group('the saved cel', () {
    final picture = drawingOf({a: ink}).withTexts([
      textOf(
        3,
        words: '한글 かな text',
        plate: {b: letters, TileCoord(x: -1, y: 2): ink},
        anchor: CanvasPoint(x: 12.5, y: -4),
      ),
      textOf(4, words: 'second'),
    ]);

    test('🚨reads back with its texts — ids, settings, order and every '
        'plate byte', () {
      final read = AnicelCelBlob.encode(
        AnicelCelEntry.fromSurface(key, picture),
      ).decode().toSurface();

      expect(read, picture);
      expect(read.texts.map((text) => text.id), [3, 4]);
      expect(read.texts.first.content.text, '한글 かな text');
    });

    test('the two ways of writing a cel write the same bytes', () {
      expect(
        encodeCelEntryFromSurface(key, picture),
        encodeCelEntry(AnicelCelEntry.fromSurface(key, picture)),
      );
    });

    test('a text longer than a 16-bit length can say is written whole', () {
      final long = 'あ' * 40000;
      final read = decodeCelEntry(
        encodeCelEntryFromSurface(
          key,
          drawingOf(const {}).withTexts([textOf(1, words: long)]),
        ),
      ).toSurface();

      expect(read.texts.single.content.text, long);
    });

    test('a cel written before texts existed reads as it always did', () {
      // A v2 stream: the header, one tile, and nothing after it.
      final v3 = encodeCelEntryFromSurface(key, drawingOf({a: ink}));
      final v2 = Uint8List.fromList(v3.sublist(0, v3.length - 4))..[0] = 2;

      final read = decodeCelEntry(v2).toSurface();

      expect(read, drawingOf({a: ink}));
      expect(read.texts, isEmpty);
    });

    test('a cel with no text writes a zero where its texts would be', () {
      final withNone = encodeCelEntryFromSurface(key, drawingOf({a: ink}));

      expect(withNone.first, anicelCelBinaryVersion);
      expect(withNone.sublist(withNone.length - 4), [0, 0, 0, 0]);
    });

    test('a parked cel — the same blob, compressed — comes back with them', () {
      // The cooling pass's own shape: the stream straight off the surface,
      // compressed, wrapped in the blob header.
      final compressed = compressAnicelPayload(
        encodeCelEntryFromSurface(key, picture),
      );
      final blob = AnicelCelBlob.fromCompressedBody(
        key: key,
        canvasSize: picture.canvasSize,
        tileSize: picture.tileSize,
        codec: compressed.codec,
        body: compressed.bytes,
      );

      expect(AnicelCelBlob(blob.bytes).decode().toSurface(), picture);
    });
  });

  group('an undo entry that was parked', () {
    test('🚨puts the picture back WITH its texts — the payload it parked '
        'was the drawing alone', () async {
      final live = drawingOf({a: ink, b: ink});
      final before = drawingOf({
        a: tileOf({
          (0, 0): [1, 2, 3, 255],
        }),
        b: ink,
      }).withTexts([
        textOf(1, plate: {b: letters}),
      ]);
      final snapshot = UndoSurfaceSnapshot(
        key: key,
        snapshot: before,
        sharedWith: live,
      );

      expect(await snapshot.park(), isTrue);
      expect(snapshot.isParked, isTrue, reason: 'fixture: it let go');
      final back = snapshot.surfaceOver(live);

      expect(back, before);
      expect(back!.texts.single.plate[b], same(letters));
    });

    test('a snapshot that owned no tile — a text edit, which changes none — '
        'comes back with its texts too', () async {
      final live = drawingOf({a: ink}).withTexts([
        textOf(1, words: 'after'),
      ]);
      final before = drawingOf({a: ink}).withTexts([
        textOf(1, words: 'before', plate: {b: letters}),
      ]);
      final snapshot = UndoSurfaceSnapshot(
        key: key,
        snapshot: before,
        sharedWith: live,
      );

      expect(await snapshot.park(), isTrue);
      final back = snapshot.surfaceOver(live);

      expect(back, before);
      expect(back!.texts.single.content.text, 'before');
    });
  });

  group('a canvas resize', () {
    final anchor = CanvasPoint(x: 10, y: 6);
    BitmapSurface picture() => drawingOf({a: ink}).withTexts([
      textOf(1, plate: {a: letters}, anchor: anchor),
    ]);

    test('a crop or an extension leaves a text where it stands, on the new '
        'canvas', () {
      const wider = CanvasSize(width: 64, height: 32);

      final resized = resizeBitmapSurfaceCanvas(picture(), wider);

      expect(resized.canvasSize, wider);
      expect(resized.texts.single.content.anchor, anchor);
      expect(resized.texts.single.plate[a], same(letters));
      expect(resized.tileAt(a), same(ink));
    });

    test('🚨an anchored resize moves a text exactly as it moves the '
        'drawing: the plate by the pixels\' own pass, the anchor by the '
        'same offset', () {
      // A whole tile and a part of one, so both roads of the pass run.
      for (final (dx, dy) in [(8, 16), (3, -5)]) {
        final moved = translateBitmapSurface(
          picture(),
          dx: dx,
          dy: dy,
          canvasSize: celTextTestCanvas,
        );
        // The plate alone, moved as a drawing of its own would be.
        final plateMoved = translateBitmapSurface(
          drawingOf({a: letters}),
          dx: dx,
          dy: dy,
          canvasSize: celTextTestCanvas,
        );

        final text = moved.texts.single;
        expect(text.id, 1, reason: '($dx, $dy)');
        expect(
          text.content.anchor,
          CanvasPoint(x: anchor.x + dx, y: anchor.y + dy),
          reason: '($dx, $dy)',
        );
        expect(text.plate, plateMoved.tiles, reason: '($dx, $dy)');
        expect(text.plate, isNotEmpty, reason: 'fixture: ($dx, $dy)');
        // And it is still laid over the drawing it moved with.
        expect(
          drawingOf(moved.tiles),
          translateBitmapSurface(
            drawingOf({a: ink}),
            dx: dx,
            dy: dy,
            canvasSize: celTextTestCanvas,
          ),
          reason: '($dx, $dy)',
        );
      }
    });

    test('a move that carries a text off the pasteboard cuts its plate at '
        'the wall, as it cuts the drawing — and leaves the text', () {
      final gone = translateBitmapSurface(
        picture(),
        dx: 0,
        dy: 1000,
        canvasSize: celTextTestCanvas,
      );

      expect(gone.tiles, isEmpty, reason: 'fixture: the drawing left too');
      expect(gone.texts.single.plate, isEmpty);
      expect(gone.texts.single.content.anchor, CanvasPoint(x: 10, y: 1006));
    });
  });
}
