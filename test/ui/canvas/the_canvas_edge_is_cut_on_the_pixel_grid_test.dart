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
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_resample.dart';
import 'package:anicel/src/ui/canvas/landing_preview.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/canvas/stage_planes_painter.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_float.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';
import '../../helpers/the_frame_as_it_stands.dart';

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
  // A blend over its backdrop is composed by its shader.
  setUpAll(LayerBlendShader.load);
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

  /// Ink over two whole coordinates of half the canvas a side, the first
  /// and the last, so every coordinate's edge inside the canvas — 7.25 and
  /// 5.25 at this view — falls inside a pixel between ink and paper, as a
  /// cel's grid does on screen at any zoom but a whole one.
  BitmapSurfacePainter seamedInkSurface() {
    BitmapTile inked() {
      var tile = BitmapTile.blank(size: 2);
      for (var y = 0; y < 2; y += 1) {
        for (var x = 0; x < 2; x += 1) {
          tile = writeRgbaColorToBitmapTile(
            tile: tile,
            x: x,
            y: y,
            color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
          );
        }
      }
      return tile;
    }

    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 2,
        tiles: {
          TileCoord(x: 0, y: 0): inked(),
          TileCoord(x: 1, y: 1): inked(),
        },
      ),
      showTransparentBackground: false,
    );
  }

  /// Ink across the pasteboard's wall a quarter of the canvas out — whole
  /// coordinates a pixel past each wall at 1 and 5, so the wall cuts each
  /// inside it — as a picture the pasteboard holds past the page.
  BitmapSurfacePainter wallInkSurface() {
    BitmapTile inked() {
      var tile = BitmapTile.blank(size: 2);
      for (var y = 0; y < 2; y += 1) {
        for (var x = 0; x < 2; x += 1) {
          tile = writeRgbaColorToBitmapTile(
            tile: tile,
            x: x,
            y: y,
            color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
          );
        }
      }
      return tile;
    }

    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 2,
        pasteboardReach: PasteboardReach.quarter,
        tiles: {
          TileCoord(x: -1, y: 0): inked(),
          TileCoord(x: 2, y: 1): inked(),
        },
      ),
      showTransparentBackground: false,
    );
  }

  /// [disableBuffer] takes the DIRECT WALK instead of the buffer blit: the
  /// paper rect and the tiles drawn straight under the viewport transform,
  /// which is the route a frame falls to when the buffer is refused.
  /// Without [live] the stack has no surface to draw: the walk lays its
  /// paper straight onto the screen. [surface] draws in place of the corner
  /// ink.
  Future<CustomPainter> pumpEditingStack(
    WidgetTester tester, {
    bool disableBuffer = false,
    bool ink = true,
    bool live = true,
    BitmapSurfacePainter? surface,
    List<CompositeNode<CanvasStackRow>> nodes = const [
      CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1)),
    ],
    CanvasViewport? view,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        // A distinct key per route, so the second pump builds a FRESH state.
        key: ValueKey<bool>(disableBuffer),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: logical.width,
              height: logical.height,
              child: TheFrameAsItStands(
                nodes: nodes,
                imageCache: LayerFrameImageCache(
                  frameStore: BrushFrameStore(),
                ),
                canvasSize: canvasSize,
                viewport: view ?? viewport,
                activeSurfacePainter: live
                    ? surface ?? cornerInkSurface(ink: ink)
                    : null,
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
            of: find.byType(TheFrameAsItStands),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .toList();
    expect(painted, isNotEmpty);
    return painted.first.painter!;
  }

  /// Logical == device pixels: the painter snaps in device pixels through
  /// the view's DPR, and the raster below is at logical size — times
  /// [ratio], the view's, where it is not 1: the painter records in logical
  /// pixels and the recording is laid on the device's, as the engine's root
  /// does, so the canvas's own transform never holds the ratio. With
  /// [everyEdgeBlended] the painter draws onto [_EveryEdgeBlended].
  Future<Uint8List> rasterize(
    CustomPainter painter, {
    bool everyEdgeBlended = false,
    double ratio = 1,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & logical);
    painter.paint(
      everyEdgeBlended ? _EveryEdgeBlended(canvas) : canvas,
      logical,
    );
    final device = ui.PictureRecorder();
    Canvas(device, Offset.zero & logical * ratio)
      ..scale(ratio)
      ..drawPicture(recorder.endRecording());
    final image = await device.endRecording().toImage(
      (logical.width * ratio).round(),
      (logical.height * ratio).round(),
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

    testWidgets('the direct walk laying the coordinates straight on the '
        'screen — every edge of each, inside the canvas too', (tester) async {
      // the-walk-draws-off-the-grid-on-impeller (10-28): each coordinate is
      // its own draw, and drawn where it fell its edge was the one left
      // blended — 🔬at 150% under `--enable-impeller` a line of ink along
      // the canvas's edge 64 grey for black, apart from the buffer's.
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      final buffered = await pumpEditingStack(
        tester,
        surface: seamedInkSurface(),
      );
      final bufferedBytes = (await tester.runAsync(
        () => rasterize(buffered),
      ))!;
      final walk = await pumpEditingStack(
        tester,
        disableBuffer: true,
        surface: seamedInkSurface(),
      );
      final bytes = (await tester.runAsync(
        () => rasterize(walk, everyEdgeBlended: true),
      ))!;
      expectCutOnTheGrid(bytes, 'walk, every edge blended');
      expect(
        bytes,
        equals(bufferedBytes),
        reason: 'the walk lays each texel where the buffer does — a route '
            'flip moves no coordinate\'s edge',
      );
    });

    testWidgets('…on the DEVICE\'s grid, at a ratio of 2', (tester) async {
      // Cut on the logical grid, each edge would land a device pixel off
      // the buffer's wherever it fell in a logical pixel's second half.
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      final buffered = await pumpEditingStack(
        tester,
        surface: seamedInkSurface(),
      );
      final bufferedBytes = (await tester.runAsync(
        () => rasterize(buffered, ratio: 2),
      ))!;
      final walk = await pumpEditingStack(
        tester,
        disableBuffer: true,
        surface: seamedInkSurface(),
      );
      final bytes = (await tester.runAsync(
        () => rasterize(walk, everyEdgeBlended: true, ratio: 2),
      ))!;
      for (var at = 0; at < bytes.length; at += 4) {
        final pixel = bytes.sublist(at, at + 4);
        expect(
          [green, red, transparent].any((shown) => listEquals(pixel, shown)),
          isTrue,
          reason: 'device pixel ${at ~/ 4} = $pixel: wholly paper, ink or '
              'nothing — a blend is an edge left off the grid',
        );
      }
      expect(
        bytes,
        equals(bufferedBytes),
        reason: 'the walk cuts each edge on the pixel the buffer does',
      );
    });

    // the-walk-family-cuts-the-rest-on-the-grid (10-30): a node the walk
    // draws as a picture of its own lay on a grid counted from the canvas's
    // origin, which the view's phase puts inside a device pixel above 100%
    // — so its blit resampled each texel once more and blended its edge.
    // 🔬A folder at half strength: 18 of 256 pixels apart from the buffer at
    // 125% (a seam of the ink a pixel off, 16/255 of it past the page), 12 at
    // 150%; at a ratio of 2, 10 · 5 · 12 of 1,024 at 125 · 137 · 150%.
    const leaf = CompositeLeaf<CanvasStackRow>(
      CanvasActiveLayerRow(opacity: 1),
    );
    final pictures = <String, List<CompositeNode<CanvasStackRow>>>{
      'a folder': const [
        CompositeGroup<CanvasStackRow>(
          children: [leaf],
          opacity: 0.5,
          blendMode: LayerBlendMode.normal,
        ),
      ],
      'a blend over its backdrop': const [
        CompositeBackdropBlend<CanvasStackRow>(
          backdrop: [],
          source: leaf,
          blendMode: LayerBlendMode.multiply,
        ),
      ],
      'a clip': const [
        CompositeClip<CanvasStackRow>(
          base: leaf,
          scope: [],
          opacity: 0.5,
          blendMode: LayerBlendMode.normal,
        ),
      ],
      'an adjustment': [
        CompositeAdjustment<CanvasStackRow>(
          children: const [leaf],
          effects: [
            ResolvedLayerEffect(
              kind: EffectKind.brightnessContrast,
              values: [20, 0],
            ),
          ],
          mix: 0.5,
        ),
      ],
    };
    // At a fraction of a pixel each way: above 100% on the logical grid, at
    // a ratio of 2 on the device's.
    const offTheGrid = [
      (1.0, 1.25, false),
      (1.0, 1.37, false),
      (1.0, 1.5, false),
      (2.0, 0.625, false),
      (2.0, 0.685, false),
      (2.0, 0.75, false),
      // Turned over, the canvas's space runs the other way from its
      // origin: the grid is counted back from it.
      (1.0, 1.25, true),
      (2.0, 0.75, true),
    ];
    String atTheView(double ratio, double zoom, {bool turned = false}) =>
        '${(zoom * ratio * 100).round()}% at a ratio of $ratio'
        '${turned ? ', turned over' : ''}';
    CanvasViewport turnedOrNot(double zoom, bool turned) => CanvasViewport(
      zoom: zoom,
      panX: turned ? 10 : 5,
      panY: 3,
      flipHorizontal: turned,
    );

    /// What the walk draws of [surface] under [nodes] at [view] on a screen
    /// of [ratio], every edge blended, laid byte for byte where the buffer
    /// lays it.
    Future<void> expectTheWalkWhereTheBufferIs(
      WidgetTester tester, {
      required BitmapSurfacePainter Function() surface,
      required List<CompositeNode<CanvasStackRow>> nodes,
      required CanvasViewport view,
      required double ratio,
    }) async {
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.resetDevicePixelRatio);
      final buffered = await pumpEditingStack(
        tester,
        surface: surface(),
        nodes: nodes,
        view: view,
      );
      final bufferedBytes = (await tester.runAsync(
        () => rasterize(buffered, ratio: ratio),
      ))!;
      final walk = await pumpEditingStack(
        tester,
        disableBuffer: true,
        surface: surface(),
        nodes: nodes,
        view: view,
      );
      final bytes = (await tester.runAsync(
        () => rasterize(walk, everyEdgeBlended: true, ratio: ratio),
      ))!;
      expect(
        bytes,
        equals(bufferedBytes),
        reason: 'the walk lands each texel where the buffer does',
      );
    }

    for (final MapEntry(key: picture, value: nodes) in pictures.entries) {
      for (final (ratio, zoom, turned) in offTheGrid) {
        testWidgets('$picture the walk draws lies on the device\'s pixels — '
            '${atTheView(ratio, zoom, turned: turned)}', (tester) async {
          await expectTheWalkWhereTheBufferIs(
            tester,
            surface: seamedInkSurface,
            nodes: nodes,
            view: turnedOrNot(zoom, turned),
            ratio: ratio,
          );
        });
      }
    }

    // ②The pasteboard's wall cuts a picture laid past it where the buffer's
    // raster of the cel ends — ↩️the walk clipped it at a fraction of a
    // pixel: 🔬5 · 6 of 256 pixels apart from the buffer at 125 · 150%, 5 of
    // 1,024 at a ratio of 2 at 125% (10-30).
    for (final (ratio, zoom, turned) in offTheGrid) {
      testWidgets('the pasteboard\'s wall the walk cuts a picture at lies on '
          'the device\'s pixels — ${atTheView(ratio, zoom, turned: turned)}', (
        tester,
      ) async {
        await expectTheWalkWhereTheBufferIs(
          tester,
          surface: wallInkSurface,
          nodes: const [leaf],
          view: turnedOrNot(zoom, turned),
          ratio: ratio,
        );
      });
    }

    // ③Where the frame ends — the page and every row's content — the walk
    // cuts what spreads past it, as the buffer's raster ends there.
    // ↩️It drew it whole: 🔬a blur at the page's corner 16 of 256 pixels
    // apart from the buffer at 100% (10-30).
    for (final (ratio, zoom) in [(1.0, 1.0), (2.0, 0.5)]) {
      testWidgets('what spreads past where the frame ends the walk cuts '
          'there — ${atTheView(ratio, zoom)}', (tester) async {
        await expectTheWalkWhereTheBufferIs(
          tester,
          surface: cornerInkSurface,
          nodes: [
            CompositeLeaf<CanvasStackRow>(
              CanvasActiveLayerRow(
                opacity: 1,
                effects: [
                  ResolvedLayerEffect(kind: EffectKind.blur, values: [3, 0]),
                ],
              ),
            ),
          ],
          view: CanvasViewport(zoom: zoom, panX: 5, panY: 3),
          ratio: ratio,
        );
      });
    }

    /// [surface] as a sheet's window lays a cel — by its painter alone, at
    /// [view] on a screen of [ratio], [landing] over it — every edge
    /// blended.
    Future<Uint8List> paintedAlone(
      BitmapSurface surface, {
      required CanvasViewport view,
      required double ratio,
      LandingPreview? landing,
    }) => rasterize(
      BitmapSurfacePainter(
        surface: surface,
        viewport: view,
        devicePixelRatio: ratio,
        landingPreview: landing == null ? null : ValueNotifier(landing),
        showTransparentBackground: false,
      ),
      everyEdgeBlended: true,
      ratio: ratio,
    );

    BitmapTile inkedColumn(int x) {
      var tile = BitmapTile.blank(size: 2);
      for (var y = 0; y < 2; y += 1) {
        tile = writeRgbaColorToBitmapTile(
          tile: tile,
          x: x,
          y: y,
          color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
        );
      }
      return tile;
    }

    Future<ui.Image> redPicture(int width, int height) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..color = const Color(0xFFFF0000),
      );
      return recorder.endRecording().toImage(width, height);
    }

    // ②The painter alone cuts its cel at the wall where the walk does: the
    // coordinates [wallInkSurface] holds past it, against the ones inside
    // it with the wall far off.
    for (final (ratio, zoom, turned) in offTheGrid) {
      test('the pasteboard\'s wall a cel laid alone is cut at lies on the '
          'device\'s pixels — ${atTheView(ratio, zoom, turned: turned)}',
          () async {
        final view = turnedOrNot(zoom, turned);
        final inside = BitmapSurface(
          canvasSize: canvasSize,
          tileSize: 2,
          pasteboardReach: PasteboardReach.whole,
          tiles: {
            TileCoord(x: -1, y: 0): inkedColumn(1),
            TileCoord(x: 2, y: 1): inkedColumn(0),
          },
        );
        expect(
          await paintedAlone(
            wallInkSurface().surface,
            view: view,
            ratio: ratio,
          ),
          equals(await paintedAlone(inside, view: view, ratio: ratio)),
          reason: 'the wall cuts on the pixel each coordinate\'s own edge '
              'is cut on',
        );
      });
    }

    // ②A landing — a text, a float — is cut at the pasteboard where a file's
    // picture widens the cel past it (F-374-Q8), on the grid as the
    // landing's own edge is: a picture across both walls, against the part
    // of it inside them with the walls far off.
    for (final (ratio, zoom, turned) in offTheGrid) {
      test('the pasteboard\'s wall a landing is cut at lies on the device\'s '
          'pixels — ${atTheView(ratio, zoom, turned: turned)}', () async {
        final view = turnedOrNot(zoom, turned);
        BitmapSurface laidWide(PasteboardReach reach) => BitmapSurface(
          canvasSize: canvasSize,
          tileSize: 2,
          pasteboardReach: reach,
          tiles: const {},
          laidBounds: DirtyRegion.fromXYWH(
            x: -4,
            y: -4,
            width: 12,
            height: 12,
          ),
        );
        expect(
          await paintedAlone(
            laidWide(PasteboardReach.quarter),
            view: view,
            ratio: ratio,
            landing: CelTextLanding(
              picture: await redPicture(8, 2),
              left: -2,
              top: 1,
            ),
          ),
          equals(
            await paintedAlone(
              laidWide(PasteboardReach.whole),
              view: view,
              ratio: ratio,
              landing: CelTextLanding(
                picture: await redPicture(6, 2),
                left: -1,
                top: 1,
              ),
            ),
          ),
          reason: 'the wall cuts the landing on the pixel its own edge is '
              'cut on',
        );
      });
    }

    test('a grid whole in the canvas\'s space and not on the device\'s — '
        'the ratio decides', () async {
      // At 150% in logical pixels from a whole origin every coordinate's
      // edge is whole there, and at a ratio of 1.25 a quarter in on the
      // device: 6.25 · 10 · 13.75.
      const ratio = 1.25;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Offset.zero & const Size(16, 16));
      seamedInkSurface().paintContentInto(
        _EveryEdgeBlended(canvas)
          ..translate(5, 5)
          ..scale(1.5),
        pixelRatio: ratio,
      );
      final device = ui.PictureRecorder();
      Canvas(device)
        ..scale(ratio)
        ..drawPicture(recorder.endRecording());
      final image = await device.endRecording().toImage(20, 20);
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      bool inked(int x, int y) =>
          (x >= 6 && x <= 9 && y >= 6 && y <= 9) ||
          (x >= 10 && x <= 13 && y >= 10 && y <= 13);
      for (var y = 0; y < 20; y += 1) {
        for (var x = 0; x < 20; x += 1) {
          final at = (y * 20 + x) * 4;
          expect(
            rgba.sublist(at, at + 4),
            inked(x, y) ? red : transparent,
            reason: '($x,$y): a coordinate wholly, or nothing — cut on the '
                'device\'s grid',
          );
        }
      }
    });

    test('a float\'s picture over the walk — a transform\'s, a text\'s '
        'landing', () async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 2, 2),
        Paint()..color = const Color(0xFFFF0000),
      );
      final square = await recorder.endRecording().toImage(2, 2);
      // At canvas (1, 1), so its edges fall at 6.15 · 8.35 and 4.15 · 6.35.
      for (final (route, float) in <(String, LandingPreview)>[
        ('a transform', SelectionFloatPaint(
          image: square,
          imageLeft: 1,
          imageTop: 1,
        )),
        ('a text', CelTextLanding(picture: square, left: 1, top: 1)),
      ]) {
        final drawn = ui.PictureRecorder();
        final canvas = Canvas(drawn, Offset.zero & logical);
        float.paintInto(
          _EveryEdgeBlended(canvas)
            ..translate(5.05, 3.05)
            ..scale(zoom),
          pixelRatio: 1,
        );
        final image = await drawn.endRecording().toImage(
          logical.width.round(),
          logical.height.round(),
        );
        final rgba = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        final columns = pixelsInside(6.15, 8.35);
        final rows = pixelsInside(4.15, 6.35);
        for (var y = 0; y < logical.height.round(); y += 1) {
          for (var x = 0; x < logical.width.round(); x += 1) {
            final inside =
                x >= columns.first &&
                x <= columns.last &&
                y >= rows.first &&
                y <= rows.last;
            expect(
              rgbaAt(rgba, x, y),
              inside ? red : transparent,
              reason: '$route ($x,$y): wholly the float inside the '
                  'pixel-centre cut, untouched past it',
            );
          }
        }
      }
    });
  });

  test('on the grid — into a raster at the canvas\'s own pixels, every '
      'frame\'s picture and step\'s patch — each coordinate is one drawImage',
      () {
    // ⛔The cut's clip and shader are paid only where an edge falls inside
    // a pixel: on the grid they are the same pixels at a coordinate's draw
    // more, and a frame's picture lays thousands.
    final canvas = _WholeRecordingCanvas(const Rect.fromLTWH(0, 0, 4, 4));
    seamedInkSurface().paintContentInto(canvas, pixelRatio: 1);
    final calls = [
      for (final call in canvas.invocations) call.invocation.memberName,
    ];
    expect(calls.where((name) => name == #drawImage), hasLength(2));
    expect(calls, isNot(contains(#drawPaint)));
  });

  test('the grid\'s blit lays the texels a nearest sample picks — only its '
      'edge moves', () async {
    // A part of a 4×3 picture of twelve colours, twice its size, at a
    // phase off the grid.
    List<int> colourOf(int x, int y) => [60 * x, 80 * y, 20 + x * y, 255];
    final recorder = ui.PictureRecorder();
    final paint = Canvas(recorder);
    for (var y = 0; y < 3; y += 1) {
      for (var x = 0; x < 4; x += 1) {
        final [r, g, b, a] = colourOf(x, y);
        paint.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
          Paint()..color = Color.fromARGB(a, r, g, b),
        );
      }
    }
    final picture = await recorder.endRecording().toImage(4, 3);
    const source = Rect.fromLTWH(1, 0, 3, 3);
    const destination = Rect.fromLTWH(0, 0, 6, 6);
    const phase = Offset(1.3, 0.7);
    const size = (width: 10, height: 8);

    final drawn = ui.PictureRecorder();
    drawImageRectOnThePixelGrid(
      Canvas(drawn)..translate(phase.dx, phase.dy),
      picture,
      source,
      destination,
      filterQuality: ui.FilterQuality.none,
      pixelRatio: 1,
    );
    final image = await drawn.endRecording().toImage(size.width, size.height);
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();

    // Worked out here, not drawn by the engine: a reference drawn with
    // `drawImageRect` would blend its own edge on Impeller.
    for (var y = 0; y < size.height; y += 1) {
      for (var x = 0; x < size.width; x += 1) {
        final centre = Offset(x + 0.5, y + 0.5) - phase;
        final at = (y * size.width + x) * 4;
        expect(
          bytes.sublist(at, at + 4),
          destination.contains(centre)
              ? colourOf(
                  (source.left + centre.dx / 2).floor(),
                  (source.top + centre.dy / 2).floor(),
                )
              : const [0, 0, 0, 0],
          reason: '($x,$y): the texel its centre falls on, or nothing',
        );
      }
    }
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

/// A canvas that records its calls, its space the raster's own pixels and
/// [bounds] its clip.
class _WholeRecordingCanvas extends TestRecordingCanvas {
  _WholeRecordingCanvas(this.bounds);

  final Rect bounds;

  @override
  Rect getLocalClipBounds() => bounds;

  @override
  Rect getDestinationClipBounds() => bounds;

  @override
  Float64List getTransform() => Matrix4.identity().storage;
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
  void drawImage(ui.Image image, ui.Offset offset, ui.Paint paint) =>
      _inner.drawImage(image, offset, _blended(paint));

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
