import 'dart:typed_data';

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
  const canvasSize = CanvasSize(width: 32, height: 32);
  const viewSize = Size(48, 40);
  const under = Color(0xFF203040);
  const ink = [0x00, 0x40, 0x00, 0xFF];
  const stroke = [0x40, 0x00, 0x00, 0xFF];
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('inked'),
    frameId: FrameId('f'),
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
          pixels.setRange((y * tileSize + x) * 4, (y * tileSize + x) * 4 + 4,
              colour);
        }
      }
    }
    return BitmapTile(size: tileSize, pixels: pixels);
  }

  /// A canvas standing on [nodes]' frame — its one row inked at (4..8,
  /// 4..8) — over a store on [gpu]; what [screen] shows, and the overlay
  /// its pen's steps are shown by.
  Future<
    ({
      FramePictureStore<FramePictureKey> store,
      FramePictureKey picture,
      ActiveStrokeOverlayModel overlay,
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
    });
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize);
    addTearDown(overlay.dispose);
    final painter = BitmapSurfacePainter(
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
    final run = runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => nodes,
    );
    final shown = (
      cut: cut,
      frameIndex: 0,
      paintPaper: false,
      ghosts: FrameGhosts.none,
    );
    await tester.pumpWidget(
      onAScreen(
        screen,
        size: viewSize,
        under: under,
        view: standingOn(
          run,
          picture: shown,
          nodes: nodes,
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
    return (
      store: store,
      picture: run.pictures.keyOfStack(nodes, shown),
      overlay: overlay,
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

  for (final (name, waits) in [('waits for a plugin', true), ('runs none', false)]) {
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

    testWidgets('a frame that $name: a stroke\'s steps go in '
        '${waits ? 'one patch at a time' : 'a patch a step'}', (tester) async {
      final screen = GlobalKey();
      final gpu = WritesNeverLand();
      final (:store, :picture, :overlay) = await standOn(
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

      await aStep(tester, overlay, TileCoord(x: 0, y: 0));
      final first = store.landingOf(keptByTheCanvas(tester, picture));
      expect(first, isNotNull, reason: '⛔premise: the step is on its way');
      await aStep(tester, overlay, TileCoord(x: 1, y: 1));
      final after = store.landingOf(keptByTheCanvas(tester, picture));

      expect(identical(after, first), waits);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a frame that $name: a step no patch can follow — past its '
        'picture — ${waits ? 'leaves the picture shown' : 'draws the frame '
                  'as it stands'}', (tester) async {
      final screen = GlobalKey();
      final gpu = WritesNeverLand();
      final (:store, :picture, :overlay) = await standOn(
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
}
