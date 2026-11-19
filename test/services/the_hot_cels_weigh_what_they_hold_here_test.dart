import 'dart:ffi';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/hot_cel_weights.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cel_text_fixture.dart';

/// The hot cels weigh the bytes their tiles hold here, and their sum is
/// right at every read ([HotCelWeights]) — card
/// `cel-originals-are-held-twice-in-ram-and-on-the-gpu` ②. A tile the
/// engine made weighs nothing till its bytes come (`BitmapTile.ownBytes`),
/// which no store is told of: the sum is weighed again where they came,
/// by itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final a = TileCoord(x: 0, y: 0);
  final b = TileCoord(x: 1, y: 0);
  final tileBytes = BitmapTile.bytesFor(celTextTestTileSize);

  /// One pixel of ink on nothing: a tile of bytes of its own.
  BitmapTile inked(int shade) => tileOf({
    (0, 0): [shade, shade, shade, 255],
  });

  BitmapTile madeOnEngine() =>
      BitmapTile.onEngine(size: celTextTestTileSize, on: _Engine());

  /// Its bytes come here, as a read back brings them.
  void bytesComeTo(BitmapTile tile) => tile.readPixels((_, _) {});

  BrushFrameKey cel(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  group('the weights', () {
    test('are each cel\'s as it was last weighed, and none once it is let '
        'go', () {
      final weights = HotCelWeights()
        ..weigh(cel('1'), drawingOf({a: inked(1)}))
        ..weigh(cel('2'), drawingOf({a: inked(2), b: inked(3)}));

      expect(weights.bytes, 3 * tileBytes);

      weights.weigh(cel('2'), drawingOf({a: inked(4)}));

      expect(weights.bytes, 2 * tileBytes);

      weights
        ..letGo(cel('1'))
        ..letGo(cel('1'))
        ..letGo(cel('never weighed'));

      expect(weights.bytes, tileBytes);

      weights.clear();

      expect(weights.bytes, 0);
    });

    test('🚨a cel whose tile the engine made weighs that tile\'s bytes once '
        'they come here — nobody telling the weights', () {
      final landed = madeOnEngine();
      final weights = HotCelWeights()
        ..weigh(cel('1'), drawingOf({a: inked(1), b: landed}));

      expect(weights.bytes, tileBytes);

      bytesComeTo(landed);

      expect(weights.bytes, 2 * tileBytes);
    });

    test('a text\'s plate the engine made is weighed as the drawing is', () {
      final plate = madeOnEngine();
      final weights = HotCelWeights()
        ..weigh(
          cel('1'),
          drawingOf({a: inked(1)}).withTexts([
            textOf(1, plate: {a: plate}),
          ]),
        );

      expect(weights.bytes, tileBytes);

      bytesComeTo(plate);

      expect(weights.bytes, 2 * tileBytes);
    });

    test('a cel is weighed again only while a tile of it may weigh more', () {
      final first = madeOnEngine();
      final second = madeOnEngine();
      final weights = HotCelWeights()
        ..weigh(cel('made here'), drawingOf({a: inked(1)}))
        ..weigh(cel('landed'), drawingOf({a: first, b: second}));

      expect(weights.weighedAgainCount, 1);

      bytesComeTo(first);

      expect(weights.bytes, 2 * tileBytes);
      expect(weights.weighedAgainCount, 1, reason: 'one tile still to come');

      bytesComeTo(second);

      expect(weights.bytes, 3 * tileBytes);
      expect(weights.weighedAgainCount, 0);
    });

    test('a cel let go is not weighed again as its tile\'s bytes come', () {
      final landed = madeOnEngine();
      final weights = HotCelWeights()
        ..weigh(cel('1'), drawingOf({a: landed}))
        ..weigh(cel('2'), drawingOf({a: inked(1)}))
        ..letGo(cel('1'));

      bytesComeTo(landed);

      expect(weights.bytes, tileBytes);
      expect(weights.weighedAgainCount, 0);
    });

    test('a cel weighed anew weighs its new picture alone as bytes come to '
        'the one it had', () {
      final landed = madeOnEngine();
      final weights = HotCelWeights()
        ..weigh(cel('1'), drawingOf({a: landed}))
        ..weigh(cel('1'), drawingOf({a: inked(1)}));

      bytesComeTo(landed);

      expect(weights.bytes, tileBytes);
    });

    test('a weight moved to another key is that key\'s — what the key '
        'weighed gone, and the bytes still to come its own', () {
      final landed = madeOnEngine();
      final weights = HotCelWeights()
        ..weigh(cel('from'), drawingOf({a: inked(1), b: landed}))
        ..weigh(cel('to'), drawingOf({a: inked(2), b: inked(3)}))
        ..move(cel('from'), cel('to'));

      expect(weights.bytes, tileBytes);

      bytesComeTo(landed);

      expect(weights.bytes, 2 * tileBytes);

      weights
        ..move(cel('never weighed'), cel('to'))
        ..letGo(cel('from'));

      expect(weights.bytes, 2 * tileBytes, reason: 'nothing moved');

      weights.letGo(cel('to'));

      expect(weights.bytes, 0);
    });
  });

  group('a store', () {
    test('🚨weighs a hot cel\'s landed tile once its bytes come here', () {
      final landed = madeOnEngine();
      final store = BrushFrameStore()
        ..storeBakedSurface(
          celTextTestKey,
          drawingOf({a: inked(1), b: landed}),
        );

      expect(store.hotBakedBytes, tileBytes);

      bytesComeTo(landed);

      expect(store.hotBakedBytes, 2 * tileBytes);
    });

    test('lets a cel\'s weight go with the cel: one stored with nothing in '
        'it', () {
      final store = BrushFrameStore()
        ..storeBakedSurface(celTextTestKey, drawingOf({a: inked(1)}))
        ..storeBakedSurface(cel('2'), drawingOf({a: inked(2)}));

      expect(store.hotBakedBytes, 2 * tileBytes);

      store.storeBakedSurface(cel('2'), drawingOf({}));

      expect(store.hotBakedBytes, tileBytes);
    });
  });
}

/// The engine as a tile reads it: a tile of sevens.
final class _Engine implements TilePixelsOnEngine {
  @override
  void readInto(BitmapTile tile, Pointer<Uint8> into) {
    final bytes = BitmapTile.bytesFor(tile.size);
    into.asTypedList(bytes).fillRange(0, bytes, 7);
  }
}
