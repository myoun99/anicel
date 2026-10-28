import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/no_worker_free.dart';

/// 🚨Card `cel-thaw-holds-the-ui-thread`: a cel still in the saved file was
/// inflated on the UI thread the moment a row's image was made — 16–19 ms a
/// cel, a cut's first play 60–70 ms at a time. Its image now waits for the
/// thaw made ahead on a worker ([BrushFrameStore.thawAhead]), and a frame's
/// maker asks for all of its cels at once. ↩️It made the frame's rows one
/// after another, each from its cel, until a frame became one picture
/// (one-picture-per-frame ②-2).
void main() {
  // 🚨The road production takes — a REAL worker. The corpus runs every
  // worker's job here ([debugWorkersRunHere]); these tests wait through
  // `runAsync`, so they can wait for one.
  setUp(() => debugWorkersRunHere = false);
  tearDown(() => debugWorkersRunHere = true);

  const canvasSize = CanvasSize(width: 8, height: 8);

  final cut = Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 1,
    canvasSize: canvasSize,
    layers: const [],
  );

  BrushFrameKey keyOf(String cel) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: cut.id,
    layerId: LayerId(cel),
    frameId: const FrameId('f'),
  );

  /// Two inked tiles of the cel's own bytes.
  BitmapSurface surfaceOf(int seed) {
    BitmapTile tile(int salt) {
      final pixels = Uint8List(4 * 4 * 4);
      for (var i = 0; i < pixels.length; i += 1) {
        pixels[i] = i % 4 == 3 ? 255 : (i * seed * 31 + salt) & 0xFF;
      }
      return BitmapTile(size: 4, pixels: pixels);
    }

    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 4,
      tiles: {TileCoord(x: 0, y: 0): tile(3), TileCoord(x: 1, y: 1): tile(7)},
    );
  }

  /// [cels] kept as an opened project keeps them: each a stretch of the
  /// saved file, cold until read.
  void keepInTheFile(BrushFrameStore store, List<String> cels) => keepInAFile(
    store,
    {for (final (index, cel) in cels.indexed) keyOf(cel): surfaceOf(index + 1)},
  );

  FramePictures picturesOf(LayerFrameImageCache images, List<String> cels) {
    final store = FramePictureStore<FramePictureKey>();
    addTearDown(store.dispose);
    return FramePictures(
      store: store,
      layerImages: images,
      stackOf: (_) => [
        for (final cel in cels)
          CompositeLeaf(
            CanvasLayerImageRequest(frameKey: keyOf(cel), opacity: 1),
          ),
      ],
      pageOf: (picture) => (
        canvasSize: picture.cut.canvasSize,
        pasteboardReach: PasteboardReach.none,
        paintPaper: picture.paintPaper,
        paperBackground: ProjectBackground.defaultBackground,
      ),
    );
  }

  /// ↩️A row's image waited for it, until no row image was made
  /// (one-picture-per-frame ②-5b-1).
  testWidgets('🚨a cel read in waits for its thaw on a worker — the cel is '
      'not read on this thread', (tester) async {
    await tester.runAsync(() async {
      final store = _ThawAsks();
      keepInTheFile(store, ['a']);
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);

      late Future<void> read;
      var answered = false;
      await whileNoWorkerIsFree(() async {
        read = images.readIn(keyOf('a'), canvasSize: canvasSize);
        unawaited(read.whenComplete(() => answered = true));
        await pumpEventQueue();
        expect(answered, isFalse, reason: 'the reading waits for the thaw');
        expect(
          store.hotBakedSurfaceOrNull(keyOf('a')),
          isNull,
          reason: 'no worker was free, and the cel was not read here',
        );
      });
      await read;
      expect(store.hotBakedSurfaceOrNull(keyOf('a')), isNotNull);
      expect(
        images.storedSurfaceIsInHand(keyOf('a'), canvasSize: canvasSize),
        isTrue,
        reason: 'its preview prepared once it is hot',
      );
    });
  });

  testWidgets('🚨a frame\'s cels thaw at once — every one is asked for before '
      'any is thawed', (tester) async {
    await tester.runAsync(() async {
      final store = _ThawAsks();
      keepInTheFile(store, ['a', 'b', 'c']);
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);
      final pictures = picturesOf(images, ['a', 'b', 'c']);

      late Future<bool> made;
      await whileNoWorkerIsFree(() async {
        made = pictures.make((
          cut: cut,
          frameIndex: 0,
          paintPaper: true,
        ), shouldAbort: () => false);
        await pumpEventQueue();
        expect(
          store.asked.toSet(),
          {keyOf('a'), keyOf('b'), keyOf('c')},
          reason: 'the frame asked for every cel before any was thawed',
        );
      });
      expect(await made, isTrue);
      for (final cel in ['a', 'b', 'c']) {
        expect(store.hotBakedSurfaceOrNull(keyOf(cel)), isNotNull);
      }
      expect(pictures.has((cut: cut, frameIndex: 0, paintPaper: true)), isTrue);
    });
  });

  /// ↩️Nor a row's image's, until no row image was made
  /// (one-picture-per-frame ②-5b-1).
  testWidgets('a maker the editor has stood down starts no thaw', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = _ThawAsks();
      keepInTheFile(store, ['a', 'b']);
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);

      expect(
        await picturesOf(images, ['a', 'b']).make((
          cut: cut,
          frameIndex: 0,
          paintPaper: true,
        ), shouldAbort: () => true),
        isFalse,
      );
      expect(store.asked, isEmpty);
    });
  });
}

/// A store that says which cels it was asked to thaw ahead, in order.
class _ThawAsks extends BrushFrameStore {
  final List<BrushFrameKey> asked = [];

  @override
  Future<void> thawAhead(
    BrushFrameKey key, {
    required CanvasSize canvasSize,
  }) {
    asked.add(key);
    return super.thawAhead(key, canvasSize: canvasSize);
  }
}
