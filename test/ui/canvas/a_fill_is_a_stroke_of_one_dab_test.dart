import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/placed_tile.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_commit_builder.dart';
import 'package:anicel/src/services/brush_fill_promotion.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/canvas_selection_paint_clip.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨★★★A FILL IS A STROKE OF ONE DAB (유저 절대규칙 2026-09-17: 「보이는
/// 중이랑 결과랑 절대로 다르면 안 되」). The tap makes the tiles the commit
/// will land, the overlay shows them as its pre-blended result tiles, and
/// the commit installs the same objects — so what the fill shows before it
/// commits is the commit, byte for byte, at every level.
void main() {
  const tileSize = 8;
  const canvasSize = CanvasSize(width: 32, height: 32);
  const layerId = LayerId('layer');
  const frameId = FrameId('frame');
  final cache = BitmapTileImageCache.instance;
  const black = [0, 0, 0, 255];
  const clear = [0, 0, 0, 0];

  /// A tile of [size] whose pixels are [rgbaAt], with its picture drawn
  /// the same way and given to the cache as a landed decode.
  BitmapTile pictured(
    TileCoord coord,
    int size,
    List<int> Function(int x, int y) rgbaAt,
  ) {
    final pixels = Uint8List(size * size * 4);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    for (var y = 0; y < size; y += 1) {
      for (var x = 0; x < size; x += 1) {
        final rgba = rgbaAt(x, y);
        pixels.setRange((y * size + x) * 4, (y * size + x) * 4 + 4, rgba);
        if (rgba[3] != 0) {
          canvas.drawRect(
            ui.Rect.fromLTWH(x * 1.0, y * 1.0, 1, 1),
            ui.Paint()
              ..color = ui.Color.fromARGB(rgba[3], rgba[0], rgba[1], rgba[2]),
          );
        }
      }
    }
    final tile = BitmapTile(size: size, pixels: pixels);
    final picture = recorder.endRecording();
    cache.adoptDecoded(
      tile,
      picture.toImageSync(size, size),
    );
    picture.dispose();
    return tile;
  }

  /// Every tile of the cel: a black column at every fourth canvas x.
  BitmapSurface columns() => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (var ty = 0; ty * tileSize < canvasSize.height; ty += 1)
        for (var tx = 0; tx * tileSize < canvasSize.width; tx += 1)
          TileCoord(x: tx, y: ty): pictured(
            TileCoord(x: tx, y: ty),
            tileSize,
            (x, y) => (tx * tileSize + x) % 4 == 0 ? black : clear,
          ),
    },
  );

  /// A 16×16 stamp with a black column at every fourth x, offset by two —
  /// landed over the top-left 16×16 of the cel, each 4×4 block then holds
  /// two black columns.
  BrushDab fillDab({double opacity = 1}) {
    final rgba = Uint8List(16 * 16 * 4);
    for (var y = 0; y < 16; y += 1) {
      for (var x = 0; x < 16; x += 1) {
        if (x % 4 == 2) {
          rgba.setRange((y * 16 + x) * 4, (y * 16 + x) * 4 + 4, black);
        }
      }
    }
    return BrushDab(
      center: CanvasPoint(x: 8, y: 8),
      color: 0xFF000000,
      size: 16,
      opacity: opacity,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: BrushStampImage(id: 'columns', width: 16, height: 16, rgba: rgba),
    );
  }

  Uint8List bytesOf(BitmapTile tile) => tile.readPixels((_, px) => Uint8List.fromList(px));

  test('the promoted tiles are the tiles the commit lands — with a selection '
      'and an opacity, the two roundings that could have split them', () {
    final base = columns();
    final region = CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(left: 2, top: 2, right: 14, bottom: 14),
    );
    final dab = fillDab(opacity: 0.5);
    final promoted = promoteFillDab(
      surface: base,
      dab: dab,
      blendMode: BrushBlendMode.color,
      selection: region,
      layerId: layerId,
      frameId: frameId,
    );
    expect(promoted, isNotEmpty);

    // The classic route, exactly as the panel's commit funnel runs it for
    // a fill it has no promoted tiles for.
    final clipped = clipDabsToSelection(
      dabs: [dab],
      canvasSize: canvasSize,
      tileSize: tileSize,
      region: region,
    )!;
    final classic = brushCommitResultForBrushDabSequenceOnBitmapSurface(
      surface: base,
      sequence: BrushDabSequence([dab]),
      layerId: layerId,
      frameId: frameId,
      prerasterizedStrokePixels: clipped.pixels,
      prerasterizedStrokeBounds: clipped.bounds,
    );
    // And the promotion route, as the commit lands it: a tile PUT.
    final installed = brushCommitResultForBrushDabSequenceOnBitmapSurface(
      surface: base,
      sequence: BrushDabSequence([dab]),
      layerId: layerId,
      frameId: frameId,
      promotedBase: base,
      promotedTiles: [
        for (final entry in promoted) (coord: entry.coord, tile: entry.tile),
      ],
    );
    expect(installed.dirtyTiles.coords, classic.dirtyTiles.coords);
    for (final coord in classic.dirtyTiles.coords) {
      expect(
        bytesOf(installed.afterSurface.tileAt(coord)!),
        bytesOf(classic.afterSurface.tileAt(coord)!),
        reason: '$coord: the promoted tile and the classic commit\'s tile '
            'are the same bytes',
      );
    }
  });

  test('a fill that lands nothing promotes nothing', () {
    final base = columns();
    final outside = CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(left: 24, top: 24, right: 32, bottom: 32),
    );
    expect(
      promoteFillDab(
        surface: base,
        dab: fillDab(),
        blendMode: BrushBlendMode.color,
        selection: outside,
        layerId: layerId,
        frameId: frameId,
      ),
      isEmpty,
    );
  });

  Widget stackAt({
    required CanvasViewport viewport,
    required Size logicalSize,
    required BitmapSurfacePainter live,
    required LayerFrameImageCache images,
    DisplayBufferCache? buffers,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: logicalSize.width,
          height: logicalSize.height,
          child: CanvasLayerStackView(
            nodes: const [
              CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1)),
            ],
            imageCache: images,
            canvasSize: canvasSize,
            viewport: viewport,
            activeSurfacePainter: live,
            paintPaper: true,
            paperBackground: ProjectBackground.defaultBackground,
            debugBufferCache: buffers,
          ),
        ),
      ),
    ),
  );

  CustomPainter painterOf(WidgetTester tester) => tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(CanvasLayerStackView),
          matching: find.byType(CustomPaint),
        ),
      )
      .where((paint) => paint.painter != null)
      .first
      .painter!;

  Future<Uint8List> paintBytes(
    WidgetTester tester,
    CustomPainter painter,
    Size size,
  ) async {
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder, Offset.zero & size), size);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        size.width.round(),
        size.height.round(),
      );
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  int red(Uint8List bytes, int x, int y, int width) => bytes[(y * width + x) * 4];

  testWidgets('at 25% the fill shows as the exact mean of its result tiles, '
      'and the commit that installs them changes not one byte on screen',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final images = LayerFrameImageCache(frameStore: BrushFrameStore());
    addTearDown(images.dispose);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);
    final base = columns();
    final dab = fillDab();
    final promoted = promoteFillDab(
      surface: base,
      dab: dab,
      blendMode: BrushBlendMode.color,
      selection: null,
      layerId: layerId,
      frameId: frameId,
    );
    expect(promoted.map((entry) => entry.coord).toSet(), {
      for (var ty = 0; ty < 2; ty += 1)
        for (var tx = 0; tx < 2; tx += 1) TileCoord(x: tx, y: ty),
    });
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = base
      ..blendMode = BrushBlendMode.color;
    addTearDown(overlay.dispose);
    overlay.showResultTiles(promoted);
    expect(overlay.tileImages, hasLength(4));

    // 32×32 canvas px in an 8×8 view: one device pixel per 4×4 block.
    const logicalSize = Size(8, 8);
    await tester.pumpWidget(
      stackAt(
        viewport: CanvasViewport(zoom: 0.25),
        logicalSize: logicalSize,
        live: BitmapSurfacePainter(
          surface: base,
          overlayModel: overlay,
          showTransparentBackground: false,
        ),
        images: images,
        buffers: buffers,
      ),
    );
    await tester.pumpAndSettle();
    await paintBytes(tester, painterOf(tester), logicalSize);
    final shown = await paintBytes(tester, painterOf(tester), logicalSize);
    expect(buffers.lastBufferLevel, 2);
    for (var y = 1; y < 7; y += 1) {
      for (var x = 1; x < 7; x += 1) {
        final filled = x < 4 && y < 4;
        expect(
          red(shown, x, y, 8),
          inInclusiveRange(filled ? 126 : 189, filled ? 130 : 193),
          reason: '($x,$y) ${filled ? 'under the fill: two' : 'untouched: one'} '
              'black column in four — the block mean, not one texel of it',
        );
      }
    }

    // The commit, the way landPromoted does it: hand over the images,
    // install the same tile objects, drop the overlay.
    final placed = <PlacedTile>[];
    for (final entry in promoted) {
      final image = overlay.takeTileImageAt(entry.coord, revision: entry.revision);
      expect(image, isNotNull);
      cache.adoptDecoded(
        entry.tile,
        image!,
      );
      placed.add((coord: entry.coord, tile: entry.tile));
    }
    final committed = base.putMaterializedTiles(placed);
    overlay.reset();
    await tester.pumpWidget(
      stackAt(
        viewport: CanvasViewport(zoom: 0.25),
        logicalSize: logicalSize,
        live: BitmapSurfacePainter(
          surface: committed,
          overlayModel: overlay,
          showTransparentBackground: false,
        ),
        images: images,
        buffers: buffers,
      ),
    );
    await tester.pumpAndSettle();
    await paintBytes(tester, painterOf(tester), logicalSize);
    final afterCommit = await paintBytes(tester, painterOf(tester), logicalSize);
    expect(afterCommit, shown, reason: 'the commit changes nothing on screen');
  });
}
