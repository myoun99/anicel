import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/composite_tree_plan.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/native/screen_texture.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/debug/screen_asked.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../helpers/a_shown_surface.dart';
import '../helpers/engine_screen_pins.dart';


/// 🚨THE ENGINE'S SCREEN SHOWS THE FRAME IT KEEPS (screen-on-the-engine c6
/// ④, 관제 11-08 14:19): a frame laid on the engine's screen
/// ([EngineStackScreen]) and shown through the view's camera is, byte for
/// byte, the same frame laid by the translator and run on the engine
/// ([GpuComposite.run]) — at rest, moved and shrunk at twice the pixels,
/// turned a quarter — the pasteboard left of the page among it, and again
/// after a change composed where it lies. ↩️Not against the walk's screen:
/// 「지금화면이랑 맞출필요는없어 … 바뀌고 나서만 동일하면되」(유저 11-08, 관제가
/// 전함).
///
/// 🚨AND SHOWN AGAIN ON THE TARGET THAT HOLDS IT, IT IS DRAWN WHERE IT WAS
/// MADE AGAIN ALONE — the target showing, byte for byte, what one drawn
/// whole shows. 🗣️유저 2026-11-21, on a Galaxy Tab (card
/// the-galaxy-tab-canvas-went-slow-on-build-1095): 「캔버스조작, 즉 팬이나
/// 줌이나 스트로크가 너무 느려졋어」. ↩️Every frame drew every texel of its
/// target, a stroke's step as a zoom's.

/// A view a case shows through: where each device pixel's middle lands on
/// the world ([canvasAt]), and the surface's size.
typedef View = ({
  String name,
  CanvasViewport viewport,
  double devicePixelRatio,
  (int, int) size,
  (int, int) Function(int x, int y) canvasAt,
});

/// A camera a frame is shown again through, and its target's texels —
/// with what it draws of each tile changed in turn, columns by rows, null
/// where nothing: the page's first, its second and the one past it.
/// [drawn] is null where the camera's edges are no whole texels, and a
/// rounding tells which side of one they fall.
typedef Camera = ({
  String name,
  CanvasViewport viewport,
  double devicePixelRatio,
  (int, int) size,
  List<(int, int)?>? drawn,
});

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
  // The cel's tiles: one left of the page, on the pasteboard, and the
  // page's two.
  const columns = [-1, 0, 1];
  // What the frame holds: the page and the tile past it.
  const world = (-side, 0, 2 * side, side);
  final engine = EngineScreenPins('the engine screen shows the frame it keeps');

  /// A cel of [seed]'s pixels in the tiles of [over], [marked] green: on the
  /// page alphas of every kind over the paper, past it whole or none —
  /// there they lie over nothing, as the screen shows them premultiplied.
  BitmapSurface cel(
    int seed, {
    (int, int, int, int)? marked,
    List<int> over = columns,
  }) {
    BitmapTile tile(int column) {
      final pixels = Uint8List(side * side * 4);
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final at = (y * side + x) * 4;
          final worldX = x + column * side;
          final n = worldX * 7 + y * 13 + seed * 101;
          final band = ((worldX + seed * 9) ~/ 16 + y ~/ 32) % 4;
          final alpha = column < 0
              ? (band.isEven ? 0 : 255)
              : switch (band) {
                  0 => 0,
                  1 => 255,
                  2 => 96 + (n & 63),
                  _ => 200 + (n & 31),
                };
          final green = switch (marked) {
            (final l, final t, final r, final b) =>
              worldX >= l && worldX < r && y >= t && y < b,
            null => false,
          };
          pixels.setAll(at, switch ((alpha, green)) {
            (0, _) => const [0, 0, 0, 0],
            (_, true) => [0, 255, 0, alpha],
            _ => [(n * 37) & 255, (n * 23 + 91) & 255, (n * 11) & 255, alpha],
          });
        }
      }
      return BitmapTile(size: side, pixels: pixels);
    }

    return BitmapSurface(
      canvasSize: canvas,
      tileSize: side,
      tiles: {
        for (final column in over)
          TileCoord(x: column, y: 0): tile(column),
      },
    );
  }

  List<CompositeNode<CanvasStackRow>> rows() => [
    const CompositeLeaf(CanvasLayerImageRequest(frameKey: key, opacity: 1)),
  ];

  StackedFrame frameOf(BitmapSurface surface) => stackedFrameOf(
    rows(),
    page: (
      canvasSize: canvas,
      pasteboardReach: PasteboardReach.whole,
      paintPaper: true,
      paperBackground: paper,
    ),
    surfaceOf: (_) => surface,
  );

  /// The pixel at (x, y) of the world [surface] lays: the paper and the
  /// cel over it, laid by the translator and run on the engine — nothing
  /// outside the world.
  List<int> Function(int x, int y) ranOver(BitmapSurface surface) {
    final ledger = EngineTileLedger.instance;
    final tree = <CompositeNode<EngineRow>>[
      CompositeLeaf(
        EngineSolid(
          argb: paper.paintedArgb,
          rect: DirtyRegion.fromLTBR(
            left: 0,
            top: 0,
            rightExclusive: canvas.width,
            bottomExclusive: canvas.height,
          ),
        ),
      ),
      CompositeLeaf(
        EngineTiles(lineage: key.cel, surface: surface, opacity: 1),
      ),
    ];
    final tiles = ledger.held((hold) {
      final plan = GpuPlan(engine.composite.engine);
      addTearDown(plan.free);
      planCompositeTree(
        plan,
        tree,
        hold: hold,
        paper: canvas.canvasRect,
        letters: engine.letters,
      );
      final out = engine.composite.run(ledger.pool, plan, [
        for (final column in columns) (column, 0),
      ], world);
      addTearDown(out.free);
      return out.read();
    });
    return (x, y) {
      final (left, top, right, bottom) = world;
      if (x < left || x >= right || y < top || y >= bottom) {
        return const [0, 0, 0, 0];
      }
      final tile = columns.indexOf((x / side).floor());
      final at = (tile * side * side + y * side + x % side) * 4;
      return tiles.sublist(at, at + 4);
    };
  }

  /// The views the cases show through.
  final views = <View>[
    (
      name: 'at rest',
      viewport: CanvasViewport(),
      devicePixelRatio: 1,
      size: (2 * side, side),
      canvasAt: (x, y) => (x, y),
    ),
    // Half the zoom at twice the pixels is 100% again, the page's
    // corner 32 logical pixels in and 3 up: a texel a canvas pixel.
    (
      name: 'moved and shrunk at twice the pixels',
      viewport: CanvasViewport(zoom: 0.5, panX: 32, panY: -3),
      devicePixelRatio: 2,
      size: (160, 100),
      canvasAt: (x, y) => (x - 64, y + 6),
    ),
    (
      name: 'turned a quarter',
      viewport: CanvasViewport(panX: 128, rotationDegrees: 90),
      devicePixelRatio: 1,
      size: (side, 2 * side),
      canvasAt: (x, y) => (y, 127 - x),
    ),
    // Twice the zoom samples Nearest, as the walk does over 100%.
    (
      name: 'magnified twice',
      viewport: CanvasViewport(zoom: 2, panX: -64, panY: -10),
      devicePixelRatio: 1,
      size: (side, 64),
      canvasAt: (x, y) => ((x + 64) ~/ 2, (y + 10) ~/ 2),
    ),
  ];

  /// What [surface] of [size] shows of [pixel] through [canvasAt], in the
  /// surface's channel order.
  Uint8List expected(
    GpuSurface surface,
    (int, int) size,
    (int, int) Function(int x, int y) canvasAt,
    List<int> Function(int x, int y) pixel,
  ) {
    final (width, height) = size;
    final bytes = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final (cx, cy) = canvasAt(x, y);
        final [r, g, b, a] = pixel(cx, cy);
        bytes.setAll(
          (y * width + x) * 4,
          surface.bgra ? [b, g, r, a] : [r, g, b, a],
        );
      }
    }
    return bytes;
  }

  /// [screen] shown through each of [views] is [pixel] through it.
  void showsThrough(
    EngineStackScreen screen,
    List<int> Function(int x, int y) pixel,
    Iterable<View> views,
  ) {
    for (final view in views) {
      final (width, height) = view.size;
      final target = shownSurfaceOf(width, height);
      addTearDown(target.free);
      screen.show(
        target,
        view.size,
        viewport: view.viewport,
        devicePixelRatio: view.devicePixelRatio,
      );
      final want = expected(target, view.size, view.canvasAt, pixel);

      expect(target.fingerprint(), fingerprintBytes(want), reason: view.name);
    }
  }

  /// [rect] as a rectangle of the world.
  Rect rectOf((int, int, int, int) rect) {
    final (left, top, right, bottom) = rect;
    return Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right.toDouble(),
      bottom.toDouble(),
    );
  }

  test('the screen shows the frame the engine lays, through the '
      'view', () async {
    final screen = EngineStackScreen(engine.composite, engine.letters);
    addTearDown(screen.free);
    final surface = cel(3);
    await screen.compose(frameOf(surface));

    showsThrough(screen, ranOver(surface), views);
  });

  // A change composed where it lies shows, at rest and past the page alike:
  // a mark across the page's left edge, told where it changed; and a frame
  // told nothing of where is laid everywhere.
  test('a change composed where it lies is the frame the engine '
      'lays', () async {
    final screen = EngineStackScreen(engine.composite, engine.letters);
    addTearDown(screen.free);
    await screen.compose(frameOf(cel(5)));
    const marked = (-20, 10, 40, 50);
    final changed = cel(5, marked: marked);
    await screen.compose(frameOf(changed), changed: rectOf(marked));

    showsThrough(screen, ranOver(changed), views.take(2));

    final another = cel(7);
    await screen.compose(frameOf(another));

    showsThrough(screen, ranOver(another), views.take(2));
  });

  // A change the screen is not told of is kept as it was: the frame is
  // made again where it is told it changed, not everywhere.
  test('a change not told of is not composed', () async {
    final screen = EngineStackScreen(engine.composite, engine.letters);
    addTearDown(screen.free);
    final before = cel(5);
    await screen.compose(frameOf(before));
    final marked = cel(5, marked: (200, 60, 220, 80));
    await screen.compose(frameOf(marked), changed: rectOf((10, 10, 20, 20)));

    showsThrough(screen, ranOver(before), views.take(1));
    expect(
      ranOver(marked)(210, 70),
      isNot(ranOver(before)(210, 70)),
      reason: 'the mark not told of is one the frame shows',
    );
  });

  // A frame of another world — its pasteboard tile wiped — is laid on a
  // screen of that world, whole: nothing of the world kept before shows.
  test('a frame of another world is laid whole', () async {
    final screen = EngineStackScreen(engine.composite, engine.letters);
    addTearDown(screen.free);
    await screen.compose(frameOf(cel(5)));
    final within = cel(5, over: const [0, 1]);
    await screen.compose(frameOf(within), changed: rectOf((10, 10, 20, 20)));

    showsThrough(screen, ranOver(within), views.take(2));
  });

  // A frame laid over a film is its own frame on the tile it is fresh on —
  // the page's first — and the film's as it is on the others, the
  // pasteboard's and the page's second, through every view.
  test('a frame laid over a film is the film but where it is fresh', () async {
    final film = EngineStackScreen(engine.composite, engine.letters);
    addTearDown(film.free);
    final under = cel(5);
    await film.compose(frameOf(under));
    final screen = EngineStackScreen(engine.composite, engine.letters);
    addTearDown(screen.free);
    final frame = cel(7);

    await screen.composeOver(
      frameOf(frame),
      over: (film: film, fresh: rectOf((10, 10, 20, 20))),
    );

    final (mine, theirs) = (ranOver(frame), ranOver(under));
    showsThrough(
      screen,
      (x, y) => (x / side).floor() == 0 ? mine(x, y) : theirs(x, y),
      views,
    );
  });

  // Over a film nothing is laid on, a frame is laid whole; onto a screen
  // laid on already, a frame over a film is refused with the engine's
  // reason.
  test('a frame over a film of nothing is laid whole, and over a film onto '
      'a screen laid already refused', () async {
    final film = EngineStackScreen(engine.composite, engine.letters);
    addTearDown(film.free);
    final screen = EngineStackScreen(engine.composite, engine.letters);
    addTearDown(screen.free);
    final frame = cel(7);
    final fresh = rectOf((10, 10, 20, 20));

    await screen.composeOver(frameOf(frame), over: (film: film, fresh: fresh));

    showsThrough(screen, ranOver(frame), views.take(1));
    await film.compose(frameOf(cel(5)));
    await expectLater(
      screen.composeOver(frameOf(frame), over: (film: film, fresh: fresh)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'why',
          contains('before anything is composed'),
        ),
      ),
    );
  });

  // What the screen keeps is its world's tiles — the page's two and the one
  // past it — and nothing more however far it is shown reduced (↩️the
  // halvings it showed through under 1/16 besides, till 2026-11-19:
  // F-610-Q4, 유저 「6.25밑에서 두번째소재 만들고 들고있는게 별로잖아」);
  // a frame of another world is kept on that world's tiles alone.
  test('the screen keeps the bytes of the world it lays, and nothing more '
      'shown far reduced', () async {
    final screen = EngineStackScreen(engine.composite, engine.letters);
    addTearDown(screen.free);
    expect(screen.bytes, 0, reason: 'nothing laid');
    const tile = side * side * 4;
    await screen.compose(frameOf(cel(5)));
    expect(screen.bytes, 3 * tile);

    final target = shownSurfaceOf(64, 48);
    addTearDown(target.free);
    screen.show(
      target,
      (64, 48),
      viewport: CanvasViewport(zoom: 1 / 32),
      devicePixelRatio: 1,
    );
    // Told by the show once it has run on the engine's thread.
    await engine.composite.engine.done();
    expect(screen.bytes, 3 * tile, reason: 'the one composite, read far');

    await screen.compose(frameOf(cel(5, over: const [0, 1])));
    expect(screen.bytes, 2 * tile, reason: 'another world');
  });

  // What a show asked is told for the frame statistics ([ScreenAsked]):
  // the texels it drew — all of a target nothing was drawn on —, the
  // display's scale — the zoom by the device's ratio — and the mode the
  // display's law picks by it, Blend under 100% and Nearest from it.
  test('a show tells what it asked of the engine: its texels, the '
      'display\'s scale and the mode by it', () async {
    final screen = EngineStackScreen(engine.composite, engine.letters);
    addTearDown(screen.free);
    addTearDown(ScreenAsked.debugForget);
    await screen.compose(frameOf(cel(3)));
    ScreenAsked.debugForget();
    expect(ScreenAsked.last, isNull, reason: 'none shown yet');

    for (final (zoom, ratio, size, mode) in const [
      (0.5, 1.5, (96, 40), GpuSampling.blend),
      (0.5, 2.0, (40, 96), GpuSampling.nearest),
    ]) {
      final (width, height) = size;
      final target = shownSurfaceOf(width, height);
      addTearDown(target.free);
      screen.show(
        target,
        size,
        viewport: CanvasViewport(zoom: zoom),
        devicePixelRatio: ratio,
      );

      expect(ScreenAsked.last, (
        columns: width,
        rows: height,
        texels: width * height,
        moved: null,
        scale: zoom * ratio,
        mode: mode,
      ));
    }
  });

  // 🚨SHOWN AGAIN ON THE TARGET THAT HOLDS IT, A FRAME IS DRAWN WHERE IT
  // WAS MADE AGAIN ALONE ([EngineStackScreen.show]) — and what the target
  // shows then is, byte for byte, what one drawn whole shows.
  group('shown again on the target that holds it,', () {
    setUp(ScreenAsked.debugForget);
    tearDown(ScreenAsked.debugForget);

    /// A cel whose tiles are [cel]'s of the seeds [seeds] name, column by
    /// column — those of the columns [over] alone: a tile of another seed
    /// differs over all of it.
    BitmapSurface celOf(List<int> seeds, {List<int> over = columns}) =>
        BitmapSurface(
          canvasSize: canvas,
          tileSize: side,
          tiles: {
            for (final column in over)
              TileCoord(x: column, y: 0): cel(
                seeds[columns.indexOf(column)],
                over: [column],
              ).tileAt(TileCoord(x: column, y: 0))!,
          },
        );

    /// What [screen] shows through [camera] on a target drawn whole — one
    /// nothing was drawn on.
    int whole(EngineStackScreen screen, Camera camera) {
      final (width, height) = camera.size;
      final target = shownSurfaceOf(width, height);
      try {
        screen.show(
          target,
          camera.size,
          viewport: camera.viewport,
          devicePixelRatio: camera.devicePixelRatio,
        );
        return target.fingerprint();
      } finally {
        target.free();
      }
    }

    /// Shows [screen] through [camera] on [target]: what it asked of the
    /// engine — null where it drew nothing ([ScreenAsked]).
    ScreenAsk? askedOn(
      GpuSurface target,
      EngineStackScreen screen,
      Camera camera,
    ) {
      ScreenAsked.debugForget();
      screen.show(
        target,
        camera.size,
        viewport: camera.viewport,
        devicePixelRatio: camera.devicePixelRatio,
      );
      return ScreenAsked.last;
    }

    /// Shows [screen] through [camera] on [target]: the box round the
    /// texels it drew, columns by rows — null where none.
    (int, int)? drawnOn(
      GpuSurface target,
      EngineStackScreen screen,
      Camera camera,
    ) => switch (askedOn(target, screen, camera)) {
      null => null,
      final asked => (asked.columns, asked.rows),
    };

    // A target with room past what the camera shows of the world: drawn
    // whole, it is more texels than the world's tiles land on.
    const roomy = (300, 140);
    final Camera withRoom = (
      name: 'at rest, with room',
      viewport: CanvasViewport(),
      devicePixelRatio: 1,
      size: roomy,
      drawn: const [(128, 128), (128, 128), null],
    );
    // A lay told of a corner of the page's first tile, and of its second.
    final inTheFirst = rectOf((10, 10, 20, 20));
    final inTheSecond = rectOf((200, 60, 210, 70));

    // What the file's views draw of each tile, where their edges are
    // whole texels.
    const drawnThrough = <String, List<(int, int)?>>{
      'at rest': [(128, 128), (128, 128), null],
      'moved and shrunk at twice the pixels': [(96, 100), null, (64, 100)],
      'magnified twice': [(128, 64), null, null],
    };
    // Under 100% the display's law reads Blend, a texel a tent over what
    // it spans: one beside a tile reads into it. What is drawn is the
    // tile and 16 pixels round it ([GpuSampling.reach]).
    final Camera half = (
      name: 'shrunk to a half',
      viewport: CanvasViewport(zoom: 0.5),
      devicePixelRatio: 1,
      size: (160, 64),
      drawn: const [(72, 64), (80, 64), (8, 64)],
    );
    final cameras = <Camera>[
      withRoom,
      // Under the world: its tiles' columns are on the target, none of
      // their rows.
      (
        name: 'at rest, under the world',
        viewport: CanvasViewport(panY: -140),
        devicePixelRatio: 1,
        size: (300, 20),
        drawn: const [null, null, null],
      ),
      for (final view in views)
        (
          name: view.name,
          viewport: view.viewport,
          devicePixelRatio: view.devicePixelRatio,
          size: view.size,
          drawn: drawnThrough[view.name],
        ),
      // A camera turned is snapped to no device pixel
      // (`renderSnappedViewport`): a tile's edges lie a part of a texel
      // in — under the half a quarter round, over it turned over, where
      // the world's left lands right of its right and its top under its
      // bottom.
      (
        name: 'turned a quarter, under half a pixel in',
        viewport: CanvasViewport(panX: 128.3, panY: 0.4, rotationDegrees: 90),
        devicePixelRatio: 1,
        size: (132, 260),
        drawn: null,
      ),
      (
        name: 'turned over, over half a pixel in',
        viewport: CanvasViewport(
          panX: 256.7,
          panY: 128.7,
          rotationDegrees: 180,
        ),
        devicePixelRatio: 1,
        size: (260, 132),
        drawn: null,
      ),
      half,
      (
        name: 'shrunk to a tenth',
        viewport: CanvasViewport(zoom: 0.1),
        devicePixelRatio: 1,
        size: (32, 16),
        drawn: const [(15, 15), (17, 15), (2, 15)],
      ),
    ];

    // Each tile is changed in turn — all of it, a tile of another seed,
    // though the lay is told of a corner of it: a lay makes again the
    // tiles its rect meets, whole (`Screen::compose`), and what a target
    // holds of them is what is drawn again. No lay is waited for before
    // its show, as a canvas's is not (`_LiveCelScreenState._show`).
    test('it is the frame drawn whole, byte for byte, through every '
        'camera — drawn where its tiles were made again alone', () async {
      final lays = [
        (const [5, 7, 5], inTheFirst),
        (const [5, 7, 9], inTheSecond),
        (const [3, 7, 9], rectOf((-100, 10, -90, 20))),
      ];
      for (final camera in cameras) {
        final screen = EngineStackScreen(engine.composite, engine.letters);
        final (width, height) = camera.size;
        final target = shownSurfaceOf(width, height);
        try {
          await screen.compose(frameOf(celOf(const [5, 5, 5])));
          expect(
            drawnOn(target, screen, camera),
            camera.size,
            reason: '${camera.name}: all of it, the first time',
          );
          final drawn = <(int, int)?>[];
          for (final (seeds, told) in lays) {
            final laid = screen.compose(frameOf(celOf(seeds)), changed: told);
            drawn.add(drawnOn(target, screen, camera));
            await laid;
            expect(
              target.fingerprint(),
              whole(screen, camera),
              reason: '${camera.name}: tiles of the seeds $seeds',
            );
          }
          expect(
            drawn,
            camera.drawn ?? isNot(contains(camera.size)),
            reason: '${camera.name}: what it drew of each tile — where '
                'not told to the texel, never all of the target',
          );
        } finally {
          target.free();
          screen.free();
        }
      }
    });

    test('nothing is drawn where nothing was made again — nor for a lay '
        'over no pixel', () async {
      final screen = EngineStackScreen(engine.composite, engine.letters);
      addTearDown(screen.free);
      final target = shownSurfaceOf(300, 140);
      addTearDown(target.free);
      final reduced = shownSurfaceOf(160, 64);
      addTearDown(reduced.free);
      await screen.compose(frameOf(celOf(const [5, 5, 5])));
      expect(drawnOn(target, screen, withRoom), roomy);
      expect(drawnOn(reduced, screen, half), half.size);

      expect(drawnOn(target, screen, withRoom), isNull);
      expect(drawnOn(reduced, screen, half), isNull, reason: 'nor in Blend');
      await screen.compose(frameOf(celOf(const [5, 5, 5])), changed: Rect.zero);
      expect(drawnOn(target, screen, withRoom), isNull, reason: 'no pixel');
      expect(drawnOn(reduced, screen, half), isNull, reason: 'no pixel');
      expect(target.fingerprint(), whole(screen, withRoom));

      // Beside a lay that made a tile again, it adds nothing to draw.
      await screen.compose(
        frameOf(celOf(const [5, 5, 9])),
        changed: inTheSecond,
      );
      await screen.compose(frameOf(celOf(const [5, 5, 9])), changed: Rect.zero);
      expect(drawnOn(target, screen, withRoom), (128, 128));
      expect(target.fingerprint(), whole(screen, withRoom));
    });

    // A lay told nothing of where is one over all the frame; and a frame
    // of another world — the tile past the page wiped — is laid on a
    // canvas of its own, all of it: its second tile too, which the lay is
    // told nothing of.
    test('a frame laid everywhere, or one of another world, is drawn '
        'whole', () async {
      final screen = EngineStackScreen(engine.composite, engine.letters);
      addTearDown(screen.free);
      final target = shownSurfaceOf(300, 140);
      addTearDown(target.free);
      await screen.compose(frameOf(celOf(const [5, 5, 5])));
      expect(drawnOn(target, screen, withRoom), roomy);

      await screen.compose(frameOf(celOf(const [5, 5, 9])));
      expect(drawnOn(target, screen, withRoom), roomy, reason: 'everywhere');
      expect(target.fingerprint(), whole(screen, withRoom));

      await screen.compose(
        frameOf(celOf(const [5, 5, 3], over: const [0, 1])),
        changed: inTheFirst,
      );
      expect(drawnOn(target, screen, withRoom), roomy, reason: 'a world');
      expect(target.fingerprint(), whole(screen, withRoom));
    });

    // Flutter shows one of a screen's two textures while its next frame
    // is drawn on the other (`_AlternatedTextures`): each holds the frame
    // before the last.
    test('each of two targets drawn on in turn is drawn where the frame '
        'was made again since its own last', () async {
      final screen = EngineStackScreen(engine.composite, engine.letters);
      addTearDown(screen.free);
      final first = shownSurfaceOf(300, 140);
      addTearDown(first.free);
      final second = shownSurfaceOf(300, 140);
      addTearDown(second.free);
      await screen.compose(frameOf(celOf(const [5, 5, 5])));
      expect(drawnOn(first, screen, withRoom), roomy);
      expect(drawnOn(second, screen, withRoom), roomy);

      await screen.compose(
        frameOf(celOf(const [5, 7, 5])),
        changed: inTheFirst,
      );
      expect(drawnOn(first, screen, withRoom), (128, 128));
      await screen.compose(
        frameOf(celOf(const [5, 7, 9])),
        changed: inTheSecond,
      );

      expect(
        drawnOn(second, screen, withRoom),
        (256, 128),
        reason: 'both lays are since its last',
      );
      expect(second.fingerprint(), whole(screen, withRoom));
      expect(
        drawnOn(first, screen, withRoom),
        (128, 128),
        reason: 'the second lay alone is since its last',
      );
      expect(first.fingerprint(), whole(screen, withRoom));
    });

    /// A lay of the second tile of [screen], then [then] of the first.
    Future<void> laysOf(
      EngineStackScreen screen,
      List<int> seeds, {
      required int then,
    }) async {
      final frame = frameOf(celOf(seeds));
      await screen.compose(frame, changed: inTheSecond);
      for (var lay = 0; lay < then; lay++) {
        await screen.compose(frame, changed: inTheFirst);
      }
    }

    // The lays are kept apart [screenLaysKeptApart] deep (`_Lays`): a
    // target as many behind is still drawn where they lay, one more behind
    // whole — the oldest of them, the second tile's, is told of no more.
    test('a target behind by more lays than are kept apart is drawn '
        'whole', () async {
      final screen = EngineStackScreen(engine.composite, engine.letters);
      addTearDown(screen.free);
      final target = shownSurfaceOf(300, 140);
      addTearDown(target.free);
      await screen.compose(frameOf(celOf(const [5, 5, 5])));
      expect(drawnOn(target, screen, withRoom), roomy);

      await laysOf(screen, const [5, 7, 9], then: screenLaysKeptApart - 1);
      expect(
        drawnOn(target, screen, withRoom),
        (256, 128),
        reason: 'as many as are kept apart',
      );
      expect(target.fingerprint(), whole(screen, withRoom));

      await laysOf(screen, const [5, 3, 1], then: screenLaysKeptApart);
      expect(drawnOn(target, screen, withRoom), roomy, reason: 'one more');
      expect(target.fingerprint(), whole(screen, withRoom));
    });

    // 🔬Two frames of the Galaxy Tab's slowest behind — 54 strokes' steps
    // laid in one frame (build 1099, 2026-11-23, `screenLaysKeptApart`):
    // its window, one texture, falls behind by one such frame, two in turn
    // by two —, a target is drawn where they lay: whole, it was 43 ms of
    // that tablet's GPU at every slow frame of a stroke.
    test('a target two frames of the Galaxy Tab\'s slowest behind is drawn '
        'where they lay', () async {
      const behind = 2 * 54;
      final screen = EngineStackScreen(engine.composite, engine.letters);
      addTearDown(screen.free);
      final target = shownSurfaceOf(300, 140);
      addTearDown(target.free);
      await screen.compose(frameOf(celOf(const [5, 5, 5])));
      expect(drawnOn(target, screen, withRoom), roomy);

      await laysOf(screen, const [5, 7, 9], then: behind - 1);
      expect(drawnOn(target, screen, withRoom), (256, 128));
      expect(target.fingerprint(), whole(screen, withRoom));
    });

    // A texel reads another pixel through another camera — and, of a
    // target shown more of, texels nothing was drawn on.
    test('through another camera, or over more of the target, it is '
        'drawn whole', () async {
      final screen = EngineStackScreen(engine.composite, engine.letters);
      addTearDown(screen.free);
      final target = shownSurfaceOf(300, 140);
      addTearDown(target.free);
      final Camera less = (
        name: 'at rest, over less of the target',
        viewport: withRoom.viewport,
        devicePixelRatio: 1,
        size: (200, 100),
        drawn: null,
      );
      // ↩️A pixel's pan till 2026-11-23: one of whole texels is moved now
      // (the tests after this one).
      final Camera zoomed = (
        name: 'zoomed a little',
        viewport: CanvasViewport(zoom: 1.25),
        devicePixelRatio: 1,
        size: roomy,
        drawn: null,
      );
      await screen.compose(frameOf(celOf(const [5, 5, 5])));
      expect(drawnOn(target, screen, less), less.size);
      await screen.compose(
        frameOf(celOf(const [5, 7, 5])),
        changed: inTheFirst,
      );

      for (final camera in [withRoom, zoomed, withRoom]) {
        expect(drawnOn(target, screen, camera), roomy, reason: camera.name);
        expect(
          target.fingerprint(),
          whole(screen, camera),
          reason: camera.name,
        );
      }
    });

    // 🚨A PAN BY WHOLE TEXELS MOVES WHAT THE TARGET HOLDS
    // ([GpuComposite.move]) and draws what it uncovers, with what was made
    // again since: the frame then is the one drawn whole through the
    // camera panned, byte for byte — under 100% in Blend, a texel a tent
    // over what it spans; over it in Nearest; at a device's ratio of one
    // and a half; and turned a quarter, where whole pixels of pan are
    // whole texels still. No lay is waited for before its show.
    test('panned by whole texels, what it holds is moved and the frame is '
        'the one drawn whole — drawn where the pan uncovered alone', () async {
      final (columns, rows) = roomy;
      // Each a pan of the view on from the last, in device pixels.
      const pans = [(7, 0), (0, -5), (13, 9), (-20, -3), (-1, 11)];
      for (final (name, zoom, ratio, turned, from) in const [
        ('at rest', 1.0, 1.0, 0.0, (30, 12)),
        ('shrunk to a half', 0.5, 1.0, 0.0, (30, 12)),
        ('magnified twice', 2.0, 1.0, 0.0, (30, 12)),
        ('at one and a half device pixels a pixel', 0.5, 1.5, 0.0, (30, 12)),
        ('turned a quarter', 1.0, 1.0, 90.0, (158, 12)),
      ]) {
        final screen = EngineStackScreen(engine.composite, engine.letters);
        final target = shownSurfaceOf(columns, rows);
        try {
          var (x, y) = from;
          Camera panned() => (
            name: '$name, panned to ($x, $y)',
            viewport: CanvasViewport(
              zoom: zoom,
              panX: x / ratio,
              panY: y / ratio,
              rotationDegrees: turned,
            ),
            devicePixelRatio: ratio,
            size: roomy,
            drawn: null,
          );
          await screen.compose(frameOf(celOf(const [5, 7, 5])));
          expect(
            drawnOn(target, screen, panned()),
            roomy,
            reason: '$name: all of it, the first time',
          );
          for (final (dx, dy) in pans) {
            (x, y) = (x + dx, y + dy);
            final camera = panned();
            final asked = askedOn(target, screen, camera);
            expect(asked?.moved, (dx, dy), reason: camera.name);
            expect(
              asked?.texels,
              dx.abs() * rows + (columns - dx.abs()) * dy.abs(),
              reason: '${camera.name}: what it uncovered alone',
            );
            expect(
              target.fingerprint(),
              whole(screen, camera),
              reason: camera.name,
            );
          }
          // A lay between two pans: drawn where it made tiles again too.
          final laid = screen.compose(
            frameOf(celOf(const [5, 9, 5])),
            changed: inTheFirst,
          );
          (x, y) = (x + 6, y - 2);
          final camera = panned();
          final asked = askedOn(target, screen, camera);
          await laid;
          expect(asked?.moved, (6, -2), reason: camera.name);
          expect(
            asked?.texels,
            greaterThan(6 * rows + (columns - 6) * 2),
            reason: '${camera.name}: and the tile made again',
          );
          expect(
            target.fingerprint(),
            whole(screen, camera),
            reason: '${camera.name}: a lay between',
          );
          // Through the very camera again, a lay since: nothing is moved.
          await screen.compose(
            frameOf(celOf(const [5, 7, 5])),
            changed: inTheFirst,
          );
          expect(
            askedOn(target, screen, camera)?.moved,
            isNull,
            reason: '${camera.name}: shown again',
          );
          expect(
            target.fingerprint(),
            whole(screen, camera),
            reason: '${camera.name}: shown again',
          );
        } finally {
          target.free();
          screen.free();
        }
      }
    });

    // 🚨THROUGH ANOTHER CAMERA, WHAT THE VIEW HOLDS ALONE
    // ([EngineStackScreen.show]'s `holding`): its box and the margin a pan
    // spares — the rest by the show after, through this camera or its own
    // panned, as what the target does not hold. The frame then is the one
    // drawn whole, byte for byte, and what the target holds is told
    // ([EngineStackScreen.heldIn]) for a pan the frame drawn last serves
    // (`_RenderFrameScreen`). 🔬A zoom's frame drew all of the Galaxy Tab's
    // 3584 × 2560 texels for a view of 2960 × 1848 with its margin, 6.77M
    // of 9.17M (card the-galaxy-tab-canvas-went-slow-on-build-1095).
    test('through another camera it draws what the view holds alone — the '
        'rest by the show after, as what the target does not hold', () async {
      final (columns, rows) = roomy;
      const holding = (40, 20, 260, 120);
      const heldTexels = 220 * 100;
      Camera through(double zoom, (int, int) pan) => (
        name: 'zoomed to $zoom, panned to $pan',
        viewport: CanvasViewport(
          zoom: zoom,
          panX: pan.$1.toDouble(),
          panY: pan.$2.toDouble(),
        ),
        devicePixelRatio: 1,
        size: roomy,
        drawn: null,
      );
      ScreenAsk? heldOn(
        GpuSurface target,
        EngineStackScreen screen,
        Camera camera,
        (int, int, int, int) holding,
      ) {
        ScreenAsked.debugForget();
        screen.show(
          target,
          camera.size,
          viewport: camera.viewport,
          devicePixelRatio: camera.devicePixelRatio,
          holding: holding,
        );
        return ScreenAsked.last;
      }

      for (final (name, (dx, dy)) in const [
        ('shown again', (0, 0)),
        ('panned by whole texels', (7, -3)),
      ]) {
        final screen = EngineStackScreen(engine.composite, engine.letters);
        final target = shownSurfaceOf(columns, rows);
        try {
          await screen.compose(frameOf(celOf(const [5, 7, 9])));
          expect(EngineStackScreen.heldIn(target.kept), isNull, reason: name);
          for (final camera in [through(1, (30, 12)), through(0.5, (30, 12))]) {
            final asked = heldOn(target, screen, camera, holding);
            expect(
              (asked?.columns, asked?.rows, asked?.texels, asked?.moved),
              (220, 100, heldTexels, null),
              reason: '$name, ${camera.name}: what the view holds alone',
            );
            expect(
              EngineStackScreen.heldIn(target.kept),
              holding,
              reason: '$name, ${camera.name}',
            );
          }

          final after = through(0.5, (30 + dx, 12 + dy));
          final asked = heldOn(target, screen, after, holding);
          expect(
            (asked?.texels, asked?.moved),
            (columns * rows - heldTexels, dx == 0 && dy == 0 ? null : (dx, dy)),
            reason: '$name: the rest alone',
          );
          expect(
            EngineStackScreen.heldIn(target.kept),
            (0, 0, columns, rows),
            reason: '$name: all of it held',
          );
          expect(
            target.fingerprint(),
            whole(screen, after),
            reason: '$name: the frame drawn whole',
          );
          expect(
            heldOn(target, screen, after, holding),
            isNull,
            reason: '$name: nothing more to draw',
          );
        } finally {
          target.free();
          screen.free();
        }
      }

      // What reaches past the target: what lies within it.
      final screen = EngineStackScreen(engine.composite, engine.letters);
      addTearDown(screen.free);
      final target = shownSurfaceOf(columns, rows);
      addTearDown(target.free);
      await screen.compose(frameOf(celOf(const [5, 7, 9])));
      expect(
        heldOn(target, screen, through(1, (30, 12)), (-30, 20, 260, 400))
            ?.texels,
        260 * 120,
      );
      expect(EngineStackScreen.heldIn(target.kept), (0, 20, 260, rows));
    });

    // What no whole texels move onto is drawn whole: a pan by a part of a
    // texel — a view turned, whose pan nothing snaps
    // (`renderSnappedViewport`) —, and one by as many texels as the target
    // holds or more.
    test('panned by a part of a texel, or past all the target holds, it is '
        'drawn whole', () async {
      final (columns, rows) = roomy;
      final screen = EngineStackScreen(engine.composite, engine.letters);
      addTearDown(screen.free);
      final target = shownSurfaceOf(columns, rows);
      addTearDown(target.free);
      await screen.compose(frameOf(celOf(const [5, 7, 5])));
      Camera at(double x, double y, {double turned = 0}) => (
        name: 'panned to ($x, $y), turned $turned',
        viewport: CanvasViewport(panX: x, panY: y, rotationDegrees: turned),
        devicePixelRatio: 1,
        size: roomy,
        drawn: null,
      );

      for (final camera in [
        at(158, 12, turned: 30),
        at(160.5, 12, turned: 30),
        at(30, 12),
        at(30.0 + columns, 12),
        at(30.0 + columns, 12.0 - rows),
        at(-970, 12),
      ]) {
        final asked = askedOn(target, screen, camera);
        expect(
          (asked?.columns, asked?.rows, asked?.moved),
          (columns, rows, null),
          reason: camera.name,
        );
        expect(
          target.fingerprint(),
          whole(screen, camera),
          reason: camera.name,
        );
      }
    });

    // A view's corner on the texel `corner` of its target is the view
    // panned by as many device pixels — a target with room stands its
    // view inside (`_RenderFrameScreen`): one camera, byte for byte.
    test('a view whose corner stands on a texel of its target shows what it '
        'does panned by as many', () async {
      final screen = EngineStackScreen(engine.composite, engine.letters);
      addTearDown(screen.free);
      await screen.compose(frameOf(celOf(const [5, 7, 5])));
      for (final (ratio, corner) in const [(1.0, (64, 16)), (1.5, (30, 9))]) {
        final (cornerX, cornerY) = corner;
        final target = shownSurfaceOf(roomy.$1, roomy.$2);
        addTearDown(target.free);
        screen.show(
          target,
          roomy,
          viewport: CanvasViewport(zoom: 0.5, panX: 10, panY: 4),
          devicePixelRatio: ratio,
          corner: corner,
        );
        expect(
          target.fingerprint(),
          whole(screen, (
            name: 'panned by the corner',
            viewport: CanvasViewport(
              zoom: 0.5,
              panX: 10 + cornerX / ratio,
              panY: 4 + cornerY / ratio,
            ),
            devicePixelRatio: ratio,
            size: roomy,
            drawn: null,
          )),
          reason: 'the corner on $corner at $ratio device pixels a pixel',
        );
      }
    });

    test('a target another screen drew on last is drawn whole', () async {
      final screen = EngineStackScreen(engine.composite, engine.letters);
      addTearDown(screen.free);
      final another = EngineStackScreen(engine.composite, engine.letters);
      addTearDown(another.free);
      final target = shownSurfaceOf(300, 140);
      addTearDown(target.free);
      await screen.compose(frameOf(celOf(const [5, 5, 5])));
      await another.compose(frameOf(celOf(const [9, 9, 9])));
      expect(drawnOn(target, screen, withRoom), roomy);

      for (final shown in [another, screen]) {
        expect(drawnOn(target, shown, withRoom), roomy);
        expect(target.fingerprint(), whole(shown, withRoom));
      }
    });

    // Every draw on a target forgets what it was said to hold
    // ([GpuSurface.kept]): a fill, a composite shown, a screen of the
    // engine's shown by another hand, the grid's lay.
    test('a target another draw was on since is drawn whole', () async {
      final screen = EngineStackScreen(engine.composite, engine.letters);
      addTearDown(screen.free);
      final target = shownSurfaceOf(300, 140);
      addTearDown(target.free);
      final grid = GpuGridLay(engine.composite.engine);
      addTearDown(grid.free);
      await screen.compose(frameOf(celOf(const [5, 5, 5])));
      const all = (0, 0, 300, 140);
      const page = (0, 0, 256, 128);

      /// [draw] handed the paper alone, planned on the app's pool.
      void withThePaper(void Function(GpuPool pool, GpuPlan plan) draw) {
        final ledger = EngineTileLedger.instance;
        ledger.held((hold) {
          final plan = GpuPlan(engine.composite.engine);
          try {
            planCompositeTree(
              plan,
              <CompositeNode<EngineRow>>[
                CompositeLeaf(
                  EngineSolid(
                    argb: paper.paintedArgb,
                    rect: DirtyRegion.fromLTBR(
                      left: 0,
                      top: 0,
                      rightExclusive: canvas.width,
                      bottomExclusive: canvas.height,
                    ),
                  ),
                ),
              ],
              hold: hold,
              paper: canvas.canvasRect,
              letters: engine.letters,
            );
            draw(ledger.pool, plan);
          } finally {
            plan.free();
          }
        });
      }

      final draws = <String, void Function()>{
        'a fill': () => target.fill(7),
        'a composite shown': () => withThePaper(
          (pool, plan) => engine.composite.show(pool, plan, target, all),
        ),
        'a screen shown by another hand': () => withThePaper((pool, plan) {
          final raw = GpuScreen(engine.composite, page);
          try {
            unawaited(raw.compose(pool, plan, page));
            raw.show(
              target,
              inverse: const [1, 0, 0, 1, 0, 0],
              sampling: GpuSampling.nearest,
              rect: all,
            );
          } finally {
            raw.free();
          }
        }),
        "the grid's lay": () => grid.lay(target, all, const []),
      };
      expect(drawnOn(target, screen, withRoom), roomy);
      for (final MapEntry(key: name, value: draw) in draws.entries) {
        expect(drawnOn(target, screen, withRoom), isNull, reason: name);

        draw();

        expect(drawnOn(target, screen, withRoom), roomy, reason: name);
        expect(target.fingerprint(), whole(screen, withRoom), reason: name);
      }
    });

    // What the GPU did of a frame it did not finish is not known
    // (`ScreenTexture.present`): nothing was made again since, and still
    // the next frame is drawn whole. Nobody is told of the frames here
    // ([ScreenTexture.putUp]) — the one given up is given up all the same,
    // and the next is drawn.
    test('a target whose frame the GPU did not finish is drawn '
        'whole', () async {
      final reportTo = FlutterError.onError;
      final reported = <Object>[];
      FlutterError.onError = (details) => reported.add(details.exception);
      addTearDown(() => FlutterError.onError = reportTo);
      final screen = EngineStackScreen(engine.composite, engine.letters);
      addTearDown(screen.free);
      final target = shownSurfaceOf(300, 140);
      addTearDown(target.free);
      final gates = <Completer<GpuWaited?>>[];
      final texture = ScreenTexture.debugOnSurface(
        target,
        done: () {
          final gate = Completer<GpuWaited?>();
          gates.add(gate);
          return gate.future;
        },
      );
      addTearDown(texture.free);
      await screen.compose(frameOf(celOf(const [5, 5, 5])));
      final drawn = <(int, int)?>[];
      final failure = GpuRefused('the GPU did not finish within 30s');

      /// A frame of the texture's, the GPU ending it as [end] says.
      Future<void> aFrame(void Function(Completer<GpuWaited?> gate) end) async {
        texture.present(
          (next) => drawn.add(drawnOn(next, screen, withRoom)),
        );
        end(gates.last);
        await pumpEventQueue();
      }

      await aFrame((gate) => gate.complete());
      await aFrame((gate) => gate.complete());
      await aFrame((gate) => gate.completeError(failure));
      await aFrame((gate) => gate.complete());

      expect(drawn, [roomy, null, null, roomy]);
      expect(reported, [failure]);
    });
  });
}
