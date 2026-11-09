import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/engine_frame_picture_store.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../../helpers/a_shown_surface.dart';
import '../../helpers/engine_screen_pins.dart';

/// 🚨★★★A FRAME'S ONE PICTURE ON THE ENGINE (flip lane ⓑ-1): the store lays
/// a frame as the engine's screen lays it, one picture a key however often
/// it is asked for, the frame on screen first and none its askers have
/// left; composes an edit into it where it changed and moves it to its new
/// key; lets go of what its budget says but what a screen pins, and frees
/// a picture once it is let go and no one showing it holds it — as the
/// engine's count of what it keeps says.
void main() {
  // The letters read their faces from the bundle.
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvas = CanvasSize(width: 256, height: 128);
  const side = 128;
  const paper = ProjectBackground.color(0xFF30A060);
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );
  // A picture of the page's two tiles and the one left of it.
  const picture = 3 * side * side * 4;
  final engine = EngineScreenPins('the engine frame picture store');

  /// A cel of [seed]'s pixels — or [seedAt]'s of each tile's column — in
  /// the tiles of [over] — the one left of the page and the page's two —,
  /// [marked] green.
  BitmapSurface cel(
    int seed, {
    int Function(int column)? seedAt,
    (int, int, int, int)? marked,
    List<int> over = const [-1, 0, 1],
  }) {
    BitmapTile tile(int column) {
      final pixels = Uint8List(side * side * 4);
      final seeded = seedAt?.call(column) ?? seed;
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final worldX = x + column * side;
          final n = worldX * 7 + y * 13 + seeded * 101;
          final green = switch (marked) {
            (final l, final t, final r, final b) =>
              worldX >= l && worldX < r && y >= t && y < b,
            null => false,
          };
          pixels.setAll(
            (y * side + x) * 4,
            green
                ? const [0, 255, 0, 255]
                : [(n * 37) & 255, (n * 23 + 91) & 255, (n * 11) & 255, 255],
          );
        }
      }
      return BitmapTile(size: side, pixels: pixels);
    }

    return BitmapSurface(
      canvasSize: canvas,
      tileSize: side,
      tiles: {
        for (final column in over) TileCoord(x: column, y: 0): tile(column),
      },
    );
  }

  StackedFrame frameOf(BitmapSurface surface) => stackedFrameOf(
    const [
      CompositeLeaf(CanvasLayerImageRequest(frameKey: key, opacity: 1)),
    ],
    page: (
      canvasSize: canvas,
      pasteboardReach: PasteboardReach.whole,
      paintPaper: true,
      paperBackground: paper,
    ),
    surfaceOf: (_) => surface,
  );

  /// What the engine's screen shows of [surface]'s frame, at rest.
  int laidBy(BitmapSurface surface) =>
      engine.shown(frameOf(surface), size: (256, 128));

  /// What [shown] shows at rest.
  int shownBy(EngineFramePicture shown) {
    final target = shownSurfaceOf(256, 128);
    addTearDown(target.free);
    shown.show(
      target,
      (256, 128),
      viewport: CanvasViewport(),
      devicePixelRatio: 1,
    );
    return target.fingerprint();
  }

  EngineFramePictureStore<String> storeOf() {
    final store = EngineFramePictureStore<String>(
      tools: () async => (
        composite: engine.composite,
        letters: engine.letters,
      ),
    );
    addTearDown(store.dispose);
    return store;
  }

  /// What the engine keeps past what it kept at [before].
  int keptSince(int before) => GpuScreen.liveBytes - before;

  test('🚨a frame laid is the frame the engine\'s screen lays', () async {
    final want = laidBy(cel(5));
    final store = storeOf();

    final laid = await store.lay('a', frameOf(cel(5)));

    expect(shownBy(laid!), want);
    expect(store.peek('a'), same(laid));
    expect(store.bytesOf('a'), picture);
    expect(store.holdsWhere((key) => key == 'a'), isTrue);
    expect(store.holdsWhere((key) => key == 'b'), isFalse);
  });

  test('a key asked for again is one picture, laid once', () async {
    final store = storeOf();
    final before = GpuScreen.liveBytes;

    final first = store.lay('a', frameOf(cel(5)));
    final again = store.lay('a', frameOf(cel(6)));

    expect(await again, same(await first));
    expect(await store.lay('a', frameOf(cel(7))), same(await first));
    expect(keptSince(before), picture, reason: 'one picture');
  });

  test('a picture there is answered at once, not behind the lays '
      'waiting', () async {
    final store = storeOf();
    await store.lay('there', frameOf(cel(5)));
    final answered = <String>[];

    await Future.wait([
      store
          .lay('waiting', frameOf(cel(6)))
          .then((_) => answered.add('waiting')),
      store.lay('there', frameOf(cel(5))).then((_) => answered.add('there')),
    ]);

    expect(answered, ['there', 'waiting']);
  });

  /// The keys [store] lays as [asked] for them, in the order they are laid.
  Future<List<String>> laidInTurn(
    EngineFramePictureStore<String> store,
    List<(String, {bool shownNow})> asked,
  ) async {
    final laid = <String>[];
    await Future.wait([
      for (final (key, :shownNow) in asked)
        store
            .lay(key, frameOf(cel(5)), shownNow: shownNow)
            .then((_) => laid.add(key)),
    ]);
    return laid;
  }

  test('the frame on screen is laid before the ones made ahead', () async {
    final laid = await laidInTurn(storeOf(), [
      ('ahead', shownNow: false),
      ('shown', shownNow: true),
    ]);

    expect(laid, ['shown', 'ahead']);
  });

  test('a frame waiting its turn goes to the front once the screen asks for '
      'it', () async {
    final laid = await laidInTurn(storeOf(), [
      ('ahead', shownNow: false),
      ('shown', shownNow: false),
      ('shown', shownNow: true),
    ]);

    expect(laid, ['shown', 'shown', 'ahead']);
  });

  test('🗣️F-529: a lay every asker has left is not made', () async {
    final store = storeOf();
    final before = GpuScreen.liveBytes;

    final laid = await store.lay('a', frameOf(cel(5)), gone: () => true);

    expect(laid, isNull);
    expect(store.holds('a'), isFalse);
    expect(keptSince(before), 0);
  });

  test('🗣️F-529: a lay one of its askers still wants is made', () async {
    final store = storeOf();

    final left = store.lay('a', frameOf(cel(5)), gone: () => true);
    final stays = store.lay('a', frameOf(cel(5)));

    expect(await stays, isNotNull);
    expect(await left, same(await stays));
  });

  test('a frame the engine refuses is answered with its reason, and the lays '
      'after it are laid', () async {
    final store = storeOf();
    final refused = stackedFrameOf(
      const [
        CompositeOpaque(
          CompositeLeaf(CanvasLayerImageRequest(frameKey: key, opacity: 1)),
        ),
      ],
      page: (
        canvasSize: canvas,
        pasteboardReach: PasteboardReach.whole,
        paintPaper: true,
        paperBackground: paper,
      ),
      surfaceOf: (_) => cel(5),
    );

    final failing = store.lay('refused', refused);
    final next = store.lay('next', frameOf(cel(5)));

    await expectLater(failing, throwsStateError);
    expect(await next, isNotNull);
    expect(store.holds('refused'), isFalse);
  });

  test('a key a picture moves to while its lay waits answers with that '
      'picture', () async {
    final store = storeOf();
    final before = GpuScreen.liveBytes;
    final moved = await store.lay('a', frameOf(cel(5)));
    final waiting = store.lay('b', frameOf(cel(6)));

    store.move(from: 'a', to: 'b');

    expect(await waiting, same(moved));
    expect(keptSince(before), picture, reason: 'one picture');
  });

  test('🚨a patch composes the frame where it changed, and moves the picture '
      'to its key', () async {
    final store = storeOf();
    final laid = await store.lay('a', frameOf(cel(5)));
    const marked = (-20, 10, 40, 50);
    final changed = cel(5, marked: marked);
    var told = 0;
    laid!.addListener(() => told += 1);

    expect(
      store.patch(
        from: 'a',
        to: 'b',
        rect: const Rect.fromLTRB(-20, 10, 40, 50),
        frame: frameOf(changed),
      ),
      isTrue,
    );

    expect(store.holds('a'), isFalse);
    expect(store.peek('b'), same(laid));
    expect(shownBy(laid), laidBy(changed));
    expect(told, 1, reason: 'what it shows changed');
  });

  group('a step on its way to another key', () {
    const marked = (-20, 10, 40, 50);
    const rect = Rect.fromLTRB(-20, 10, 40, 50);
    final routes = <String, Future<bool> Function(
      EngineFramePictureStore<String> store,
      StackedFrame frame,
    )>{
      'patch': (store, frame) async =>
          store.patch(from: 'a', to: 'b', rect: rect, frame: frame),
      'patchThrough': (store, frame) => store.patchThrough(
        from: 'a',
        to: 'b',
        rect: rect,
        frame: frame,
        stands: () => true,
      ),
    };

    for (final MapEntry(key: route, value: write) in routes.entries) {
      test('🚨through $route, leaves a picture another screen shows as it '
          'was, and the step is in a copy under the key', () async {
        final store = storeOf();
        final want = laidBy(cel(5));
        final laid = (await store.lay('a', frameOf(cel(5))))!
          ..hold()
          ..hold();
        var told = 0;
        laid.addListener(() => told += 1);
        final changed = cel(5, marked: marked);

        expect(await write(store, frameOf(changed)), isTrue);

        expect(store.peek('a'), same(laid), reason: 'the other screen\'s');
        expect(shownBy(laid), want);
        expect(told, 0, reason: 'what it shows did not change');
        final copy = store.peek('b')!;
        expect(copy, isNot(same(laid)));
        expect(shownBy(copy), laidBy(changed));
        laid
          ..release()
          ..release();
      });

      test('through $route, goes into a picture only its writer shows',
          () async {
        final store = storeOf();
        final laid = (await store.lay('a', frameOf(cel(5))))!..hold();
        var told = 0;
        laid.addListener(() => told += 1);
        final changed = cel(5, marked: marked);

        expect(await write(store, frameOf(changed)), isTrue);

        expect(store.holds('a'), isFalse);
        expect(store.peek('b'), same(laid));
        expect(shownBy(laid), laidBy(changed));
        expect(told, 1);
        laid.release();
      });
    }

    test('under the one key, is written in for every screen showing it — '
        'a picture under a key is that key\'s', () async {
      final store = storeOf();
      final laid = (await store.lay('a', frameOf(cel(5))))!
        ..hold()
        ..hold();
      var told = 0;
      laid.addListener(() => told += 1);
      final changed = cel(5, marked: marked);

      store.patch(from: 'a', to: 'a', rect: rect, frame: frameOf(changed));

      expect(store.peek('a'), same(laid));
      expect(shownBy(laid), laidBy(changed));
      expect(told, 1);
      laid
        ..release()
        ..release();
    });
  });

  test('🚨a frame laid over a film is the film\'s picture where it is not '
      'fresh, and its own frame where it is', () async {
    final store = storeOf();
    await store.lay('film', frameOf(cel(5)));

    // Fresh over the page's first tile alone.
    final laid = await store.lay(
      'ghosts',
      frameOf(cel(6)),
      over: (film: 'film', fresh: const Rect.fromLTRB(10, 10, 20, 20)),
    );

    final mixed = cel(5, seedAt: (column) => column == 0 ? 6 : 5);
    expect(shownBy(laid!), laidBy(mixed));
    expect(store.bytesOf('ghosts'), picture);
  });

  test('a frame laid over a film not there is laid whole', () async {
    final store = storeOf();

    final laid = await store.lay(
      'ghosts',
      frameOf(cel(6)),
      over: (film: 'gone', fresh: const Rect.fromLTRB(10, 10, 20, 20)),
    );

    expect(shownBy(laid!), laidBy(cel(6)));
  });

  test('a patch composes nothing where it is not told the frame '
      'changed', () async {
    final store = storeOf();
    final laid = await store.lay('a', frameOf(cel(5)));

    store.patch(
      from: 'a',
      to: 'a',
      rect: const Rect.fromLTRB(10, 10, 20, 20),
      frame: frameOf(cel(5, marked: (200, 60, 220, 80))),
    );

    expect(shownBy(laid!), laidBy(cel(5)));
  });

  test('a patch of a frame over another world composes it whole', () async {
    final store = storeOf();
    final laid = await store.lay('a', frameOf(cel(5)));
    final within = cel(5, over: const [0, 1]);

    store.patch(
      from: 'a',
      to: 'a',
      rect: const Rect.fromLTRB(10, 10, 20, 20),
      frame: frameOf(within),
    );

    expect(shownBy(laid!), laidBy(within));
    expect(store.bytesOf('a'), 2 * side * side * 4, reason: 'its world');
  });

  test('a patch or a move from a key that holds nothing answers false', () {
    final store = storeOf();

    expect(
      store.patch(
        from: 'none',
        to: 'b',
        rect: const Rect.fromLTRB(0, 0, 1, 1),
        frame: frameOf(cel(5)),
      ),
      isFalse,
    );
    expect(store.move(from: 'none', to: 'b'), isFalse);
    expect(store.holds('b'), isFalse);
  });

  test('a move gives the picture to its key, and lets go of the one that '
      'answered to it', () async {
    final store = storeOf();
    final before = GpuScreen.liveBytes;
    final moving = await store.lay('a', frameOf(cel(5)));
    await store.lay('b', frameOf(cel(6)));

    expect(store.move(from: 'a', to: 'b'), isTrue);

    expect(store.holds('a'), isFalse);
    expect(store.peek('b'), same(moving));
    expect(keptSince(before), picture, reason: 'the one there let go');
  });

  test('the budget lets go of what it must but a picture a screen '
      'pins', () async {
    final store = storeOf();
    await store.lay('pinned', frameOf(cel(5)));
    await store.lay('ahead', frameOf(cel(6)));
    store.retainPin('pinned');
    addTearDown(() => store.releasePin('pinned'));

    store.enforceBudget(maxBytes: 0);

    expect(store.holds('pinned'), isTrue);
    expect(store.holds('ahead'), isFalse);
    expect(store.pinnedBytes, picture);
    expect(store.estimatedBytes, picture);
  });

  test('the budget lets go of the picture wanted latest first, the one '
      'shown least lately among equals, and none wanted that soon', () async {
    final store = storeOf();
    for (final (key, seed) in [('a', 5), ('b', 6), ('c', 7)]) {
      await store.lay(key, frameOf(cel(seed)));
    }
    store.peek('a');

    store.enforceBudget(maxBytes: 2 * picture);
    expect([for (final key in 'abc'.split('')) store.holds(key)], [
      true,
      false,
      true,
    ], reason: 'b shown least lately');

    store.enforceBudget(
      maxBytes: picture,
      wantedAt: (key) => key == 'a' ? 9 : 1,
    );
    expect(store.holds('a'), isFalse, reason: 'a wanted latest');

    expect(
      store.enforceBudget(maxBytes: 0, wantedAt: (_) => 1, laterThan: 1),
      isFalse,
    );
    expect(store.holds('c'), isTrue, reason: 'c wanted that soon');
  });

  test('a picture a screen pins is let go of only once no screen '
      'does', () async {
    final store = storeOf();
    for (final (key, seed) in [('pinned', 5), ('dead', 6), ('alive', 7)]) {
      await store.lay(key, frameOf(cel(seed)));
    }
    store.retainPin('pinned');

    store
      ..letGoUnpinned('pinned')
      ..letGoUnpinnedWhere((key) => key != 'alive');

    expect(store.holds('pinned'), isTrue);
    expect(store.holds('dead'), isFalse);
    expect(store.holds('alive'), isTrue);
    store
      ..releasePin('pinned')
      ..letGoUnpinned('pinned');
    expect(store.holds('pinned'), isFalse);
  });

  test('🚨a picture let go while a screen holds it stays to be shown, and '
      'goes at the last release', () async {
    final store = storeOf();
    final want = laidBy(cel(5));
    final before = GpuScreen.liveBytes;
    final laid = (await store.lay('a', frameOf(cel(5))))!..hold();

    store.letGo('a');

    expect(laid.gone, isTrue);
    expect(store.holds('a'), isFalse);
    expect(shownBy(laid), want);
    expect(keptSince(before), picture, reason: 'held');
    laid.release();
    expect(keptSince(before), 0, reason: 'released');
    expect(
      () => laid.addListener(() {}),
      throwsFlutterError,
      reason: 'a picture freed is told to no one',
    );
  });

  test('a store let go of keeps nothing, and answers the lays waiting with '
      'none', () async {
    final before = GpuScreen.liveBytes;
    final store = EngineFramePictureStore<String>(
      tools: () async => (
        composite: engine.composite,
        letters: engine.letters,
      ),
    );
    await store.lay('a', frameOf(cel(5)));
    await store.lay('b', frameOf(cel(6)));
    final waiting = store.lay('c', frameOf(cel(7)));

    store.dispose();

    expect(await waiting, isNull);
    expect(keptSince(before), 0);
    expect(store.holds('a'), isFalse);
  });
}
