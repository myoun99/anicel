import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/brush/cut_piece_preview.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨★★★WHAT THE ACTIVE LAYER DRAWS ON THE PASTEBOARD SHOWS WHILE IT IS
/// DRAWN, NOT ONCE A COMMIT PUTS TILES THERE (F-85, 2026-09-11).
///
/// 유저: 「변형시 캔버스 밖, 페이스트보드에서 그림이 사라짐. 추가로 펜 그리는
/// 도중, 페이스트보드의 일부?까지 그려지는데 정확히 페이스트보드 끝까지 그림
/// 그려지지않음. 그 상태에서 손 떼면 정상적으로 페이스트보드에 그림 남아있음」.
///
/// The editing canvas composites every row into ONE buffer sized by what the
/// rows cover, and it asked the ACTIVE row only about its committed surface.
/// Everything the active slot draws on top of that surface — the stroke in
/// flight, a fill's stamp, the stamp ghost, the selection's float — was cut
/// at the edge of the ink that had already landed.
///
/// Each case draws ONE thing twice: inside the page (the control — the rig
/// draws it at all) and then on the pasteboard beside the page, where the
/// committed layer holds nothing. The first case is the state the user
/// called normal: the same red as a COMMITTED tile there.
void main() {
  // A 32×32 page on 16px tiles, seen 1:1 with the page's origin 32px in, so
  // screen x 0..32 is the pasteboard column left of the page.
  const canvasSize = CanvasSize(width: 32, height: 32);
  const tileSize = 16;
  const view = Size(96, 96);
  const pageSpot = Rect.fromLTWH(8, 8, 16, 16);
  const pageProbe = Offset(48, 48);
  // Tile (-1, 1) exactly: canvas (-16..0, 16..32), screen (16..32, 48..64).
  const pasteboardSpot = Rect.fromLTWH(-16, 16, 16, 16);
  const pasteboardProbe = Offset(24, 56);

  ui.Image redSquare() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 16, 16),
      Paint()..color = const Color(0xFFFF0000),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(16, 16);
    picture.dispose();
    return image;
  }

  Uint8List redRgba() {
    final rgba = Uint8List(tileSize * tileSize * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = 255;
      rgba[i + 3] = 255;
    }
    return rgba;
  }

  BitmapSurface surfaceWith(Map<TileCoord, BitmapTile> tiles) =>
      BitmapSurface(canvasSize: canvasSize, tileSize: tileSize, tiles: tiles);

  Future<void> decodeAll(
    WidgetTester tester,
    BitmapTileImageCache cache,
    BitmapSurface surface,
  ) async {
    await tester.runAsync(() async {
      for (final entry in surface.tiles.entries) {
        cache.ensureDecoded((coord: entry.key, tile: entry.value));
      }
      while (surface.tiles.values.any((tile) => cache.imageFor(tile) == null)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
  }

  Future<CustomPainter> pumpStack(
    WidgetTester tester, {
    required BitmapSurfacePainter painter,
    SelectionFloatOverlay? float,
  }) async {
    final cache = DisplayBufferCache();
    addTearDown(cache.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: view.width,
              height: view.height,
              child: CanvasLayerStackView(
                nodes: const [
                  CompositeLeaf<CanvasStackRow>(
                    CanvasActiveLayerRow(opacity: 1),
                  ),
                ],
                imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
                canvasSize: canvasSize,
                viewport: CanvasViewport(panX: 32, panY: 32),
                activeSurfacePainter: painter,
                floatOverlay: float,
                paintPaper: true,
                paperBackground: ProjectBackground.defaultBackground,
                debugBufferCache: cache,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .first
        .painter!;
  }

  /// Whether [at] reads red with [stack] painted over a grey backdrop —
  /// the pasteboard itself is transparent in the stack, so grey is "nothing
  /// drawn there" and white is paper.
  Future<bool> redAt(
    WidgetTester tester,
    CustomPainter stack,
    Offset at,
  ) async {
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Offset.zero & view,
        Paint()..color = const Color(0xFF808080),
      );
      stack.paint(canvas, view);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        view.width.round(),
        view.height.round(),
      );
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    final i = (at.dy.round() * view.width.round() + at.dx.round()) * 4;
    return bytes![i] >= 200 && bytes[i + 1] <= 60 && bytes[i + 2] <= 60;
  }

  /// Draws with [draw] inside the page, then on the pasteboard, and reads
  /// both.
  Future<void> expectShownOnThePasteboard(
    WidgetTester tester, {
    required String what,
    required CustomPainter stack,
    required Future<void> Function(Rect where) draw,
  }) async {
    await draw(pageSpot);
    expect(
      await redAt(tester, stack, pageProbe),
      isTrue,
      reason: 'control: $what inside the page reaches the screen — the rig '
          'draws it at all',
    );
    await draw(pasteboardSpot);
    expect(
      await redAt(tester, stack, pasteboardProbe),
      isTrue,
      reason: '$what on the pasteboard, where the committed layer holds '
          'nothing, has to show while it is drawn — not only once a commit '
          'puts tiles there',
    );
  }

  testWidgets('control: ink already COMMITTED on the pasteboard shows — the '
      'state after pen-up', (tester) async {
    final tiles = BitmapTileImageCache();
    final surface = surfaceWith({
      TileCoord(x: -1, y: 1): BitmapTile(
        size: tileSize,
        pixels: redRgba(),
      ),
    });
    await decodeAll(tester, tiles, surface);
    final stack = await pumpStack(
      tester,
      painter: BitmapSurfacePainter(
        surface: surface,
        tileImageCache: tiles,
        showTransparentBackground: false,
      ),
    );
    expect(
      await redAt(tester, stack, pasteboardProbe),
      isTrue,
      reason: 'the view shows that pasteboard spot, and a committed tile '
          'there is part of what the layer covers',
    );
  });

  testWidgets('🚨the stroke in flight shows on the pasteboard', (tester) async {
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize);
    addTearDown(overlay.dispose);
    final rasterizer = BrushLiveStrokeRasterizer(
      canvasSize: canvasSize,
      tileSize: tileSize,
    );
    final stack = await pumpStack(
      tester,
      painter: BitmapSurfacePainter(
        surface: surfaceWith(const {}),
        overlayModel: overlay,
        tileImageCache: BitmapTileImageCache(),
        showTransparentBackground: false,
      ),
    );
    final dabs = <BrushDab>[];
    await expectShownOnThePasteboard(
      tester,
      what: 'the stroke in flight',
      stack: stack,
      draw: (where) async {
        dabs.add(
          BrushDab(
            center: CanvasPoint(x: where.center.dx, y: where.center.dy),
            color: 0xFFFF0000,
            size: 14,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.square,
            pressure: 1,
            sequence: dabs.length,
          ),
        );
        await tester.runAsync(() async {
          final region = rasterizer.blendFrom(dabs, from: dabs.length - 1);
          overlay.updateRegion(source: rasterizer, region: region!);
          await overlay.waitForPendingDecodes();
        });
      },
    );
  });

  testWidgets('🚨a fill\'s stamp shows on the pasteboard before it commits', (
    tester,
  ) async {
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize);
    addTearDown(overlay.dispose);
    final stack = await pumpStack(
      tester,
      painter: BitmapSurfacePainter(
        surface: surfaceWith(const {}),
        overlayModel: overlay,
        tileImageCache: BitmapTileImageCache(),
        showTransparentBackground: false,
      ),
    );
    await expectShownOnThePasteboard(
      tester,
      what: 'a fill\'s stamp',
      stack: stack,
      // The overlay owns the stamp from here: it retires the one it
      // replaces and the last one with itself.
      draw: (where) async => overlay.setStampOverlay(redSquare(), where.topLeft),
    );
  });

  testWidgets('🚨the stamp ghost shows on the pasteboard', (tester) async {
    final image = redSquare();
    addTearDown(image.dispose);
    final ghost = ValueNotifier<CutStampPreview?>(null);
    addTearDown(ghost.dispose);
    final piece = CutPiece(
      image: BrushStampImage(
        id: 'ghost',
        width: tileSize,
        height: tileSize,
        rgba: redRgba(),
      ),
      originLeft: 0,
      originTop: 0,
    );
    final stack = await pumpStack(
      tester,
      painter: BitmapSurfacePainter(
        surface: surfaceWith(const {}),
        stampPreview: ghost,
        tileImageCache: BitmapTileImageCache(),
        showTransparentBackground: false,
      ),
    );
    await expectShownOnThePasteboard(
      tester,
      what: 'the stamp ghost',
      stack: stack,
      draw: (where) async => ghost.value = CutStampPreview(
        piece: piece,
        image: image,
        canvasRect: where,
        opacity: 1,
        blendMode: BrushBlendMode.color,
      ),
    );
  });

  testWidgets('🚨a transform\'s float shows on the pasteboard', (tester) async {
    final image = redSquare();
    addTearDown(image.dispose);
    final float = SelectionFloatOverlay(null);
    addTearDown(float.dispose);
    final stack = await pumpStack(
      tester,
      painter: BitmapSurfacePainter(
        surface: surfaceWith(const {}),
        tileImageCache: BitmapTileImageCache(),
        showTransparentBackground: false,
      ),
      float: float,
    );
    await expectShownOnThePasteboard(
      tester,
      what: 'a transform\'s resampled float',
      stack: stack,
      draw: (where) async => float.value = SelectionFloatPaint(
        image: image,
        imageLeft: where.left,
        imageTop: where.top,
        clip: canvasSize.pasteboardRect,
      ),
    );
  });

  testWidgets('🚨a move\'s float shows on the pasteboard', (tester) async {
    final floatTiles = BitmapTileImageCache();
    final lifted = surfaceWith({
      TileCoord(x: 0, y: 0): BitmapTile(
        size: tileSize,
        pixels: redRgba(),
      ),
    });
    await decodeAll(tester, floatTiles, lifted);
    final float = SelectionFloatOverlay(null);
    addTearDown(float.dispose);
    final stack = await pumpStack(
      tester,
      painter: BitmapSurfacePainter(
        surface: surfaceWith(const {}),
        tileImageCache: BitmapTileImageCache(),
        showTransparentBackground: false,
      ),
      float: float,
    );
    final liftedPainter = BitmapSurfacePainter(
      surface: lifted,
      tileImageCache: floatTiles,
      showTransparentBackground: false,
    );
    await expectShownOnThePasteboard(
      tester,
      what: 'a move\'s float',
      stack: stack,
      draw: (where) async => float.value = SelectionFloatPaint(
        surface: liftedPainter,
        surfaceOffset: CanvasPoint(x: where.left, y: where.top),
        clip: canvasSize.pasteboardRect,
      ),
    );
  });
}
