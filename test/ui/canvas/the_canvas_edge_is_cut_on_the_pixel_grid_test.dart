import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';

/// 🚨★★★ THE CANVAS EDGE IS CUT ON THE PIXEL GRID (F-67-paper-edge,
/// 2026-09-11).
///
/// F-67's phase snap lands the render translation on whole + φ device
/// pixels above 1:1 (a quarter pixel at 110%), so the canvas's left and top
/// edges sit INSIDE a device pixel. Every boundary within the artwork is
/// decided per pixel by its centre — nearest sampling — but the outer edge
/// of the buffer blit and of the paper rect was anti-aliased, which painted
/// a blended line one pixel wide along the canvas (75% paper over the
/// backdrop). 유저 09-11: 「가장자리 흐려지는 거만 바뀌는 거 맞지? … 고치자」.
///
/// The law ([displayEdgeAntiAliased]): on an axis-aligned view under
/// nearest sampling the edge is one more texel boundary — no anti-aliasing,
/// every device pixel is wholly canvas or wholly not, and the leftmost
/// texel keeps its column. This file pins it on the two routes that draw
/// the boundary on screen — the editing stack's buffer blit and the
/// playback painter that stands in for it during a scrub — and pins that
/// the two agree byte for byte with the edge fractional.
///
/// ⚠️The fixture is chosen so the edge really is fractional: the test reads
/// the snapped translation back and refuses to run if it landed whole (a
/// whole edge is cut the same with or without anti-aliasing, and the pins
/// below would pass on nothing).
void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);
  const paper = ProjectBackground.color(0xFF00FF00);
  const zoom = 1.1;
  // Pan chosen so the phase (1/4 at 110%) puts BOTH edges of each axis
  // inside a pixel: left 5.25, right 9.65; top 3.25, bottom 7.65.
  final viewport = CanvasViewport(zoom: zoom, panX: 5, panY: 3);
  const logical = Size(16, 16);

  /// The one tile: ink at the canvas's own corner, so the leftmost and
  /// topmost texel of the artwork sits on the fractional edge — an edge
  /// rounded INWARD would drop it, an anti-aliased one would blend it.
  BitmapSurfacePainter cornerInkSurface() {
    var tile = BitmapTile.blank(size: 4);
    tile = writeRgbaColorToBitmapTile(
      tile: tile,
      x: 0,
      y: 0,
      color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
    );
    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 4,
        tiles: {TileCoord(x: 0, y: 0): tile},
      ),
      showTransparentBackground: false,
    );
  }

  /// [disableBuffer] takes the DIRECT WALK instead of the buffer blit: the
  /// paper rect and the tiles drawn straight under the viewport transform,
  /// which is the route a frame falls to when the buffer is refused.
  Future<CustomPainter> pumpEditingStack(
    WidgetTester tester, {
    bool disableBuffer = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        // A distinct key per route, so the second pump builds a FRESH state
        // rather than reusing the first one's warm bake.
        key: ValueKey<bool>(disableBuffer),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: logical.width,
              height: logical.height,
              child: CanvasLayerStackView(
                nodes: const [
                  CompositeLeaf<CanvasStackRow>(
                    CanvasActiveLayerRow(opacity: 1),
                  ),
                ],
                imageCache: LayerFrameImageCache(
                  frameStore: BrushFrameStore(),
                ),
                canvasSize: canvasSize,
                viewport: viewport,
                activeSurfacePainter: cornerInkSurface(),
                paintPaper: true,
                paperBackground: paper,
                debugDisableSingleBuffer: disableBuffer,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final painted = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .toList();
    expect(painted, isNotEmpty);
    return painted.first.painter!;
  }

  /// The canvas-resolution composite the playback route serves: the same
  /// four-by-four with ink at the corner.
  Future<ui.Image> compositeImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint()
        ..color = const Color(0xFFFF0000)
        ..isAntiAlias = false,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(canvasSize.width, canvasSize.height);
    } finally {
      picture.dispose();
    }
  }

  /// Logical == device pixels: the painter snaps in device pixels through
  /// the view's DPR, and the raster below is at logical size.
  Future<Uint8List> rasterize(CustomPainter painter) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & logical);
    painter.paint(canvas, logical);
    final image = await recorder.endRecording().toImage(
      logical.width.round(),
      logical.height.round(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return bytes!.buffer.asUint8List();
  }

  /// The device pixels whose centres fall inside `[edge, farEdge)`.
  ({int first, int last}) pixelsInside(double edge, double farEdge) =>
      (first: (edge - 0.5).ceil(), last: (farEdge - 0.5).ceil() - 1);

  int alphaAt(Uint8List rgba, int x, int y) =>
      rgba[(y * logical.width.round() + x) * 4 + 3];

  List<int> rgbaAt(Uint8List rgba, int x, int y) {
    final i = (y * logical.width.round() + x) * 4;
    return [rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]];
  }

  const transparent = [0, 0, 0, 0];
  const green = [0, 255, 0, 255];
  const red = [255, 0, 0, 255];

  void expectCutOnTheGrid(Uint8List rgba, String route) {
    final snapped = renderSnappedViewport(viewport, 1.0);
    final left = snapped.panX;
    final top = snapped.panY;
    final right = left + canvasSize.width * zoom;
    final bottom = top + canvasSize.height * zoom;
    // 계측기를 먼저 의심하라: a whole edge would pass with the bug in place.
    for (final edge in [left, right, top, bottom]) {
      expect(
        edge - edge.floorToDouble(),
        isNot(0),
        reason: 'edge $edge is whole — the fixture no longer exercises the '
            'fractional cut',
      );
    }

    final columns = pixelsInside(left, right);
    final rows = pixelsInside(top, bottom);
    for (var y = 0; y < logical.height.round(); y += 1) {
      for (var x = 0; x < logical.width.round(); x += 1) {
        final inside =
            x >= columns.first &&
            x <= columns.last &&
            y >= rows.first &&
            y <= rows.last;
        final pixel = rgbaAt(rgba, x, y);
        if (!inside) {
          expect(
            pixel,
            transparent,
            reason: '$route ($x,$y) is outside the canvas — the edge must '
                'not spill a blended pixel past the pixel-centre cut',
          );
          continue;
        }
        expect(
          alphaAt(rgba, x, y),
          255,
          reason: '$route ($x,$y) is inside the canvas — the edge pixel '
              'must be wholly canvas, not a 75% blend',
        );
        expect(
          listEquals(pixel, green) || listEquals(pixel, red),
          isTrue,
          reason: '$route ($x,$y) = $pixel: every canvas pixel is exactly '
              'paper or exactly ink — a blend is the anti-aliased edge',
        );
      }
    }
    expect(
      rgbaAt(rgba, columns.first, rows.first),
      red,
      reason: '$route: the leftmost, topmost texel keeps its column and '
          'row — an edge rounded inward would have dropped it',
    );
  }

  testWidgets(
    'the editing stack cuts the canvas edge on the pixel grid at 110%',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      final painter = await pumpEditingStack(tester);
      final bytes = (await tester.runAsync(() => rasterize(painter)))!;
      expectCutOnTheGrid(bytes, 'editing');
    },
  );

  testWidgets(
    'the direct walk cuts it on the same pixels — a route flip cannot move '
    'the edge either',
    (tester) async {
      // The paper rect drawn straight on screen (the walk) and the buffer's
      // blit (the production route above 1:1) share the law, so the two
      // routes agree byte for byte INCLUDING the boundary — the probe's
      // route-flip oracle, with the edges back in.
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      final buffered = await pumpEditingStack(tester);
      final bufferedBytes = (await tester.runAsync(
        () => rasterize(buffered),
      ))!;
      final walk = await pumpEditingStack(tester, disableBuffer: true);
      final walkBytes = (await tester.runAsync(() => rasterize(walk)))!;
      expectCutOnTheGrid(walkBytes, 'walk');
      expect(walkBytes, equals(bufferedBytes));
    },
  );

  testWidgets(
    'the playback painter cuts it on the same pixels — the scrub stand-in '
    'agrees with the editing stack byte for byte, edge included',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      final editing = await pumpEditingStack(tester);
      final editingBytes = (await tester.runAsync(() => rasterize(editing)))!;

      final composite = (await tester.runAsync(compositeImage))!;
      addTearDown(composite.dispose);
      final playback = PlaybackFramePainter(
        image: composite,
        canvasSize: canvasSize,
        viewport: viewport,
        devicePixelRatio: 1.0,
        paperBackground: paper,
      );
      final playbackBytes = (await tester.runAsync(
        () => rasterize(playback),
      ))!;
      expectCutOnTheGrid(playbackBytes, 'playback');
      expect(
        playbackBytes,
        equals(editingBytes),
        reason: 'the two routes must cut the boundary on the same pixel, '
            'or a scrub switches the edge line on and off',
      );
    },
  );

  testWidgets('a rotated view keeps its anti-aliased edge', (tester) async {
    // The law's other half: a rotated edge is a diagonal, and a diagonal
    // cut on pixel centres is a staircase. Blended pixels along the edge
    // are the anti-aliasing this view must keep.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final composite = (await tester.runAsync(compositeImage))!;
    addTearDown(composite.dispose);
    final playback = PlaybackFramePainter(
      image: composite,
      canvasSize: canvasSize,
      viewport: CanvasViewport(
        zoom: zoom,
        panX: 6,
        panY: 5,
        rotationDegrees: 30,
      ),
      devicePixelRatio: 1.0,
      paperBackground: paper,
    );
    final bytes = (await tester.runAsync(() => rasterize(playback)))!;
    var blended = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      if (bytes[i + 3] > 0 && bytes[i + 3] < 255) {
        blended += 1;
      }
    }
    expect(
      blended,
      greaterThan(0),
      reason: 'a rotated edge with no partial pixels is a staircase — the '
          'law leaked past the axis-aligned case',
    );
  });
}
