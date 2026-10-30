import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🚨★★★A PAINT UNDER A CLIP DRAWS WHAT IT SHOWS, AND ONLY THAT
/// (one-picture-per-frame ②-5a, 2026-10-25). A patch on its way into a
/// frame's picture is drawn as it stands under its own rects — on the
/// screen ([StackedFrame.paintOnScreen]) and into the picture, as the store
/// records a patch ([StackedFrame.drawing]) — and the walk composed
/// everything in view there: a stroke's every step rastered the whole
/// view's buffer, and recorded every row of the whole pasteboard into the
/// patch.
///
/// Cut to the clip, it is still the same pixels inside it: a blur reads
/// past the clip's edge as it reads past the view's, by its own spread.
void main() {
  const tileSize = 8;
  const canvasSize = CanvasSize(width: 64, height: 64);
  const world = Rect.fromLTWH(0, 0, 64, 64);
  // A patch's rect, well inside the page: the blurs reach across its edges.
  const clip = Rect.fromLTWH(24, 24, 8, 8);
  const blur = 2.0;
  const paper = ProjectBackground.color(0xFF30A060);

  BrushFrameKey keyOf(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );

  /// [seed]'s ink over the whole page: every pixel different, some half
  /// transparent and some empty.
  BitmapSurface surfaceOf(int seed) {
    final tiles = <TileCoord, BitmapTile>{};
    for (var ty = 0; ty < 8; ty += 1) {
      for (var tx = 0; tx < 8; tx += 1) {
        var tile = BitmapTile.blank(size: tileSize);
        for (var y = 0; y < tileSize; y += 1) {
          for (var x = 0; x < tileSize; x += 1) {
            final wx = tx * tileSize + x;
            final wy = ty * tileSize + y;
            final pattern = (wx * 5 + wy * 3 + seed) % 7;
            if (pattern == 0) {
              continue;
            }
            tile = writeRgbaColorToBitmapTile(
              tile: tile,
              x: x,
              y: y,
              color: RgbaColor(
                r: (wx * 31 + seed * 70) % 256,
                g: (wy * 29 + seed * 40) % 256,
                b: (wx * wy * 7 + seed * 90) % 256,
                a: pattern.isEven ? 255 : 150,
              ),
            );
          }
        }
        tiles[TileCoord(x: tx, y: ty)] = tile;
      }
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: tiles,
    );
  }

  final surfaces = {
    for (final (layer, seed) in [('floor', 3), ('under', 1), ('over', 2)])
      keyOf(layer): surfaceOf(seed),
  };

  CompositeNode<CanvasStackRow> row(
    String layer, {
    double opacity = 1,
    List<ResolvedLayerEffect> effects = const [],
  }) => CompositeLeaf<CanvasStackRow>(
    CanvasLayerImageRequest(
      frameKey: keyOf(layer),
      opacity: opacity,
      effects: effects,
    ),
  );

  final blurred = [
    ResolvedLayerEffect(kind: EffectKind.blur, values: [blur, 0]),
  ];

  final scenes = <String, List<CompositeNode<CanvasStackRow>>>{
    'two rows, one over the other': [
      row('under'),
      row('over', opacity: 0.6),
    ],
    'a blurred folder': [
      row('floor'),
      CompositeGroup<CanvasStackRow>(
        opacity: 0.8,
        blendMode: LayerBlendMode.normal,
        effects: blurred,
        children: [row('under'), row('over', opacity: 0.6)],
      ),
    ],
    'a folder inside a blurred folder': [
      row('floor'),
      CompositeGroup<CanvasStackRow>(
        opacity: 1,
        blendMode: LayerBlendMode.normal,
        effects: blurred,
        children: [
          CompositeGroup<CanvasStackRow>(
            opacity: 0.7,
            blendMode: LayerBlendMode.normal,
            children: [row('under'), row('over')],
          ),
        ],
      ),
    ],
    'a blurred row': [
      row('floor'),
      row('over', effects: blurred),
    ],
  };

  StackedFrame frameOf(List<CompositeNode<CanvasStackRow>> nodes) =>
      stackedFrameOf(
        nodes,
        page: (
          canvasSize: canvasSize,
          pasteboardReach: PasteboardReach.whole,
          paintPaper: true,
          paperBackground: paper,
        ),
        surfaceOf: (cel) => surfaces[cel],
      );

  Future<Uint8List> pixelsOf(
    WidgetTester tester,
    ui.PictureRecorder recorder,
    Rect rect,
  ) async => (await tester.runAsync(() async {
    final image = await recorder.endRecording().toImage(
      rect.width.toInt(),
      rect.height.toInt(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }))!;

  /// The pixels where [whole] — the world — and [cut] — [clip] alone —
  /// differ inside [clip] by more than [by] a channel, as
  /// `(x, y): whole → cut` in world pixels.
  List<String> differencesInsideTheClip(
    Uint8List whole,
    Uint8List cut, {
    int by = 0,
  }) {
    final out = <String>[];
    for (var y = 0; y < clip.height.toInt(); y += 1) {
      for (var x = 0; x < clip.width.toInt(); x += 1) {
        final wx = clip.left.toInt() + x;
        final wy = clip.top.toInt() + y;
        final a = ((wy * world.width.toInt()) + wx) * 4;
        final b = ((y * clip.width.toInt()) + x) * 4;
        final pixelA = whole.sublist(a, a + 4);
        final pixelB = cut.sublist(b, b + 4);
        if (pixelA.indexed.any(
          (entry) => (entry.$2 - pixelB[entry.$1]).abs() > by,
        )) {
          out.add('($wx, $wy): $pixelA → $pixelB');
        }
      }
    }
    return out;
  }

  /// What a folder's raster covered last, or null where none was made.
  Rect? lastFolderRaster() => debugLastSubtreeRaster?.bounds;

  /// What the clip may make a folder raster: the clip, and the spread its
  /// blur reads past it — and a pixel the clip's bounds are rounded out by.
  final reach = clip.inflate(blur + 1);
  bool inReach(Rect rect) => reach.expandToInclude(rect) == reach;

  for (final MapEntry(key: name, value: scene) in scenes.entries) {
    final hasFolder = scene.any((node) => node is CompositeGroup);
    // 🗣️a-blur-under-a-clip-cuts-its-edge-on-vulkan-Q1 = a (유저 2026-10-30
    // 「1/255 를 받아들인다」): a folder's blur, on Impeller, a channel apart
    // here and there inside the patch. 🔬The folder's raster is the same
    // bytes both ways; Impeller blurs a raster of another size into values
    // a 255th apart below the byte and lays them on the paper unrounded
    // (2 and 9 of 64 pixels, 10-30). ⛔Not a slack for a row's own blur,
    // or for Skia: those are exact.
    final apart = hasFolder && ui.ImageFilter.isShaderFilterSupported ? 1 : 0;

    testWidgets('$name — into the picture: the same pixels inside a '
        'patch, and nothing drawn far past it', (tester) async {
      final drawing = frameOf(scene).drawing;

      debugLastSubtreeRaster = null;
      final wholeRecorder = ui.PictureRecorder();
      drawing.draw(Canvas(wholeRecorder)..clipRect(world));
      final wholeFolder = lastFolderRaster();
      final whole = await pixelsOf(tester, wholeRecorder, world);

      // As the store records a patch ([FramePictureStore.patch]).
      debugLastSubtreeRaster = null;
      final cutRecorder = ui.PictureRecorder();
      drawing.draw(
        Canvas(cutRecorder)
          ..translate(-clip.left, -clip.top)
          ..clipRect(clip),
      );
      final cutFolder = lastFolderRaster();
      final cut = await pixelsOf(tester, cutRecorder, clip);

      final differing = differencesInsideTheClip(whole, cut, by: apart);
      expect(
        differing,
        isEmpty,
        reason: 'the patch is not the frame where it lies: '
            '${differing.length} pixels, the first '
            '${differing.take(6).join(', ')}',
      );
      if (hasFolder) {
        expect(
          wholeFolder!.width,
          greaterThanOrEqualTo(world.width),
          reason: 'control: the frame laid whole rasters its folder whole',
        );
        expect(
          inReach(cutFolder!),
          isTrue,
          reason: 'the patch rastered its folder over $cutFolder — the '
              'frame round it, where the patch covers $clip',
        );
      }
    });

    testWidgets('$name — on the screen: the same pixels inside a patch, and '
        'nothing composed far past it', (tester) async {
      final frame = frameOf(scene);
      void paintOnScreen(Canvas canvas) => frame.paintOnScreen(
        canvas,
        world.size,
        viewport: CanvasViewport(),
        devicePixelRatio: 1,
      );

      debugLastSubtreeRaster = null;
      final wholeRecorder = ui.PictureRecorder();
      paintOnScreen(Canvas(wholeRecorder));
      final wholeFolder = lastFolderRaster();
      final whole = await pixelsOf(tester, wholeRecorder, world);

      // As a screen draws a patch still landing (`FramePictureView`).
      debugLastSubtreeRaster = null;
      final cutRecorder = ui.PictureRecorder();
      paintOnScreen(
        Canvas(cutRecorder)
          ..translate(-clip.left, -clip.top)
          ..clipRect(clip, doAntiAlias: false),
      );
      final cutFolder = lastFolderRaster();
      final cut = await pixelsOf(tester, cutRecorder, clip);

      final differing = differencesInsideTheClip(whole, cut, by: apart);
      expect(
        differing,
        isEmpty,
        reason: 'the patch on the screen is not the frame where it lies: '
            '${differing.length} pixels, the first '
            '${differing.take(6).join(', ')}',
      );
      if (hasFolder) {
        expect(
          wholeFolder!.width,
          greaterThanOrEqualTo(world.width),
          reason: 'control: the view drawn whole rasters its folder whole',
        );
        expect(
          inReach(cutFolder!),
          isTrue,
          reason: 'the patch on the screen rastered its folder over '
              '$cutFolder — the view round it, where the patch covers $clip',
        );
      }
    });
  }
}
