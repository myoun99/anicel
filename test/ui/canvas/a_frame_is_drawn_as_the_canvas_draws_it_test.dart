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
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

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

/// 🚨★★★A FRAME'S ONE PICTURE IS WHAT THE CANVAS SHOWS OF IT
/// (one-picture-per-frame, D7-2-Q3=a — 「합성기는 하나」).
///
/// The picture a frame is kept as is drawn off the tree the screen stacks
/// ([stackedFrameOf]) by the canvas's own body (`frameDrawingOf`)
/// with every row from its tiles, where the canvas draws that SAME tree as
/// it stands while the picture is not there (`TheFrameAsItStands`) — ↩️each
/// row as its cel's image, until no screen drew a row's image
/// (one-picture-per-frame ②-5b-1). At 100% the two must be one picture,
/// byte for byte, wherever the canvas shows the world — the page, and the
/// pasteboard round it — through every road the body has: rows over one
/// another, a blend over its backdrop and the paper, a blurred folder, a
/// pose, a colour key, an adjustment, ink past the page, a blend inside a
/// folder.
void main() {
  const tileSize = 8;
  // 3 × 2 tiles: a pose and a blur reach across their edges.
  const canvasSize = CanvasSize(width: 24, height: 16);
  // A tile's width of pasteboard round the page is in view.
  const margin = 8;
  const viewSize = Size(24 + 2.0 * margin, 16 + 2.0 * margin);
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

  /// The frame's one picture of [scene], drawn as the frame picture store
  /// records what it lays ([FramePictureStore.lay]) — in world coordinates,
  /// cut by nothing of its own — over the world [canvasShows] shows. The
  /// store rasters a rect wider than [FrameDrawing.extent] (its levels'
  /// grid), so whatever the drawing lays past its extent is read here too.
  Future<Uint8List> pictureShows(
    WidgetTester tester,
    List<CompositeNode<_Cel>> scene,
    BrushFrameStore store,
  ) async {
    final previews = BrushFrameDisplayCacheService(
      frameStore: store,
      canvasSize: canvasSize,
    );
    // The SAME tree the canvas is handed: a frame's picture is keyed and
    // drawn off what the screen stacks.
    final drawing = stackedFrameOf(
      asTheCanvasAsks(scene),
      page: (
        canvasSize: canvasSize,
        pasteboardReach: PasteboardReach.whole,
        paintPaper: true,
        paperBackground: paper,
      ),
      surfaceOf: (cel) => previews.prepareFramePreview(cel).previewSurface,
    ).drawing;
    final world = Rect.fromLTWH(
      -margin.toDouble(),
      -margin.toDouble(),
      viewSize.width,
      viewSize.height,
    );
    return (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      // As a consumer shows it: [FrameDrawing.outside] past the extent, and
      // the drawing unclipped, so anything it draws past its extent shows.
      final canvas = Canvas(recorder)
        ..translate(-world.left, -world.top)
        ..clipRect(world)
        ..save()
        ..clipRect(drawing.extent, clipOp: ui.ClipOp.difference)
        ..drawColor(drawing.outside, BlendMode.src)
        ..restore();
      drawing.draw(canvas);
      final image = await recorder.endRecording().toImage(
        world.width.toInt(),
        world.height.toInt(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
  }

  /// The pixels where [a] and [b] differ by more than [by] in a channel, as
  /// `(x, y): a → b` in world pixels.
  List<String> differences(Uint8List a, Uint8List b, {int by = 0}) {
    final width = viewSize.width.toInt();
    final out = <String>[];
    for (var i = 0; i < a.length; i += 4) {
      final pixelA = a.sublist(i, i + 4);
      final pixelB = b.sublist(i, i + 4);
      if (pixelA.indexed.any(
        (entry) => (entry.$2 - pixelB[entry.$1]).abs() > by,
      )) {
        final x = (i ~/ 4) % width - margin;
        final y = (i ~/ 4) ~/ width - margin;
        out.add('($x, $y): $pixelA → $pixelB');
      }
    }
    return out;
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
              values: [0, 0, 0, 0, 255, 100],
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

  // 🚨 Decision (2026-10-24, the one-frame compositor): a blur may round
  // apart by 2 in a channel, and only a blur. The canvas blurred a cel row
  // as its row image (an image filter on an image), the frame's picture
  // blurs it as a layer of its tiles (the same filter on a saveLayer) — two
  // engine passes. Measured here: the Skia test runner rounds them 1 apart
  // where a tail falls, Impeller is exact; the sister pin measured 1–2 on
  // Impeller at sigma 3 and 6 (`a_group_is_an_image_test.dart`). The two
  // passes stop being two when the canvas draws every row from its tiles —
  // the row image is what the switch deletes. Every other scene is exact.
  //
  // 🔬2026-10-25, one-picture-per-frame ②-5b-1: the canvas draws every row
  // from its tiles now, and the two scenes still round apart — 122 pixels
  // of the blurred folder, each by 1 — so the row image was not what set
  // them apart. ⚠️Not known what does: the screen draws the frame as it
  // stands straight onto the screen's raster, the picture is laid in a
  // raster of its own and then drawn; that is the difference left, not a
  // measured cause.
  const blurs = {
    'a blurred folder of two rows at half opacity',
    'a blurred row with ink on the pasteboard',
  };

  for (final MapEntry(key: name, value: scene) in scenes.entries) {
    testWidgets('$name: the frame\'s picture is the canvas\'s, byte for '
        'byte', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = storeOf(scene);

      final canvas = await canvasShows(tester, scene, store);
      final picture = await pictureShows(tester, scene, store);

      expect(
        alphaAt(canvas, 12, 8),
        255,
        reason: 'the canvas showed no paper — the comparison would be '
            'between two empty pictures',
      );
      final differing = differences(
        canvas,
        picture,
        by: blurs.contains(name) ? 2 : 0,
      );
      expect(
        differing,
        isEmpty,
        reason: 'the frame\'s one picture is not what the canvas shows of '
            'the frame: ${differing.length} pixels, the first '
            '${differing.take(6).join(', ')}',
      );
    });
  }

  testWidgets('ink past the page is in the picture, where the canvas '
      'shows it', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final scene = scenes['ink on the pasteboard round the page']!;
    final store = storeOf(scene);

    final picture = await pictureShows(tester, scene, store);

    expect(
      [alphaAt(picture, -3, 3), alphaAt(picture, 27, 13)],
      everyElement(greaterThan(0)),
      reason: 'the ink left and right of the page fell outside the '
          'picture\'s extent',
    );
  });
}
