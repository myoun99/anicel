import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/frame_demand.dart'
    show DemandedPicture, FrameGhosts;
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
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/no_worker_free.dart';
import '../../helpers/poll_until.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';

/// 🚨Card `cel-thaw-holds-the-ui-thread`: a cel still in the saved file was
/// inflated on the UI thread the moment a row's image was made — 16–19 ms a
/// cel, a cut's first play 60–70 ms at a time. Its image now waits for the
/// thaw made ahead on a worker ([BrushFrameStore.thawAhead]), and a frame's
/// maker asks for all of its cels at once. ↩️It made the frame's rows one
/// after another, each from its cel, until a frame became one picture
/// (one-picture-per-frame ②-2).
///
/// 🚨Card `one-cut-of-fnk02-holds-nine-gigabytes`, Q1: a frame made AHEAD
/// of a screen looks at its cels ([BrushFrameStore.lookAhead]) — thawed on
/// workers as before, and none kept hot once its picture is made. ↩️Thawed
/// as a use, every frame's cels stood hot until the hot budget's ceiling.
void main() {
  opensTheEnginesScreens();
  // 🚨The road production takes — a REAL worker. The corpus runs every
  // worker's job here ([debugWorkersRunHere]); these tests wait through
  // `runAsync`, so they can wait for one.
  setUp(() => debugWorkersRunHere = false);
  tearDown(() => debugWorkersRunHere = true);

  // Two tiles across and two down, at the engine's side.
  const tileSide = defaultCelTileSize;
  const canvasSize = CanvasSize(width: 2 * tileSide, height: 2 * tileSide);

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
      final pixels = Uint8List(tileSide * tileSide * 4);
      for (var i = 0; i < pixels.length; i += 1) {
        pixels[i] = i % 4 == 3 ? 255 : (i * seed * 31 + salt) & 0xFF;
      }
      return BitmapTile(size: tileSide, pixels: pixels);
    }

    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSide,
      tiles: {TileCoord(x: 0, y: 0): tile(3), TileCoord(x: 1, y: 1): tile(7)},
    );
  }

  /// [cels] kept as an opened project keeps them: each a stretch of the
  /// saved file, cold until read.
  void keepInTheFile(BrushFrameStore store, List<String> cels) => keepInAFile(
    store,
    {for (final (index, cel) in cels.indexed) keyOf(cel): surfaceOf(index + 1)},
  );

  DemandedPicture frame(int index) =>
      (cut: cut, frameIndex: index, paintPaper: true, ghosts: FrameGhosts.none);

  /// Pictures of frames that each stack the cels [celsOf] names.
  FramePictures picturesOfFrames(
    LayerFrameImageCache images,
    List<String> Function(int frame) celsOf,
  ) {
    final store = aStoreOfPictures();
    addTearDown(store.dispose);
    return FramePictures(
      store: store,
      layerImages: images,
      stackOf: (picture) => [
        for (final cel in celsOf(picture.frameIndex))
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

  FramePictures picturesOf(LayerFrameImageCache images, List<String> cels) =>
      picturesOfFrames(images, (_) => cels);

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

  testWidgets('🚨a frame made ahead looks at its cels at once — every one '
      'is asked for before any is thawed, none read on this thread, and '
      'none kept hot once it is made', (tester) async {
    await tester.runAsync(() async {
      final store = _ThawAsks();
      keepInTheFile(store, ['a', 'b', 'c']);
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);
      final pictures = picturesOf(images, ['a', 'b', 'c']);

      late Future<bool> made;
      await whileNoWorkerIsFree(() async {
        made = pictures.make(frame(0), shouldAbort: () => false);
        await pumpEventQueue();
        expect(
          store.looked.toSet(),
          {keyOf('a'), keyOf('b'), keyOf('c')},
          reason: 'the frame asked for every cel before any was thawed',
        );
      });
      expect(await made, isTrue);
      expect(pictures.has(frame(0)), isTrue);
      for (final cel in ['a', 'b', 'c']) {
        expect(
          store.hotBakedSurfaceOrNull(keyOf(cel)),
          isNull,
          reason: 'a frame made ahead looks, and keeps nothing hot',
        );
        expect(store.isCelFileBacked(keyOf(cel)), isTrue);
      }
      expect(store.asked, isEmpty, reason: 'none was thawed to be kept');
      expect(store.thawedHere, isEmpty, reason: 'none was read here');
    });
  });

  testWidgets('🚨what a frame read ahead is in hand when it draws, whatever '
      'frames were made meanwhile — no cel is read on this thread', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = _ThawAsks();
      keepInTheFile(store, ['a', 'b', 'c', 'late']);
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);
      final pictures = picturesOfFrames(
        images,
        (index) => const [
          ['a'],
          ['b'],
          ['c', 'late'],
        ][index],
      );

      // The third frame has read [c] and waits for [late]…
      final gate = store.holdBack(keyOf('late'));
      final third = pictures.make(frame(2), shouldAbort: () => false);
      await store.landed(keyOf('c'));
      // …while two frames are made: the looks have gone on twice.
      expect(await pictures.make(frame(0), shouldAbort: () => false), isTrue);
      expect(await pictures.make(frame(1), shouldAbort: () => false), isTrue);
      expect(
        pictures.celsLookedAtAhead,
        hasLength(2),
        reason: 'b, for the frame after it — and c, counted while its frame '
            'still reads: the looks hold it no more',
      );
      gate.complete();

      expect(await third, isTrue);
      expect(
        store.thawedHere,
        isEmpty,
        reason: 'c was read for the third frame, and is its own until it '
            'draws',
      );
      expect(store.looked.where((cel) => cel == keyOf('c')), hasLength(1));
    });
  });

  testWidgets('🚨the frames made ahead hold the cels of the last one made '
      'and no more, and none once the walk rests', (tester) async {
    await tester.runAsync(() async {
      final store = _ThawAsks();
      keepInTheFile(store, ['a', 'b', 'c']);
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);
      final pictures = picturesOfFrames(
        images,
        (index) => const [
          ['a'],
          ['b'],
          ['c'],
        ][index],
      );

      for (final index in [0, 1, 2]) {
        expect(
          await pictures.make(frame(index), shouldAbort: () => false),
          isTrue,
        );
      }
      expect(
        pictures.celsLookedAtAhead,
        hasLength(1),
        reason: 'the last frame\'s one cel, held for the frame after it',
      );

      pictures.rest();
      expect(pictures.celsLookedAtAhead, isEmpty);
    });
  });

  testWidgets('🚨what the walk reads in for a frame is counted while it '
      'reads, whatever frames the looks go on to meanwhile', (tester) async {
    await tester.runAsync(() async {
      final store = _ThawAsks();
      keepInTheFile(store, ['a', 'b', 'c', 'late']);
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);
      final pictures = picturesOfFrames(
        images,
        (index) => const [
          ['a'],
          ['b'],
          ['c', 'late'],
        ][index],
      );

      // The third frame's cels are read in, and [late] waits…
      final gate = store.holdBack(keyOf('late'));
      final reading = pictures.readIn(frame(2));
      await store.landed(keyOf('c'));
      // …while two frames are made: the looks have gone on twice.
      expect(await pictures.make(frame(0), shouldAbort: () => false), isTrue);
      expect(await pictures.make(frame(1), shouldAbort: () => false), isTrue);

      expect(
        pictures.celsLookedAtAhead,
        hasLength(2),
        reason: 'b, for the frame after it — and c, counted while the '
            'reading in goes on: the looks hold it no more',
      );
      gate.complete();
      await reading;
    });
  });

  testWidgets('🚨there is room to ask for a frame ahead only while the hot '
      'cels and what the looks hold beside them weigh under the hot '
      'budget', (tester) async {
    await tester.runAsync(() async {
      final store = _ThawAsks();
      keepInTheFile(store, ['a']);
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);
      final pictures = picturesOf(images, ['a']);
      store.hotCelByteBudget = 1;
      expect(pictures.roomToAskAhead, isTrue, reason: '⛔premise');

      await pictures.readIn(frame(0));
      expect(store.hotBakedBytes, 0, reason: '⛔premise: looked at, not kept');
      expect(pictures.roomToAskAhead, isFalse);

      pictures.rest();
      expect(pictures.roomToAskAhead, isTrue);
    });
  });

  testWidgets('what the walk reads in ahead of a making is looked at too — '
      'held for the weighing, nothing thawed to be kept', (tester) async {
    await tester.runAsync(() async {
      final store = _ThawAsks();
      keepInTheFile(store, ['a']);
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);
      final pictures = picturesOf(images, ['a']);

      await pictures.readIn(frame(0));

      expect(store.asked, isEmpty);
      expect(store.hotBakedBytes, 0);
      expect(pictures.celsLookedAtAhead, hasLength(1));
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
        await picturesOf(images, ['a', 'b']).make(
          frame(0),
          shouldAbort: () => true,
        ),
        isFalse,
      );
      expect(store.asked, isEmpty);
      expect(store.looked, isEmpty);
    });
  });
}

/// A store that says which cels it was asked to thaw ahead to keep
/// ([asked]) and to look at ahead ([looked]), in order — and which kept
/// cels a look thawed on this thread ([thawedHere]).
class _ThawAsks extends BrushFrameStore {
  final List<BrushFrameKey> asked = [];
  final List<BrushFrameKey> looked = [];
  final List<BrushFrameKey> thawedHere = [];
  final Map<BrushFrameKey, Completer<void>> _heldBack = {};
  final Map<BrushFrameKey, Completer<void>> _landed = {};

  /// [key]'s look ahead waits until what this answers completes.
  Completer<void> holdBack(BrushFrameKey key) =>
      _heldBack[key] = Completer<void>();

  /// Completes once [key]'s look ahead has answered — at the one ceiling: a
  /// frame that reads its cels some other way never answers, and a pin
  /// waiting for it fails there instead of holding the line.
  Future<void> landed(BrushFrameKey key) =>
      patiently((_landed[key] ??= Completer<void>()).future);

  @override
  Future<void> thawAhead(
    BrushFrameKey key, {
    required CanvasSize canvasSize,
  }) {
    asked.add(key);
    return super.thawAhead(key, canvasSize: canvasSize);
  }

  @override
  Future<BitmapSurface?> lookAhead(
    BrushFrameKey key, {
    required CanvasSize canvasSize,
  }) async {
    looked.add(key);
    await _heldBack[key]?.future;
    final surface = await super.lookAhead(key, canvasSize: canvasSize);
    (_landed[key] ??= Completer<void>()).complete();
    return surface;
  }

  @override
  BitmapSurface? bakedSurfaceOrNull(
    BrushFrameKey key, {
    CelRead read = CelRead.use,
  }) {
    if (read == CelRead.look && isCelFileBacked(key) && !_isHot(key)) {
      thawedHere.add(key);
    }
    return super.bakedSurfaceOrNull(key, read: read);
  }

  bool _isHot(BrushFrameKey key) => hotBakedSurfaceOrNull(key) != null;
}
