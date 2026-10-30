import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart'
    show PromotedStrokeTile;
import 'package:anicel/src/services/playback/frame_demand.dart'
    show FrameGhosts;
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_gpu.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart'
    show FramePictureKey;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/a_plugin_that_shifts.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// 🗣️I-132-Q34 a (유저 2026-10-30): 「머문다 — … 결과가 올 때까지 그
/// 프레임의 직전 완성 그림에 머문다」 — a canvas standing on a frame that
/// holds a plugin's step past a cel's own pixels never draws it as it
/// stands, where the step would be drawn as if off: what it shows is the
/// frame's picture, made waiting for the plugin, and a stroke's steps go
/// into it one patch at a time — a stroke shown late by the plugin's time.
/// Beside each, the same frame with no plugin, as it always was.
void main() {
  const tileSize = 16;
  // ⚠️Wide enough that a folder drawn whole with a plugin's reach on it
  // is held: none is past a page ([HeldSubtreeRasters]).
  const canvasSize = CanvasSize(width: 128, height: 128);
  const viewSize = Size(48, 40);
  const under = Color(0xFF203040);
  const ink = [0x00, 0x40, 0x00, 0xFF];
  const stroke = [0x40, 0x00, 0x00, 0xFF];
  const other = [0x00, 0x00, 0x40, 0xFF];
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('inked'),
    frameId: FrameId('f'),
  );
  const over = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('over'),
    frameId: FrameId('o'),
  );
  final cut = Cut(
    id: key.cutId,
    name: 'Cut',
    duration: 1,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: key.layerId,
        name: 'Inked',
        frames: [Frame(id: key.frameId, duration: 1, strokes: const [])],
        timeline: {0: TimelineExposure.drawing(key.frameId, length: 1)},
      ),
      Layer(
        id: over.layerId,
        name: 'Over',
        frames: [Frame(id: over.frameId, duration: 1, strokes: const [])],
        timeline: {0: TimelineExposure.drawing(over.frameId, length: 1)},
      ),
    ],
  );
  ResolvedLayerEffect aPlugin(ShiftingFxPlugin runner) => ResolvedLayerEffect(
    kind: EffectKind.plugin,
    plugin: shiftingFxPluginDescription,
    values: const [],
    run: fxPluginRunOf(runner),
  );
  const live = CompositeLeaf<CanvasStackRow>(
    CanvasActiveLayerRow(opacity: 1, frameKey: key),
  );

  /// The row a pen is on, in a folder whose chain is [effects].
  List<CompositeNode<CanvasStackRow>> inAFolder(
    List<ResolvedLayerEffect> effects,
  ) => [
    CompositeGroup<CanvasStackRow>(
      children: const [live],
      opacity: 1,
      blendMode: LayerBlendMode.normal,
      effects: effects,
    ),
  ];

  /// The row a pen is on, under a folder whose chain is [effects] holding
  /// another row, [over].
  List<CompositeNode<CanvasStackRow>> overThePen(
    List<ResolvedLayerEffect> effects,
  ) => [
    live,
    CompositeGroup<CanvasStackRow>(
      children: const [
        CompositeLeaf(CanvasLayerImageRequest(frameKey: over, opacity: 1)),
      ],
      opacity: 1,
      blendMode: LayerBlendMode.normal,
      effects: effects,
    ),
  ];

  group('a frame waits for its plugins', () {
    final runs = aPlugin(ShiftingFxPlugin(by: 1));
    final runsNot = ResolvedLayerEffect(
      kind: EffectKind.plugin,
      plugin: shiftingFxPluginDescription,
      values: const [],
    );
    test('where a folder\'s or an adjustment\'s chain, or a row\'s past its '
        'head, runs one — not where nothing runs it, nor at a cel\'s head', () {
      expect(waitsForItsPlugins(inAFolder([runs])), isTrue);
      expect(
        waitsForItsPlugins([
          CompositeAdjustment<CanvasStackRow>(
            children: const [live],
            effects: [runs],
            mix: 1,
          ),
        ]),
        isTrue,
      );
      final blur = ResolvedLayerEffect(kind: EffectKind.blur, values: [3]);
      for (final row in <CanvasStackRow>[
        CanvasActiveLayerRow(opacity: 1, frameKey: key, effects: [blur, runs]),
        CanvasLayerImageRequest(
          frameKey: key,
          opacity: 1,
          effects: [blur, runs],
        ),
      ]) {
        expect(
          waitsForItsPlugins([CompositeLeaf(row)]),
          isTrue,
          reason: '$row',
        );
      }

      expect(waitsForItsPlugins(inAFolder([runsNot])), isFalse);
      expect(waitsForItsPlugins(inAFolder([blur])), isFalse);
      expect(
        waitsForItsPlugins([
          CompositeLeaf(
            CanvasLayerImageRequest(frameKey: key, opacity: 1, effects: [runs]),
          ),
        ]),
        isFalse,
        reason: 'at a cel\'s head it runs over the cel\'s own pixels, as the '
            'cel is read',
      );
    });
  });

  /// A tile of [colour] wherever [inside] holds, clear elsewhere.
  BitmapTile tileOf(
    TileCoord coord,
    List<int> colour,
    bool Function(Offset at) inside,
  ) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var y = 0; y < tileSize; y += 1) {
      for (var x = 0; x < tileSize; x += 1) {
        final at = Offset(
          coord.x * tileSize + x + 0.5,
          coord.y * tileSize + y + 0.5,
        );
        if (inside(at)) {
          pixels.setRange(
            (y * tileSize + x) * 4,
            (y * tileSize + x) * 4 + 4,
            colour,
          );
        }
      }
    }
    return BitmapTile(size: tileSize, pixels: pixels);
  }

  /// A canvas standing on [nodes]' frame — its one row inked at (4..8,
  /// 4..8) — over a store on [gpu]; what [screen] shows, the overlay its
  /// pen's steps are shown by, and a hand of the pen's row anew — on another
  /// frame's nodes where it is handed them.
  Future<
    ({
      FramePictureStore<FramePictureKey> store,
      FramePictureKey picture,
      ActiveStrokeOverlayModel overlay,
      Future<void> Function([List<CompositeNode<CanvasStackRow>>? nodes])
      handAnew,
    })
  >
  standOn(
    WidgetTester tester,
    GlobalKey screen,
    List<CompositeNode<CanvasStackRow>> nodes,
    RendersHeld gpu,
  ) async {
    final cels = BrushFrameStore();
    keepInAFile(cels, {
      key: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {
          TileCoord(x: 0, y: 0): tileOf(
            TileCoord(x: 0, y: 0),
            ink,
            (at) => const Rect.fromLTRB(4, 4, 8, 8).contains(at),
          ),
        },
      ),
      over: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {
          TileCoord(x: 0, y: 1): tileOf(
            TileCoord(x: 0, y: 1),
            other,
            (at) => const Rect.fromLTRB(4, 20, 8, 24).contains(at),
          ),
        },
      ),
    });
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize);
    addTearDown(overlay.dispose);
    BitmapSurfacePainter aPainter() => BitmapSurfacePainter(
      surface: BrushFrameDisplayCacheService(
        frameStore: cels,
        canvasSize: canvasSize,
      ).prepareFramePreview(key).previewSurface,
      overlayModel: overlay,
      showTransparentBackground: false,
      lineage: 'a-frame-that-waits-${nodes.hashCode}',
    );
    final store = FramePictureStore<FramePictureKey>(gpu: gpu);
    addTearDown(store.dispose);
    var standing = nodes;
    final run = runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => standing,
    );
    final shown = (
      cut: cut,
      frameIndex: 0,
      paintPaper: false,
      ghosts: FrameGhosts.none,
    );
    Future<void> standWith(BitmapSurfacePainter painter) => tester.pumpWidget(
      onAScreen(
        screen,
        size: viewSize,
        under: under,
        view: standingOn(
          run,
          picture: shown,
          nodes: standing,
          // The pasteboard left of the page in view.
          viewport: CanvasViewport(panX: 8, panY: 4),
          live: (
            activeSurfacePainter: painter,
            floatOverlay: null,
            liftedRows: const {},
          ),
        ),
      ),
    );
    await standWith(aPainter());
    return (
      store: store,
      picture: run.pictures.keyOfStack(nodes, shown),
      overlay: overlay,
      handAnew: ([nodes]) {
        standing = nodes ?? standing;
        return standWith(aPainter());
      },
    );
  }

  /// A step of the pen over the tile at [coord].
  Future<void> aStep(
    WidgetTester tester,
    ActiveStrokeOverlayModel overlay,
    TileCoord coord,
  ) async {
    overlay.showResultTiles([
      PromotedStrokeTile(coord, tileOf(coord, stroke, (_) => true), 1),
    ]);
    await tester.pump();
  }

  bool onlyTheScreen(Shot shot) {
    for (var at = 0; at < shot.rgba.length; at += 4) {
      if (Color.fromARGB(
            shot.rgba[at + 3],
            shot.rgba[at],
            shot.rgba[at + 1],
            shot.rgba[at + 2],
          ) !=
          under) {
        return false;
      }
    }
    return true;
  }

  for (final (name, waits) in [
    ('waits for a plugin', true),
    ('runs none', false),
  ]) {
    List<CompositeNode<CanvasStackRow>> nodesOf() =>
        inAFolder(waits ? [aPlugin(ShiftingFxPlugin(by: 2))] : const []);

    testWidgets('a frame that $name, its picture not there yet: '
        '${waits ? 'nothing drawn as it stands' : 'drawn as it stands'}', (
      tester,
    ) async {
      final screen = GlobalKey();
      final gpu = WritesNeverLand()..holdsRenders = true;
      addTearDown(gpu.letAllThrough);
      final nodes = nodesOf();
      expect(waitsForItsPlugins(nodes), waits, reason: '⛔premise');
      await standOn(tester, screen, nodes, gpu);
      await tester.pump();

      expect(onlyTheScreen(await shotOf(tester, screen)), waits);
    });

    testWidgets('a frame that $name: a step no patch can follow — past its '
        'picture — ${waits ? 'leaves the picture shown' : 'draws the frame '
                  'as it stands'}', (tester) async {
      final screen = GlobalKey();
      final gpu = WritesNeverLand();
      final (:store, :picture, :overlay, handAnew: _) = await standOn(
        tester,
        screen,
        nodesOf(),
        gpu,
      );
      expect(
        await settleAsync(tester, () => store.bytesOf(picture) != null),
        isTrue,
        reason: 'LIVENESS: the frame\'s picture is made',
      );
      await lendBothClocks(tester, rounds: 2);
      final before = await shotOf(tester, screen);

      await aStep(tester, overlay, TileCoord(x: -1, y: 0));
      expect(
        store.landingOf(keptByTheCanvas(tester, picture)),
        isNull,
        reason: '⛔premise: a picture does not grow — no patch goes past it',
      );

      expect(
        differences(before, await shotOf(tester, screen)),
        waits ? isEmpty : isNotEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  // One step on its way at a time, as in every frame (F-512 — a frame that
  // runs none is pinned by `a_stroke_written_into_the_picture_shown.dart`).
  testWidgets('a frame that waits for a plugin: once a step is in, the steps '
      'after it go in together, in the next patch', (tester) async {
    final screen = GlobalKey();
    final gpu = _WritesLandWhenLet();
    final (:store, :picture, :overlay, handAnew: _) = await standOn(
      tester,
      screen,
      inAFolder([aPlugin(ShiftingFxPlugin(by: 2))]),
      gpu,
    );
    expect(
      await settleAsync(tester, () => store.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    await aStep(tester, overlay, TileCoord(x: 0, y: 0));
    final first = store.landingOf(keptByTheCanvas(tester, picture));
    await aStep(tester, overlay, TileCoord(x: 1, y: 1));
    expect(
      identical(store.landingOf(keptByTheCanvas(tester, picture)), first),
      isTrue,
      reason: 'the second waits behind the first',
    );

    expect(
      await settleAsync(tester, () => gpu.writesWaiting > 0),
      isTrue,
      reason: 'LIVENESS: the first comes to be written',
    );
    gpu.landOne();
    expect(
      await settleAsync(tester, () {
        final now = store.landingOf(keptByTheCanvas(tester, picture));
        return now != null && !identical(now, first);
      }),
      isTrue,
      reason: 'the second goes in once the first is in',
    );
    gpu.landAll();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a frame that waits for a plugin: a step whose frame stands no '
      'more once its plugin has run does not go in', (tester) async {
    final screen = GlobalKey();
    final gpu = _WritesLandWhenLet()..landsAtOnce = true;
    final nodes = inAFolder([aPlugin(ShiftingFxPlugin(by: 2))]);
    final (:store, :picture, :overlay, :handAnew) = await standOn(
      tester,
      screen,
      nodes,
      gpu,
    );
    expect(
      await settleAsync(tester, () => store.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    await aStep(tester, overlay, TileCoord(x: 0, y: 0));
    final step = store.landingOf(keptByTheCanvas(tester, picture));
    expect(step, isNotNull, reason: '⛔premise: the step is on its way');

    // The pen's row handed anew before the plugin has run: the frame the
    // step was drawn by stands no more.
    await handAnew();

    bool? landed;
    unawaited(step!.then((value) => landed = value));
    expect(
      await settleAsync(tester, () => landed != null),
      isTrue,
      reason: 'LIVENESS: answered',
    );
    expect(landed, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  /// The columns [colour] shows in on [shot].
  Set<int> inkColumnsOf(Shot shot, {List<int> colour = ink}) => {
    for (var at = 0; at < shot.rgba.length; at += 4)
      if (shot.rgba[at] == colour[0] &&
          shot.rgba[at + 1] == colour[1] &&
          shot.rgba[at + 2] == colour[2] &&
          shot.rgba[at + 3] == colour[3])
        at ~/ 4 % shot.width,
  };

  /// What [screen] shows once [nodes]' frame stands there, its picture
  /// made.
  Future<Shot> shownOnceMade(
    WidgetTester tester,
    List<CompositeNode<CanvasStackRow>> nodes,
  ) async {
    final screen = GlobalKey();
    final (:store, :picture, overlay: _, handAnew: _) = await standOn(
      tester,
      screen,
      nodes,
      WritesNeverLand(),
    );
    expect(
      await settleAsync(tester, () => store.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    return shotOf(tester, screen);
  }

  // 🚨Over the pen's row as well as round it: a folder that holds no row the
  // pen is on is drawn whole and held for the pen's steps
  // ([HeldSubtreeRasters]), and one held with its step drawn as if off
  // would be cut from by the next round, which then never met the step.
  for (final (where, nodesOf, colour) in [
    ('round the pen\'s row', inAFolder, ink),
    ('over the pen\'s row', overThePen, other),
  ]) {
    testWidgets('a frame that waits for a plugin $where is shown as its '
        'plugin made it', (tester) async {
      final asDrawn = inkColumnsOf(
        await shownOnceMade(tester, nodesOf(const [])),
        colour: colour,
      );
      expect(asDrawn, isNotEmpty, reason: '⛔CONTROL: the ink, as drawn');

      final shown = inkColumnsOf(
        await shownOnceMade(
          tester,
          nodesOf([aPlugin(ShiftingFxPlugin(by: 2))]),
        ),
        colour: colour,
      );

      // Two canvas pixels to the right, as many of the screen's each.
      final by = 2 * tester.view.devicePixelRatio.round();
      expect(shown, {for (final column in asDrawn) column + by});
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a frame that waits for a plugin, handed another whose picture '
      'is not there yet, stays on the picture it showed', (tester) async {
    final screen = GlobalKey();
    final gpu = WritesNeverLand();
    addTearDown(gpu.letAllThrough);
    final (:store, :picture, overlay: _, :handAnew) = await standOn(
      tester,
      screen,
      inAFolder([aPlugin(ShiftingFxPlugin(by: 2))]),
      gpu,
    );
    expect(
      await settleAsync(tester, () => store.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    final before = await shotOf(tester, screen);
    expect(onlyTheScreen(before), isFalse, reason: '⛔premise: it is shown');

    gpu.holdsRenders = true;
    await handAnew(inAFolder([aPlugin(ShiftingFxPlugin(by: 3))]));
    await tester.pump();

    expect(differences(before, await shotOf(tester, screen)), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}

/// A GPU whose writes go in when let ([landOne]) — or at once, where it
/// [landsAtOnce] — the texels taken for the picture's own.
class _WritesLandWhenLet extends RendersHeld {
  bool landsAtOnce = false;
  final List<Completer<bool>> _writes = [];

  int get writesWaiting => _writes.length;

  void landOne() => _writes.removeAt(0).complete(true);

  void landAll() {
    landsAtOnce = true;
    for (final write in _writes) {
      write.complete(true);
    }
    _writes.clear();
  }

  @override
  Object? hold(ui.Image image) => image.clone();

  @override
  int levelsOf(Object held) {
    final image = held as ui.Image;
    return math.max(image.width, image.height).bitLength;
  }

  @override
  ui.Image imageOf(Object held) => (held as ui.Image).clone();

  @override
  Future<bool> write(Object held, List<BaseWrite> base, LevelWrites? levels) {
    if (landsAtOnce) {
      return Future.value(true);
    }
    final write = Completer<bool>();
    _writes.add(write);
    return write.future;
  }
}
