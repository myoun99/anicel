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
import 'package:anicel/src/services/guide_geometry.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/composite_tree_paint.dart'
    show BelowThePen;
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart'
    show HeldSubtreeRasters;
import 'package:anicel/src/ui/playback/engine_frame_picture_store.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../helpers/a_shown_surface.dart';
import '../helpers/engine_screen_pins.dart';

/// 🚨★WHAT A CHAIN PUT IS HELD ON THE ENGINE (folder holding, 관제 11-08
/// 22:14): a blurred folder laid again as what it shows — its rows at the
/// revisions they stand at — lays what its chain put before and runs none
/// of it, as a frame whose folder holds other pixels under the same
/// revision shows; so does a blurred row, an adjustment crossfaded at part
/// mix, and a row reading a blur map, whose picture is the map's too. One
/// that shows another picture, or a row drawn live, runs it, as does one
/// on another paper; a row a posed lens reads as its map lays what its
/// chain put where it shows by itself. What is held fits the room
/// it is given, the hold used longest ago let go first, and the engine
/// counts what it keeps; a store's screens hold in the store's.
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
  ResolvedLayerEffect fx(
    EffectKind kind,
    Map<String, double> lanes, {
    Map<String, LayerId?> layers = const {},
  }) => ResolvedLayerEffect(
    kind: kind,
    values: [
      for (final spec in kind.parameters) lanes[spec.id] ?? spec.defaultValue,
    ],
    layers: layers,
  );
  final blur = fx(EffectKind.blur, {'blurriness': 24});
  final edged = fx(EffectKind.blur, {'blurriness': 24, 'repeatEdgePixels': 1});

  /// A lens blur reading its map off the row of [map].
  ResolvedLayerEffect lensOn(BrushFrameKey map) => fx(
    EffectKind.cameraLensBlur,
    {'blurRadius': 6, 'blurFocalDistance': 128},
    layers: {'blurMapLayer': map.layerId},
  );
  FramePage pageOf(CanvasSize size) => (
    canvasSize: size,
    pasteboardReach: PasteboardReach.whole,
    paintPaper: true,
    paperBackground: const ProjectBackground.color(0xFF30A060),
  );
  final engine = EngineScreenPins('the engine holds what a chain put');

  /// A cel of [seed]'s pixels over two tiles of a page of [size], alphas of
  /// every kind.
  BitmapSurface cel(int seed, CanvasSize size) {
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
      canvasSize: size,
      tileSize: side,
      tiles: {
        for (final column in [0, 1]) TileCoord(x: column, y: 0): tile(column),
      },
    );
  }

  CompositeLeaf<CanvasStackRow> rowOf(
    BrushFrameKey key, {
    double opacity = 1,
    GuideTransform? placement,
    List<ResolvedLayerEffect> effects = const [],
  }) => CompositeLeaf(
    CanvasLayerImageRequest(
      frameKey: key,
      opacity: opacity,
      placement: placement,
      effects: effects,
    ),
  );

  /// A blurred folder of [folded] under a row of the cel outside it at
  /// half its strength.
  List<CompositeNode<CanvasStackRow>> nodes(CanvasStackRow folded) => [
    CompositeGroup(
      children: [CompositeLeaf(folded)],
      opacity: 1,
      blendMode: LayerBlendMode.normal,
      effects: [blur],
    ),
    rowOf(outside, opacity: 0.5),
  ];

  /// Each node whose chain is held, over a row of the cel outside it where
  /// that cel is not the one it reads by — what it shows the cel inside.
  final trees = <String, List<CompositeNode<CanvasStackRow>>>{
    'a blurred folder': nodes(
      CanvasLayerImageRequest(frameKey: inside, opacity: 1),
    ),
    'a blurred row': [
      rowOf(inside, effects: [blur]),
      rowOf(outside, opacity: 0.5),
    ],
    'an adjustment blurring at part mix': [
      CompositeAdjustment(
        children: [rowOf(inside)],
        effects: [blur],
        mix: 0.4,
      ),
      rowOf(outside, opacity: 0.5),
    ],
    // What it shows is the map's too: the row's own signature is not.
    'a row through a lens reading its map off the cel': [
      CompositeReadsRows(
        node: rowOf(outside, effects: [lensOn(inside)]),
        rows: {
          inside.layerId: [rowOf(inside)],
        },
      ),
    ],
  };

  /// The frame of [tree] on a page of [size] — of [trees]' folder where
  /// none —, the cel inside of [seed]'s pixels at [revision] — whatever
  /// pixels the revision stands for: the frame's key says what it shows, as
  /// a frame's picture is signed —, and every other cel's its own.
  StackedFrame frameOf(
    int seed, {
    int revision = 1,
    List<CompositeNode<CanvasStackRow>>? tree,
    CanvasSize size = canvas,
  }) => stackedFrameOf(
    tree ?? trees['a blurred folder']!,
    page: pageOf(size),
    surfaceOf: (key) => cel(key == inside ? seed : 3, size),
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
    page: pageOf(canvas),
    surfaceOf: (_) => cel(3, canvas),
    live: (
      rows: (
        activeSurfacePainter: BitmapSurfacePainter(surface: cel(seed, canvas)),
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

  /// What [shown] shows at rest on a page of [size], one texel a canvas
  /// pixel.
  int shownBy(void Function(GpuSurface target) shown, CanvasSize size) {
    final target = shownSurfaceOf(size.width, size.height);
    addTearDown(target.free);
    shown(target);
    return target.fingerprint();
  }

  /// What a screen holding its chains' puts in [holds] shows of [frame], on
  /// a page of [size].
  int laidWith(
    EngineChainHolds holds,
    StackedFrame frame, {
    CanvasSize size = canvas,
  }) {
    final screen = EngineStackScreen(engine.composite, engine.letters);
    addTearDown(screen.free);
    screen.compose(frame, holds: holds);
    return shownBy(
      (target) => screen.show(
        target,
        (size.width, size.height),
        viewport: CanvasViewport(),
        devicePixelRatio: 1,
      ),
      size,
    );
  }

  /// What a screen that holds nothing shows of [frame], on a page of
  /// [size].
  int laid(StackedFrame frame, {CanvasSize size = canvas}) =>
      engine.shown(frame, size: (size.width, size.height));

  for (final MapEntry(key: name, value: tree) in trees.entries) {
    test('🚨$name laid again as what it shows lays what its chain put', () {
      final holds = holdsIn(1 << 30);
      final first = laidWith(holds, frameOf(5, tree: tree));
      expect(first, laid(frameOf(5, tree: tree)), reason: 'a miss runs it');

      expect(
        laidWith(holds, frameOf(9, tree: tree)),
        first,
        reason: 'what it put laid',
      );
      expect(laid(frameOf(9, tree: tree)), isNot(first), reason: 'it differs');
    });

    test('$name that shows another picture runs its chain again', () {
      final holds = holdsIn(1 << 30);
      laidWith(holds, frameOf(5, tree: tree));

      expect(
        laidWith(holds, frameOf(9, revision: 2, tree: tree)),
        laid(frameOf(9, tree: tree)),
      );
    });
  }

  test('🚨a folder a row is drawn live in runs its chain each time', () {
    final holds = holdsIn(1 << 30);
    expect(laidWith(holds, liveFrameOf(5)), laid(liveFrameOf(5)));

    expect(laidWith(holds, liveFrameOf(9)), laid(liveFrameOf(9)));
    expect(holds.heldBytes, 0);
  });

  test('🚨a folder on another paper runs its chain there', () {
    const narrow = CanvasSize(width: 192, height: 128);
    final tree = [
      CompositeGroup<CanvasStackRow>(
        children: [rowOf(inside)],
        opacity: 1,
        blendMode: LayerBlendMode.normal,
        effects: [edged],
      ),
    ];
    final holds = holdsIn(1 << 30);
    laidWith(holds, frameOf(5, tree: tree));

    expect(
      laidWith(holds, frameOf(5, tree: tree, size: narrow), size: narrow),
      laid(frameOf(5, tree: tree, size: narrow), size: narrow),
    );
  });

  test('🚨a row a posed lens reads as its map lays what its chain put', () {
    // Its chain puts its own pixels, wherever it is laid: one hold, one run.
    final read = CompositeReadsRows<CanvasStackRow>(
      node: rowOf(
        outside,
        placement: const GuideTransform(1, 0, 0, 1, 64, 0),
        effects: [lensOn(inside)],
      ),
      rows: {
        inside.layerId: [
          rowOf(inside, effects: [edged]),
        ],
      },
    );
    final tree = [
      rowOf(inside, effects: [edged]),
      read,
    ];
    final weighed = holdsIn(1 << 30);
    laidWith(weighed, frameOf(5, tree: [read]));
    final holds = holdsIn(1 << 30);

    expect(
      laidWith(holds, frameOf(5, tree: tree)),
      laid(frameOf(5, tree: tree)),
    );
    expect(holds.heldBytes, weighed.heldBytes, reason: 'its map held as it');
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
    final before = GpuHeldChains.liveBytes;
    final holds = holdsIn(weighed.heldBytes);
    laidWith(holds, frameOf(5));
    laidWith(holds, frameOf(7, revision: 2));

    expect(holds.heldBytes, weighed.heldBytes);
    expect(
      GpuHeldChains.liveBytes - before,
      holds.heldBytes,
      reason: 'the engine let go of it too',
    );
    expect(
      laidWith(holds, frameOf(11, revision: 2)),
      laid(frameOf(7)),
      reason: 'the newest kept',
    );
    expect(laidWith(holds, frameOf(9)), laid(frameOf(9)), reason: 'let go');
  });

  test('a hold laid again is the one used last', () {
    final weighed = holdsIn(1 << 30);
    laidWith(weighed, frameOf(5));
    final holds = holdsIn(2 * weighed.heldBytes);
    final first = laidWith(holds, frameOf(5));
    laidWith(holds, frameOf(7, revision: 2));
    laidWith(holds, frameOf(9));
    laidWith(holds, frameOf(11, revision: 3));

    expect(laidWith(holds, frameOf(13)), first, reason: 'used last, kept');
    expect(
      laidWith(holds, frameOf(15, revision: 2)),
      laid(frameOf(15)),
      reason: 'used longest ago, let go',
    );
  });

  test('a store\'s screens hold their chains\' puts in the store\'s', () async {
    final store = EngineFramePictureStore<String>(
      tools: () async => (
        composite: engine.composite,
        letters: engine.letters,
      ),
    );
    final holds = holdsIn(1 << 30);
    addTearDown(store.dispose);
    int shownOf(EngineFramePicture picture) => shownBy(
      (target) => picture.show(
        target,
        (canvas.width, canvas.height),
        viewport: CanvasViewport(),
        devicePixelRatio: 1,
      ),
      canvas,
    );

    final first = shownOf((await store.lay('a', frameOf(5), holds: holds))!);
    final next = shownOf((await store.lay('b', frameOf(9), holds: holds))!);

    expect(first, laid(frameOf(5)));
    expect(next, first);
  });
}
