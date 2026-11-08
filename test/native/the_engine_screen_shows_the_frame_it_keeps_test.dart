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
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/composite_tree_plan.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';


/// 🚨THE ENGINE'S SCREEN SHOWS THE FRAME IT KEEPS (screen-on-the-engine c6
/// ④, 관제 11-08 14:19): a frame laid on the engine's screen
/// ([EngineStackScreen]) and shown through the view's camera is, byte for
/// byte, the same frame laid by the translator and run on the engine
/// ([GpuComposite.run]) — at rest, moved and shrunk at twice the pixels,
/// turned a quarter — the pasteboard left of the page among it, and again
/// after a change composed where it lies. ↩️Not against the walk's screen:
/// 「지금화면이랑 맞출필요는없어 … 바뀌고 나서만 동일하면되」(유저 11-08, 관제가
/// 전함).
/// A view a case shows through: where each device pixel's middle lands on
/// the world ([canvasAt]), and the surface's size.
typedef View = ({
  String name,
  CanvasViewport viewport,
  double devicePixelRatio,
  (int, int) size,
  (int, int) Function(int x, int y) canvasAt,
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
  late GpuComposite composite;
  late EngineLetters letters;

  setUpAll(() async {
    composite = GpuComposite(appGpuEngine);
    letters = await EngineLetters.open(composite);
  });
  tearDownAll(() {
    letters.free();
    composite.free();
  });

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
      final plan = GpuPlan();
      addTearDown(plan.free);
      planCompositeTree(
        plan,
        tree,
        hold: hold,
        paper: canvas.canvasRect,
        letters: letters,
      );
      final out = composite.run(ledger.pool, plan, [
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

  /// A surface as the platform makes the ones it shows: RGBA where it can,
  /// else BGRA.
  GpuSurface surfaceOf(int width, int height) {
    try {
      return appGpuEngine.surface(width, height, bgra: false);
    } on StateError {
      return appGpuEngine.surface(width, height, bgra: true);
    }
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
      final target = surfaceOf(width, height);
      addTearDown(target.free);
      screen.show(
        target,
        columns: width,
        rows: height,
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

  test('the screen shows the frame the engine lays, through the view', () {
    final screen = EngineStackScreen(composite, letters);
    addTearDown(screen.free);
    final surface = cel(3);
    screen.compose(frameOf(surface));

    showsThrough(screen, ranOver(surface), views);
  });

  // A change composed where it lies shows, at rest and past the page alike:
  // a mark across the page's left edge, told where it changed; and a frame
  // told nothing of where is laid everywhere.
  test('a change composed where it lies is the frame the engine lays', () {
    final screen = EngineStackScreen(composite, letters);
    addTearDown(screen.free);
    screen.compose(frameOf(cel(5)));
    const marked = (-20, 10, 40, 50);
    final changed = cel(5, marked: marked);
    screen.compose(frameOf(changed), changed: rectOf(marked));

    showsThrough(screen, ranOver(changed), views.take(2));

    final another = cel(7);
    screen.compose(frameOf(another));

    showsThrough(screen, ranOver(another), views.take(2));
  });

  // A change the screen is not told of is kept as it was: the frame is
  // made again where it is told it changed, not everywhere.
  test('a change not told of is not composed', () {
    final screen = EngineStackScreen(composite, letters);
    addTearDown(screen.free);
    final before = cel(5);
    screen.compose(frameOf(before));
    final marked = cel(5, marked: (200, 60, 220, 80));
    screen.compose(frameOf(marked), changed: rectOf((10, 10, 20, 20)));

    showsThrough(screen, ranOver(before), views.take(1));
    expect(
      ranOver(marked)(210, 70),
      isNot(ranOver(before)(210, 70)),
      reason: 'the mark not told of is one the frame shows',
    );
  });

  // A frame of another world — its pasteboard tile wiped — is laid on a
  // screen of that world, whole: nothing of the world kept before shows.
  test('a frame of another world is laid whole', () {
    final screen = EngineStackScreen(composite, letters);
    addTearDown(screen.free);
    screen.compose(frameOf(cel(5)));
    final within = cel(5, over: const [0, 1]);
    screen.compose(frameOf(within), changed: rectOf((10, 10, 20, 20)));

    showsThrough(screen, ranOver(within), views.take(2));
  });
}
