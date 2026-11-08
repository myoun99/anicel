import 'dart:typed_data';

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
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/engine_chain_holds.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/composite_tree_paint.dart'
    show BelowThePen;
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart'
    show HeldSubtreeRasters;
import 'package:anicel/src/ui/playback/engine_frame_picture_store.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../helpers/engine_screen_pins.dart';

/// 🚨★WHAT A CHAIN PUT IS HELD ON THE ENGINE (folder holding, 관제 11-08
/// 22:14): a blurred folder laid again as what it shows — its rows at the
/// revisions they stand at — lays what its chain put before and runs none
/// of it, as a frame whose folder holds other pixels under the same
/// revision shows; one that shows another picture, or a row drawn live,
/// runs it. What is held fits the room it is given, the oldest let go
/// first, and the engine counts what it keeps; a store's screens hold
/// in the store's.
void main() {
  // The letters read their faces from the bundle.
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvas = CanvasSize(width: 256, height: 128);
  const side = 128;
  BrushFrameKey celOf(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );
  final inside = celOf('in');
  final outside = celOf('out');
  final blur = ResolvedLayerEffect(
    kind: EffectKind.blur,
    values: [
      for (final spec in EffectKind.blur.parameters)
        const {'blurriness': 24.0}[spec.id] ?? spec.defaultValue,
    ],
  );
  const page = (
    canvasSize: canvas,
    pasteboardReach: PasteboardReach.whole,
    paintPaper: true,
    paperBackground: ProjectBackground.color(0xFF30A060),
  );
  final engine = EngineScreenPins('the engine holds what a chain put');

  /// A cel of [seed]'s pixels over the page's two tiles, alphas of every
  /// kind.
  BitmapSurface cel(int seed) {
    BitmapTile tile(int column) {
      final pixels = Uint8List(side * side * 4);
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final worldX = x + column * side;
          final n = worldX * 7 + y * 13 + seed * 101;
          final alpha = switch ((worldX ~/ 16 + y ~/ 32 + seed) % 3) {
            0 => 0,
            1 => 255,
            _ => 96 + (n & 127),
          };
          pixels.setAll(
            (y * side + x) * 4,
            alpha == 0
                ? const [0, 0, 0, 0]
                : [(n * 37) & 255, (n * 23 + 91) & 255, (n * 11) & 255, alpha],
          );
        }
      }
      return BitmapTile(size: side, pixels: pixels);
    }

    return BitmapSurface(
      canvasSize: canvas,
      tileSize: side,
      tiles: {
        for (final column in [0, 1]) TileCoord(x: column, y: 0): tile(column),
      },
    );
  }

  /// A blurred folder of [folded] under a row of the cel outside it at
  /// half its strength.
  List<CompositeNode<CanvasStackRow>> nodes(CanvasStackRow folded) => [
    CompositeGroup(
      children: [CompositeLeaf(folded)],
      opacity: 1,
      blendMode: LayerBlendMode.normal,
      effects: [blur],
    ),
    CompositeLeaf(CanvasLayerImageRequest(frameKey: outside, opacity: 0.5)),
  ];

  /// The frame of the cel inside the folder at [revision], [seed]'s pixels
  /// — whatever pixels the revision stands for: the frame's key says what
  /// it shows, as a frame's picture is signed —, and the cel outside it.
  StackedFrame frameOf(int seed, {int revision = 1}) => stackedFrameOf(
    nodes(CanvasLayerImageRequest(frameKey: inside, opacity: 1)),
    page: page,
    surfaceOf: (key) => key == inside ? cel(seed) : cel(3),
    held: (
      pictures: (
        rasters: HeldSubtreeRasters(bytes: () => 0),
        keeps: NodesKept.none,
        below: BelowThePen.inCells,
      ),
      revisionOf: (key) => key == inside ? revision : 1,
    ),
  );

  /// The frame of the folder holding the row a pen draws on, drawn live
  /// from [seed]'s pixels: no key says what it shows.
  StackedFrame liveFrameOf(int seed) => stackedFrameOf(
    nodes(const CanvasActiveLayerRow(opacity: 1)),
    page: page,
    surfaceOf: (_) => cel(3),
    live: (
      rows: (
        activeSurfacePainter: BitmapSurfacePainter(surface: cel(seed)),
        floatOverlay: null,
        liftedRows: const {},
      ),
      painters: LiftedRowPainters(),
    ),
    held: (
      pictures: (
        rasters: HeldSubtreeRasters(bytes: () => 0),
        keeps: NodesKept.none,
        below: BelowThePen.inCells,
      ),
      revisionOf: (_) => 1,
    ),
  );

  /// Holds fitting [room], let go of at the test's end.
  EngineChainHolds holdsIn(int room) {
    final holds = EngineChainHolds(room: () => room);
    addTearDown(holds.free);
    return holds;
  }

  /// What [shown] shows at rest, one texel a canvas pixel.
  int shownBy(void Function(GpuSurface target) shown) {
    final target = platformSurfaceOf(canvas.width, canvas.height);
    addTearDown(target.free);
    shown(target);
    return target.fingerprint();
  }

  /// What a screen holding its chains' puts in [holds] shows of [frame].
  int laidWith(EngineChainHolds holds, StackedFrame frame) {
    final screen = EngineStackScreen(
      engine.composite,
      engine.letters,
      holds: holds,
    );
    addTearDown(screen.free);
    screen.compose(frame);
    return shownBy(
      (target) => screen.show(
        target,
        (canvas.width, canvas.height),
        viewport: CanvasViewport(),
        devicePixelRatio: 1,
      ),
    );
  }

  /// What a screen that holds nothing shows of [frame].
  int laid(StackedFrame frame) =>
      engine.shown(frame, size: (canvas.width, canvas.height));

  test('🚨a folder laid again as what it shows lays what its chain put', () {
    final holds = holdsIn(1 << 30);
    final first = laidWith(holds, frameOf(5));
    expect(first, laid(frameOf(5)), reason: 'a miss runs the chain');

    expect(laidWith(holds, frameOf(9)), first, reason: 'what it put laid');
    expect(laid(frameOf(9)), isNot(first), reason: 'its pixels differ');
  });

  test('a folder that shows another picture runs its chain again', () {
    final holds = holdsIn(1 << 30);
    laidWith(holds, frameOf(5));

    expect(laidWith(holds, frameOf(9, revision: 2)), laid(frameOf(9)));
  });

  test('🚨a folder a row is drawn live in runs its chain each time', () {
    final holds = holdsIn(1 << 30);
    expect(laidWith(holds, liveFrameOf(5)), laid(liveFrameOf(5)));

    expect(laidWith(holds, liveFrameOf(9)), laid(liveFrameOf(9)));
    expect(holds.heldBytes, 0);
  });

  test('🚨the engine counts what the holds keep, and gives it back', () {
    final before = GpuHeldChains.liveBytes;
    final holds = holdsIn(1 << 30);
    laidWith(holds, frameOf(5));

    expect(holds.heldBytes, greaterThan(0));
    expect(GpuHeldChains.liveBytes - before, holds.heldBytes);
    holds.clear();
    expect(GpuHeldChains.liveBytes - before, 0);
  });

  test('what does not fit the room is not held', () {
    final before = GpuHeldChains.liveBytes;
    final holds = holdsIn(0);

    expect(laidWith(holds, frameOf(5)), laid(frameOf(5)));
    expect(holds.heldBytes, 0);
    expect(GpuHeldChains.liveBytes - before, 0);
    expect(laidWith(holds, frameOf(9)), laid(frameOf(9)));
  });

  test('past the room the hold used longest ago is let go of', () {
    final weighed = holdsIn(1 << 30);
    laidWith(weighed, frameOf(5));
    final holds = holdsIn(weighed.heldBytes);
    laidWith(holds, frameOf(5));
    laidWith(holds, frameOf(7, revision: 2));

    expect(holds.heldBytes, weighed.heldBytes);
    expect(
      laidWith(holds, frameOf(11, revision: 2)),
      laid(frameOf(7)),
      reason: 'the newest kept',
    );
    expect(laidWith(holds, frameOf(9)), laid(frameOf(9)), reason: 'let go');
  });

  test('a store\'s screens hold their chains\' puts in the store\'s', () async {
    final store = EngineFramePictureStore<String>(
      composite: engine.composite,
      letters: engine.letters,
      holds: holdsIn(1 << 30),
    );
    addTearDown(store.dispose);
    int shownOf(EngineFramePicture picture) => shownBy(
      (target) => picture.show(
        target,
        (canvas.width, canvas.height),
        viewport: CanvasViewport(),
        devicePixelRatio: 1,
      ),
    );

    final first = shownOf((await store.lay('a', frameOf(5)))!);
    final next = shownOf((await store.lay('b', frameOf(9)))!);

    expect(first, laid(frameOf(5)));
    expect(next, first);
  });
}
