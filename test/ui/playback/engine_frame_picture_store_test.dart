import 'dart:async';
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
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/engine_frame_picture_store.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../../helpers/a_plugin_that_shifts.dart';
import '../../helpers/a_shown_surface.dart';
import '../../helpers/engine_screen_pins.dart';
import '../../helpers/poll_until.dart';

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

  group('🚨what its plug-ins\' steps told, a picture tells again each time '
      'it is held to be shown (EngineFramePicture.hold)', () {
    const rect = Rect.fromLTRB(-20, 10, 40, 50);
    const far = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('far'),
      frameId: FrameId('far'),
    );

    /// A row of [cel] at [at], run through [runner] — telling [told] how
    /// it went.
    CompositeLeaf<CanvasStackRow> runOf(
      BrushFrameKey at,
      FxPluginRunner runner,
      FxPluginTold told,
    ) => CompositeLeaf(
      CanvasLayerImageRequest(
        frameKey: at,
        opacity: 1,
        effects: [
          ResolvedLayerEffect(
            kind: EffectKind.plugin,
            plugin: shiftingFxPluginDescription,
            values: const [],
            run: fxPluginRunOf(runner, told: told),
          ),
        ],
      ),
    );

    StackedFrame frameOfRows(
      List<CompositeNode<CanvasStackRow>> rows,
      BitmapSurface Function(BrushFrameKey key) surfaceOf,
    ) => stackedFrameOf(
      rows,
      page: (
        canvasSize: canvas,
        pasteboardReach: PasteboardReach.whole,
        paintPaper: true,
        paperBackground: paper,
      ),
      surfaceOf: surfaceOf,
    );

    test('a patch through steps that drew, into a picture they failed on, '
        'leaves it telling that they drew', () async {
      final heard = <bool>[];
      void told({required bool failed}) => heard.add(failed);
      final store = storeOf();
      final laid = (await store.lay(
        'a',
        frameOfRows([
          runOf(key, ShiftingFxPlugin(by: 1, fails: true), told),
        ], (_) => cel(5)),
      ))!..hold();
      expect(heard.last, isTrue, reason: '⛔fixture: it failed');

      expect(
        await store.patchThrough(
          from: 'a',
          to: 'b',
          rect: rect,
          frame: frameOfRows([
            runOf(key, ShiftingFxPlugin(by: 1), told),
          ], (_) => cel(5, marked: (-20, 10, 40, 50))),
          stands: () => true,
        ),
        isTrue,
      );
      expect(store.peek('b'), same(laid), reason: '⛔premise: written in');
      expect(heard.last, isFalse, reason: '⛔premise: the step drew');

      heard.clear();
      laid.hold();
      expect(heard, [false], reason: 'held again, it tells what it holds');
      laid
        ..release()
        ..release();
    });

    test('a step another screen\'s picture is copied for tells, held, what '
        'that picture told — of a row the step did not meet as well',
        () async {
      final heard = <String, bool>{};
      void near({required bool failed}) => heard['near'] = failed;
      void farOff({required bool failed}) => heard['far'] = failed;
      // The far row's cel lies on the page's last tile alone, away from
      // where the step changes it.
      BitmapSurface surfaceOf(BrushFrameKey at, BitmapSurface nearOne) =>
          at == far ? cel(7, over: const [1]) : nearOne;
      final store = storeOf();
      final laid = (await store.lay(
        'a',
        frameOfRows(
          [
            runOf(key, ShiftingFxPlugin(by: 1), near),
            runOf(far, ShiftingFxPlugin(by: 1, fails: true), farOff),
          ],
          (at) => surfaceOf(at, cel(5, over: const [-1, 0])),
        ),
      ))!
        ..hold()
        ..hold();
      expect(heard, {'near': false, 'far': true}, reason: '⛔fixture');

      heard.clear();
      expect(
        await store.patchThrough(
          from: 'a',
          to: 'b',
          rect: rect,
          frame: frameOfRows(
            [
              runOf(key, ShiftingFxPlugin(by: 1), near),
              runOf(far, ShiftingFxPlugin(by: 1, fails: true), farOff),
            ],
            (at) => surfaceOf(
              at,
              cel(5, marked: (-20, 10, 40, 50), over: const [-1, 0]),
            ),
          ),
          stands: () => true,
        ),
        isTrue,
      );
      final copy = store.peek('b')!;
      expect(copy, isNot(same(laid)), reason: '⛔premise: a copy');
      final metFar = heard.containsKey('far');

      heard.clear();
      copy.hold();
      expect(
        heard,
        {'near': false, 'far': true},
        reason: 'the far row ${metFar ? 'was' : 'was not'} met by the step',
      );
      copy.release();
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

  // 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
  // 않고 새 장치를 열어 사본으로 되살린다」.
  group('a store whose tools went with their engine', () {
    late int opened;

    /// A store that counts each time its tools are asked for.
    EngineFramePictureStore<String> storeCountingItsTools() {
      opened = 0;
      final store = EngineFramePictureStore<String>(
        tools: () async {
          opened += 1;
          return (composite: engine.composite, letters: engine.letters);
        },
      );
      addTearDown(store.dispose);
      return store;
    }

    test('keeps no picture, answers the lays waiting with none and tells '
        'who shows one — and lays with the tools it asks for '
        'anew', () async {
      final before = GpuScreen.liveBytes;
      final store = storeCountingItsTools();
      await store.lay('a', frameOf(cel(5)));
      await store.lay('b', frameOf(cel(6)));
      final shown = store.peek('a')!.hold();
      final waiting = store.lay('c', frameOf(cel(7)));
      var went = 0;
      var waits = 0;
      store.wentWithItsTools.addListener(() => went += 1);
      store.waits.addListener(() => waits += 1);
      expect(opened, 1, reason: '⛔premise');
      expect(store.toolsAreToCome, isFalse, reason: '⛔premise');

      store.letGoWithItsTools();

      expect(await waiting, isNull);
      expect(store.holds('a'), isFalse);
      expect(store.holds('b'), isFalse);
      expect(went, 1);
      expect(waits, 1);
      expect(store.toolsOpen, isNull);
      expect(store.toolsAreToCome, isTrue);
      expect(keptSince(before), picture, reason: 'the one a screen holds');
      shown.release();
      expect(keptSince(before), 0);

      final again = await patiently(store.lay('a', frameOf(cel(5))));

      expect(opened, 2);
      expect(store.toolsAreToCome, isFalse);
      expect(shownBy(again!), laidBy(cel(5)));
    });

    test('lets go of what a lay on its way laid, answered with '
        'none', () async {
      final before = GpuScreen.liveBytes;
      final store = storeCountingItsTools();
      final laying = store.lay('a', frameOf(cel(5)));
      // Its turn comes with the tools, ahead of this.
      await store.tools;
      expect(keptSince(before), picture, reason: '⛔premise: it is laid');
      expect(store.holds('a'), isFalse, reason: '⛔premise: and on its way');

      store.letGoWithItsTools();

      expect(await laying, isNull);
      await pumpEventQueue();
      expect(store.holds('a'), isFalse);
      expect(keptSince(before), 0);
    });

    test('lays what is asked right after with the next tools, whatever '
        'turn of the last ones comes meanwhile', () async {
      final opening = <Completer<EngineFrameTools>>[];
      final store = EngineFramePictureStore<String>(
        tools: () {
          opening.add(Completer<EngineFrameTools>());
          return opening.last.future;
        },
      );
      addTearDown(store.dispose);
      final tools = (composite: engine.composite, letters: engine.letters);
      // A turn asked of tools still to come ...
      final first = store.lay('a', frameOf(cel(5)));
      store.letGoWithItsTools();
      final second = store.lay('b', frameOf(cel(6)));
      expect(opening, hasLength(2), reason: '⛔premise: asked for anew');

      // ... comes with this one in the line, the next tools not there yet.
      opening.first.complete(tools);
      await pumpEventQueue();
      opening.last.complete(tools);

      expect(await first, isNull);
      expect(shownBy((await patiently(second))!), laidBy(cel(6)));
    });

    test('why the last ones would not open is no word on what is asked '
        'right after: that is laid with the next', () async {
      final opening = <Completer<EngineFrameTools>>[];
      final store = EngineFramePictureStore<String>(
        tools: () {
          opening.add(Completer<EngineFrameTools>());
          return opening.last.future;
        },
      );
      addTearDown(store.dispose);
      final first = store.lay('a', frameOf(cel(5)));
      store.letGoWithItsTools();
      final second = store.lay('b', frameOf(cel(6)));
      expect(opening, hasLength(2), reason: '⛔premise: asked for anew');

      opening.first.completeError(StateError('the engine let go'));
      await pumpEventQueue();
      opening.last.complete(
        (composite: engine.composite, letters: engine.letters),
      );

      expect(await first, isNull);
      expect(shownBy((await patiently(second))!), laidBy(cel(6)));
    });
  });
}
