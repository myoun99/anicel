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
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_resample.dart';
import 'package:anicel/src/ui/canvas/stage_planes_painter.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';

/// 🚨★★★ THE CANVAS EDGE IS CUT ON THE PIXEL GRID (F-67-paper-edge,
/// 2026-09-11).
///
/// F-67's phase snap lands the render translation on whole + φ device
/// pixels above 1:1 (1/20 of a pixel at 110%), so the canvas's left and top
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
/// playback painter's paper, which the blank canvas is — and pins that the
/// two agree byte for byte with the edge fractional. (↩️The painter stood
/// in for the stack during a scrub with a composite of its own, until
/// playback played the canvas's rows.)
///
/// ⚠️The fixture is chosen so the edge really is fractional: the test reads
/// the snapped translation back and refuses to run if it landed whole (a
/// whole edge is cut the same with or without anti-aliasing, and the pins
/// below would pass on nothing).
void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);
  const paper = ProjectBackground.color(0xFF00FF00);
  const zoom = 1.1;
  // Pan chosen so the phase (1/20 at 110%) puts BOTH edges of each axis
  // inside a pixel: left 5.05, right 9.45; top 3.05, bottom 7.45.
  final viewport = CanvasViewport(zoom: zoom, panX: 5, panY: 3);
  const logical = Size(16, 16);

  /// The one tile: ink at the canvas's own corner, so the leftmost and
  /// topmost texel of the artwork sits on the fractional edge — an edge
  /// rounded INWARD would drop it, an anti-aliased one would blend it.
  /// Without [ink], the paper alone.
  BitmapSurfacePainter cornerInkSurface({bool ink = true}) {
    var tile = BitmapTile.blank(size: 4);
    if (ink) {
      tile = writeRgbaColorToBitmapTile(
        tile: tile,
        x: 0,
        y: 0,
        color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
      );
    }
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
  /// Without [live] the stack has no surface to draw and no bake: the walk
  /// lays its paper straight onto the screen.
  Future<CustomPainter> pumpEditingStack(
    WidgetTester tester, {
    bool disableBuffer = false,
    bool ink = true,
    bool live = true,
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
                activeSurfacePainter: live ? cornerInkSurface(ink: ink) : null,
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

  /// Logical == device pixels: the painter snaps in device pixels through
  /// the view's DPR, and the raster below is at logical size. With
  /// [everyEdgeBlended] the painter draws onto [_EveryEdgeBlended].
  Future<Uint8List> rasterize(
    CustomPainter painter, {
    bool everyEdgeBlended = false,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & logical);
    painter.paint(
      everyEdgeBlended ? _EveryEdgeBlended(canvas) : canvas,
      logical,
    );
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

  void expectCutOnTheGrid(Uint8List rgba, String route, {bool ink = true}) {
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
          listEquals(pixel, green) || (ink && listEquals(pixel, red)),
          isTrue,
          reason: '$route ($x,$y) = $pixel: every canvas pixel is exactly '
              'paper or exactly ink — a blend is the anti-aliased edge',
        );
      }
    }
    expect(
      rgbaAt(rgba, columns.first, rows.first),
      ink ? red : green,
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
    'the playback painter cuts its paper on the same pixels — the blank '
    'canvas agrees with the editing stack byte for byte, edge included',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      final editing = await pumpEditingStack(tester, ink: false);
      final editingBytes = (await tester.runAsync(() => rasterize(editing)))!;

      final playback = PlaybackFramePainter(
        canvasSize: canvasSize,
        viewport: viewport,
        devicePixelRatio: 1.0,
        paperBackground: paper,
      );
      final playbackBytes = (await tester.runAsync(
        () => rasterize(playback),
      ))!;
      expectCutOnTheGrid(playbackBytes, 'playback', ink: false);
      expect(
        playbackBytes,
        equals(editingBytes),
        reason: 'the two routes must cut the boundary on the same pixel, '
            'or a cel coming and going switches the edge line on and off',
      );
    },
  );

  group('🚨on an engine that blends every edge it is handed — Impeller, whose '
      'MSAA does not honour isAntiAlias = false', () {
    // The edge is cut by putting it ON the grid, not by asking the engine
    // not to blend it: measured under `--enable-impeller` (2026-10-24), the
    // flag alone left paper at 50% one pixel past the canvas. This runner
    // honours the flag, so here every edge is handed over anti-aliased.
    testWidgets('the editing stack', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      final painter = await pumpEditingStack(tester);
      final bytes = (await tester.runAsync(
        () => rasterize(painter, everyEdgeBlended: true),
      ))!;
      expectCutOnTheGrid(bytes, 'editing, every edge blended');
    });

    testWidgets('the playback painter', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      final playback = PlaybackFramePainter(
        canvasSize: canvasSize,
        viewport: viewport,
        devicePixelRatio: 1.0,
        paperBackground: paper,
      );
      final bytes = (await tester.runAsync(
        () => rasterize(playback, everyEdgeBlended: true),
      ))!;
      expectCutOnTheGrid(bytes, 'playback, every edge blended', ink: false);
    });

    /// Every pixel inside the pixel-centre cut wholly covered, and none
    /// past it touched — whatever [route] lays there.
    void expectWhollyInside(Uint8List rgba, String route) {
      final snapped = renderSnappedViewport(viewport, 1.0);
      final columns = pixelsInside(
        snapped.panX,
        snapped.panX + canvasSize.width * zoom,
      );
      final rows = pixelsInside(
        snapped.panY,
        snapped.panY + canvasSize.height * zoom,
      );
      for (var y = 0; y < logical.height.round(); y += 1) {
        for (var x = 0; x < logical.width.round(); x += 1) {
          final inside =
              x >= columns.first &&
              x <= columns.last &&
              y >= rows.first &&
              y <= rows.last;
          expect(
            alphaAt(rgba, x, y),
            inside ? 255 : 0,
            reason: '$route ($x,$y): wholly covered inside the pixel-centre '
                'cut, untouched past it',
          );
        }
      }
    }

    testWidgets('the canvas\'s absent paper', (tester) async {
      // Its checkerboard covers the pixels the paper covers, so turning
      // the paper off and on moves no edge.
      final planes = StagePlanesPainter(
        pasteboardReach: PasteboardReach.whole,
        paperNone: true,
        canvasSize: canvasSize,
        viewport: viewport,
        devicePixelRatio: 1.0,
      );
      final bytes = (await tester.runAsync(
        () => rasterize(planes, everyEdgeBlended: true),
      ))!;
      expectWhollyInside(bytes, 'absent paper');
    });

    testWidgets('the blank canvas — a paper of the default colour', (
      tester,
    ) async {
      // What the brush host paints where no cel stands.
      final blank = PlaybackFramePainter(
        canvasSize: canvasSize,
        viewport: viewport,
        devicePixelRatio: 1.0,
      );
      final bytes = (await tester.runAsync(
        () => rasterize(blank, everyEdgeBlended: true),
      ))!;
      expectWhollyInside(bytes, 'blank canvas');
    });

    testWidgets('the direct walk laying its paper straight on the screen', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      final walk = await pumpEditingStack(
        tester,
        disableBuffer: true,
        live: false,
      );
      final bytes = (await tester.runAsync(
        () => rasterize(walk, everyEdgeBlended: true),
      ))!;
      expectWhollyInside(bytes, 'walk, no surface');
    });
  });

  test('the grid\'s blit lays the texels drawImageRect lays — only its edge '
      'moves', () async {
    // A part of a 4×3 picture of twelve colours, twice its size, at a
    // phase off the grid.
    final recorder = ui.PictureRecorder();
    final paint = Canvas(recorder);
    for (var y = 0; y < 3; y += 1) {
      for (var x = 0; x < 4; x += 1) {
        paint.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
          Paint()..color = Color.fromARGB(255, 60 * x, 80 * y, 20 + x * y),
        );
      }
    }
    final picture = await recorder.endRecording().toImage(4, 3);
    const source = Rect.fromLTWH(1, 0, 3, 3);
    const destination = Rect.fromLTWH(0, 0, 6, 6);

    Future<Uint8List> drawn(void Function(Canvas canvas) draw) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..translate(1.3, 0.7);
      draw(canvas);
      final image = await recorder.endRecording().toImage(10, 8);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return bytes!.buffer.asUint8List();
    }

    final plain = await drawn(
      (canvas) => canvas.drawImageRect(
        picture,
        source,
        destination,
        Paint()
          ..filterQuality = ui.FilterQuality.none
          ..isAntiAlias = false,
      ),
    );
    final onTheGrid = await drawn(
      (canvas) => drawImageRectOnThePixelGrid(
        canvas,
        picture,
        source,
        destination,
        filterQuality: ui.FilterQuality.none,
        pixelRatio: 1,
      ),
    );
    expect(onTheGrid, equals(plain));
  });

  test('the cut is the pixel centres — on a flip and at a ratio too, and a '
      'turned space keeps its rect', () {
    Rect cutUnder(void Function(Canvas canvas) move, Rect rect, double r) {
      final canvas = Canvas(ui.PictureRecorder());
      move(canvas);
      final cut = cutOnThePixelGrid(canvas, rect, r);
      return cut;
    }

    // Device x = 5.05 + 1.1·x: the left edge 5.05 → 5, the right 9.45 → 9.
    // ⚠️To the canvas's own precision: it keeps its transform in single
    // floats, so 1.1 comes back 2e-7 off — far inside a sample's 1/8.
    final cut = cutUnder(
      (canvas) => canvas
        ..translate(5.05, 3.05)
        ..scale(1.1),
      const Rect.fromLTWH(0, 0, 4, 4),
      1,
    );
    expect(cut.left * 1.1 + 5.05, closeTo(5, 1e-5));
    expect(cut.right * 1.1 + 5.05, closeTo(9, 1e-5));
    expect(cut.top * 1.1 + 3.05, closeTo(3, 1e-5));
    expect(cut.bottom * 1.1 + 3.05, closeTo(7, 1e-5));

    // Past the half the edge goes OUT to the next boundary.
    final out = cutUnder(
      (canvas) => canvas..translate(5.7, 0),
      const Rect.fromLTWH(0, 0, 4, 4),
      1,
    );
    expect(out.left + 5.7, closeTo(6, 1e-5));
    expect(out.right + 5.7, closeTo(10, 1e-5));

    // At a ratio of 2 the grid is half a logical pixel.
    final ratio = cutUnder(
      (canvas) => canvas..translate(0.3, 0),
      const Rect.fromLTWH(0, 0, 4, 4),
      2,
    );
    expect((ratio.left + 0.3) * 2, closeTo(1, 1e-5));
    expect((ratio.right + 0.3) * 2, closeTo(9, 1e-5));

    // Flipped, the canvas's left edge is the screen's right.
    final flipped = cutUnder(
      (canvas) => canvas
        ..translate(10.3, 0)
        ..scale(-1, 1),
      const Rect.fromLTWH(0, 0, 4, 4),
      1,
    );
    expect(10.3 - flipped.left, closeTo(10, 1e-5));
    expect(10.3 - flipped.right, closeTo(6, 1e-5));

    const square = Rect.fromLTWH(0.3, 0.3, 4, 4);
    expect(cutUnder((canvas) => canvas.rotate(0.5), square, 1), square);
  });

  testWidgets('a rotated view keeps its anti-aliased edge', (tester) async {
    // The law's other half: a rotated edge is a diagonal, and a diagonal
    // cut on pixel centres is a staircase. Blended pixels along the edge
    // are the anti-aliasing this view must keep.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final playback = PlaybackFramePainter(
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

/// [inner], with every edge handed over anti-aliased: each paint's
/// `isAntiAlias` and each clip's `doAntiAlias` forced on — an engine that
/// blends what it is told not to, as Impeller's MSAA does. What this
/// canvas does not forward fails loudly rather than drawing nothing.
class _EveryEdgeBlended implements ui.Canvas {
  _EveryEdgeBlended(this._inner);

  final ui.Canvas _inner;

  ui.Paint _blended(ui.Paint paint) => paint..isAntiAlias = true;

  @override
  void save() => _inner.save();

  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) =>
      _inner.saveLayer(bounds, _blended(paint));

  @override
  void restore() => _inner.restore();

  @override
  void restoreToCount(int count) => _inner.restoreToCount(count);

  @override
  int getSaveCount() => _inner.getSaveCount();

  @override
  void translate(double dx, double dy) => _inner.translate(dx, dy);

  @override
  void scale(double sx, [double? sy]) => _inner.scale(sx, sy);

  @override
  void rotate(double radians) => _inner.rotate(radians);

  @override
  void transform(Float64List matrix4) => _inner.transform(matrix4);

  @override
  Float64List getTransform() => _inner.getTransform();

  @override
  void clipRect(
    ui.Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) => _inner.clipRect(rect, clipOp: clipOp);

  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) =>
      _inner.clipPath(path);

  @override
  ui.Rect getLocalClipBounds() => _inner.getLocalClipBounds();

  @override
  ui.Rect getDestinationClipBounds() => _inner.getDestinationClipBounds();

  @override
  void drawPaint(ui.Paint paint) => _inner.drawPaint(_blended(paint));

  @override
  void drawRect(ui.Rect rect, ui.Paint paint) =>
      _inner.drawRect(rect, _blended(paint));

  @override
  void drawImageRect(
    ui.Image image,
    ui.Rect src,
    ui.Rect dst,
    ui.Paint paint,
  ) => _inner.drawImageRect(image, src, dst, _blended(paint));

  @override
  void drawPicture(ui.Picture picture) => _inner.drawPicture(picture);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not forwarded');
}
