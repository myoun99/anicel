import '../../helpers/a_canvas_standing_on_a_frame.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/tree_nodes.dart';
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
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/stack_as_the_plan_hands_it.dart';
import '../../helpers/the_frame_as_it_stands.dart';

/// One row's composite paint, written once for both of its shapes.
typedef _RowPaint = ({
  double opacity,
  LayerBlendMode blendMode,
  LayerPlacement? placement,
  List<ResolvedLayerEffect> effects,
});

/// A cel of a scene: its layer, the seed its pixels are drawn from, the
/// tiles it holds and its row's paint.
typedef _Cel = ({
  String layer,
  int seed,
  List<TileCoord> tiles,
  _RowPaint paint,
});

/// A FRAME'S WORLD IS THE PAGE AND WHAT ITS ROWS DRAW (one-picture-per-frame,
/// D7-2-Q3=a — 「합성기는 하나」): ink past the page is in it, and what repeats
/// the paper's edge is cut to the paper.
///
/// ↩️It stood as the frame's picture and the canvas as it stands being one
/// picture byte for byte, while they were two routes (until the engine laid
/// both, flip lane ⓑ).
void main() {
  opensTheEnginesScreens();
  const tileSize = defaultCelTileSize;
  // 3 × 2 tiles: a pose and a blur reach across their edges.
  const canvasSize = CanvasSize(width: 3 * tileSize, height: 2 * tileSize);
  // A tile's width of pasteboard round the page is in view.
  const margin = tileSize;
  const viewSize = Size(
    3.0 * tileSize + 2 * margin,
    2.0 * tileSize + 2 * margin,
  );
  // Something to blend against: a multiply over nothing is
  // indistinguishable from a dropped blend.
  const paper = ProjectBackground.color(0xFF30A060);
  final pageTiles = [
    TileCoord(x: 0, y: 0),
    TileCoord(x: 1, y: 0),
    TileCoord(x: 2, y: 0),
    TileCoord(x: 0, y: 1),
    TileCoord(x: 1, y: 1),
    TileCoord(x: 2, y: 1),
  ];

  setUpAll(LayerBlendShader.load);

  BrushFrameKey keyOf(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );

  /// [cel]'s tile at [coord]: every pixel different, some half transparent
  /// and some empty, so a row that is laid twice, or not at all, shows.
  BitmapTile tileOf(_Cel cel, TileCoord coord) {
    var tile = BitmapTile.blank(size: tileSize);
    for (var y = 0; y < tileSize; y += 1) {
      for (var x = 0; x < tileSize; x += 1) {
        final wx = coord.x * tileSize + x;
        final wy = coord.y * tileSize + y;
        final pattern = (wx * 5 + wy * 3 + cel.seed) % 7;
        if (pattern == 0) {
          continue;
        }
        tile = writeRgbaColorToBitmapTile(
          tile: tile,
          x: x,
          y: y,
          color: RgbaColor(
            r: (wx * 31 + cel.seed * 70) % 256,
            g: (wy * 29 + cel.seed * 40) % 256,
            b: (wx * wy * 7 + cel.seed * 90) % 256,
            a: pattern.isEven ? 255 : 150,
          ),
        );
      }
    }
    return tile;
  }

  /// A store holding every cel of [scene] as a FILE-BACKED entry — the
  /// image cache refuses a cel without a drawing state at its first gate.
  BrushFrameStore storeOf(List<CompositeNode<_Cel>> scene) {
    final store = BrushFrameStore();
    keepInAFile(store, {
      for (final CompositeLeaf(payload: node)
          in preorderNodes(scene).whereType<CompositeLeaf<_Cel>>())
        keyOf(node.layer): BitmapSurface(
          canvasSize: canvasSize,
          tileSize: tileSize,
          tiles: {for (final coord in node.tiles) coord: tileOf(node, coord)},
        ),
    });
    return store;
  }

  /// [scene] as the canvas asks it: a row image for each cel.
  List<CompositeNode<CanvasStackRow>> asTheCanvasAsks(
    List<CompositeNode<_Cel>> scene,
  ) => stackAsThePlanHandsIt(
    mapCompositeLeaves<_Cel, CanvasStackRow>(
      scene,
      (cel) => CanvasLayerImageRequest(
        frameKey: keyOf(cel.layer),
        opacity: cel.paint.opacity,
        blendMode: cel.paint.blendMode,
        placement: cel.paint.placement,
        effects: cel.paint.effects,
      ),
    ),
  );

  final screen = GlobalKey();

  /// What the canvas standing still at 100% shows of [scene] once its rows
  /// landed, a pixel of the world a pixel of the shot — the world's
  /// (−[margin], −[margin]) at its top left.
  Future<Uint8List> canvasShows(
    WidgetTester tester,
    List<CompositeNode<_Cel>> scene,
    BrushFrameStore store,
  ) async {
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: screen,
            child: SizedBox.fromSize(
              size: viewSize,
              child: TheFrameAsItStands(
                nodes: asTheCanvasAsks(scene),
                imageCache: images,
                canvasSize: canvasSize,
                viewport: CanvasViewport(
                  panX: margin.toDouble(),
                  panY: margin.toDouble(),
                ),
                paintPaper: true,
                paperBackground: paper,
              ),
            ),
          ),
        ),
      ),
    );
    await lendBothClocks(
      tester,
      rounds: 8,
      beat: const Duration(milliseconds: 30),
    );
    final render =
        screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return (await tester.runAsync(() async {
      final image = await render.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
  }

  /// The alpha of world pixel ([x], [y]) in [shot].
  int alphaAt(Uint8List shot, int x, int y) =>
      shot[((y + margin) * viewSize.width.toInt() + x + margin) * 4 + 3];

  const _RowPaint plain = (
    opacity: 1.0,
    blendMode: LayerBlendMode.normal,
    placement: null,
    effects: <ResolvedLayerEffect>[],
  );
  _RowPaint paintOf({
    double opacity = 1.0,
    LayerBlendMode blendMode = LayerBlendMode.normal,
    LayerPlacement? placement,
    List<ResolvedLayerEffect> effects = const [],
  }) => (
    opacity: opacity,
    blendMode: blendMode,
    placement: placement,
    effects: effects,
  );
  CompositeNode<_Cel> cel(
    String layer,
    int seed, {
    _RowPaint paint = plain,
    List<TileCoord>? tiles,
  }) => CompositeLeaf<_Cel>((
    layer: layer,
    seed: seed,
    tiles: tiles ?? pageTiles,
    paint: paint,
  ));

  final repeatingTheEdge = ResolvedLayerEffect(
    kind: EffectKind.blur,
    values: [2, 0, 1],
  );
  final scenes = <String, List<CompositeNode<_Cel>>>{
    'two rows, one over the other': [
      cel('under', 1),
      cel('over', 2, paint: paintOf(opacity: 0.6)),
    ],
    'a multiply row over a row and the paper': [
      cel('under', 1, tiles: [TileCoord(x: 0, y: 0)]),
      cel(
        'over',
        2,
        paint: paintOf(opacity: 0.7, blendMode: LayerBlendMode.multiply),
      ),
    ],
    // The one blend a row keeps on itself: the plan lifts every other but
    // normal over its backdrop (`composeOverTheirBackdrops`).
    'an add row over a row and the paper': [
      cel('under', 1, tiles: [TileCoord(x: 2, y: 0)]),
      cel(
        'over',
        2,
        paint: paintOf(opacity: 0.8, blendMode: LayerBlendMode.add),
      ),
    ],
    'a blurred folder of two rows at half opacity': [
      cel('floor', 3),
      CompositeGroup<_Cel>(
        opacity: 0.5,
        blendMode: LayerBlendMode.normal,
        effects: [ResolvedLayerEffect(kind: EffectKind.blur, values: [1, 0])],
        children: [
          cel('under', 1, tiles: [TileCoord(x: 1, y: 0)]),
          cel('over', 2, tiles: [TileCoord(x: 1, y: 1)]),
        ],
      ),
    ],
    'a posed row': [
      cel('under', 1),
      cel(
        'over',
        2,
        tiles: [TileCoord(x: 0, y: 0), TileCoord(x: 1, y: 0)],
        paint: paintOf(placement: const LayerPlacement(1, 0, 0, 1, 3, 2)),
      ),
    ],
    'a keyed row': [
      cel('under', 1),
      cel(
        'over',
        2,
        paint: paintOf(
          effects: [
            ResolvedLayerEffect(
              kind: EffectKind.colorKey,
              values: [0, 0xFF000000, 255, 100],
            ),
            ResolvedLayerEffect(
              kind: EffectKind.brightnessContrast,
              values: [20, 15],
            ),
          ],
        ),
      ),
    ],
    'an adjustment over the rows': [
      cel('under', 1),
      CompositeAdjustment<_Cel>(
        effects: [
          ResolvedLayerEffect(
            kind: EffectKind.brightnessContrast,
            values: [-30, 40],
          ),
        ],
        mix: 0.6,
        children: [cel('over', 2, tiles: [TileCoord(x: 2, y: 1)])],
      ),
    ],
    'ink on the pasteboard round the page': [
      cel(
        'past',
        4,
        tiles: [
          TileCoord(x: -1, y: 0),
          TileCoord(x: 0, y: 0),
          TileCoord(x: 3, y: 1),
        ],
      ),
    ],
    // Its spread past the outermost ink is cut where the frame ends: the
    // page and every row's content, and not a pixel further — though the
    // canvas's buffer ends past it, on the grid of the frame's picture.
    'a blurred row with ink on the pasteboard': [
      cel(
        'past',
        4,
        tiles: [TileCoord(x: -1, y: 0), TileCoord(x: 3, y: 1)],
        paint: paintOf(
          effects: [ResolvedLayerEffect(kind: EffectKind.blur, values: [2, 0])],
        ),
      ),
    ],
    // 🗣️I-132-Q14 a: the edge it repeats is the paper's, on a row and a
    // folder alike — and its ink on the pasteboard is out of sight.
    'a row repeating the paper\'s edge, with ink on the pasteboard': [
      cel(
        'past',
        4,
        tiles: [TileCoord(x: -1, y: 0), ...pageTiles],
        paint: paintOf(effects: [repeatingTheEdge]),
      ),
    ],
    'a folder repeating the paper\'s edge, with ink on the pasteboard': [
      CompositeGroup<_Cel>(
        opacity: 1,
        blendMode: LayerBlendMode.normal,
        effects: [repeatingTheEdge],
        children: [
          cel('past', 4, tiles: [TileCoord(x: -1, y: 0), ...pageTiles]),
        ],
      ),
    ],
    'a screen row inside a folder': [
      cel('floor', 3),
      CompositeGroup<_Cel>(
        opacity: 0.8,
        blendMode: LayerBlendMode.normal,
        children: [
          cel('under', 1, tiles: [TileCoord(x: 0, y: 1)]),
          cel(
            'over',
            2,
            paint: paintOf(opacity: 0.9, blendMode: LayerBlendMode.screen),
          ),
        ],
      ),
    ],
  };

  for (final name in [
    'a row repeating the paper\'s edge, with ink on the pasteboard',
    'a folder repeating the paper\'s edge, with ink on the pasteboard',
  ]) {
    testWidgets('$name: the canvas shows none of it past the page', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final scene = scenes[name]!;
      final canvas = await canvasShows(tester, scene, storeOf(scene));
      expect(
        [
          for (var x = -margin; x < 0; x += 1)
            alphaAt(canvas, x, 3 * tileSize ~/ 8),
        ],
        everyElement(0),
        reason: 'the blur repeating the paper\'s edge is cut to the paper',
      );
    });
  }

  testWidgets('ink past the page is in the picture, where the canvas '
      'shows it', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final scene = scenes['ink on the pasteboard round the page']!;
    final store = storeOf(scene);

    final picture = await canvasShows(tester, scene, store);

    // Inside the tile left of the page, and the one right of its foot.
    expect(
      [
        alphaAt(picture, -3 * tileSize ~/ 8, 3 * tileSize ~/ 8),
        alphaAt(picture, 27 * tileSize ~/ 8, 13 * tileSize ~/ 8),
      ],
      everyElement(greaterThan(0)),
      reason: 'the ink left and right of the page fell outside the '
          'picture\'s extent',
    );
  });
}
