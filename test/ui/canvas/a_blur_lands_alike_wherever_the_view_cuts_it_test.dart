@Tags(['impeller'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
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
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🚨★★★A BLUR LANDS ALIKE WHEREVER THE VIEW CUTS WHAT IT READS (card
/// nested-folder-buffers-read-past-the-view, 🤖 verify 2026-10-27: a blurred
/// folder › folder › the row drawn on, by the view's edge — the blur came out
/// 190 → 211 as the view moved a pixel at a time).
///
/// A blur reduces what it reads on a grid counted from that picture's own
/// corner. Where the view cut a folder's raster — or the layer an
/// adjustment's blur rode — that corner moved with each pan, and the frame
/// drawn as it stands (what a canvas shows while its row under a blur is
/// drawn on) blurred the same ink another way at each pixel, and another way
/// than the frame's own picture, which nothing cuts.
///
/// Each case pans the view a pixel at a time with the ink by its left edge,
/// the blur reaching past it, and asks of every pan whose raster lies on the
/// same cells ([blurReductionCell]) as the first: the same bytes, a pixel
/// over. A pan onto other cells and the frame's picture are asked the same
/// within [rounding].
///
/// ⚠️Impeller's alone: the reduction is its Gaussian's. Skia's test raster
/// blurs with none and lands alike either way.
void main() {
  setUpAll(LayerBlendShader.load);

  const canvasSize = CanvasSize(width: 512, height: 256);
  const view = Size(160, 64);
  // The view's left edge at the first pan; the ink 20 pixels inside it, and
  // ink far left of it too, so what the row stands for is cut by the view.
  const edge = 180.0;
  const top = 96.0;
  // ⚠️What this tester's Impeller (Vulkan) rounds a blur by where the raster
  // it reads is another size: 🔬2026-10-27, on the grid, a pan onto other
  // cells and the frame's picture came out up to 2 apart (a folder in a
  // folder), and the Windows app (GLES) 0. Off the grid every pan moved by
  // up to 5 (a blurred folder), 3 (a folder in one), 2 (an adjustment) — the
  // exact claim on the same cells is what holds those.
  const rounding = 2;
  final blur = [ResolvedLayerEffect(kind: EffectKind.blur, values: [40, 40])];

  const frameKey = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  ({LayerFrameImageCache cache, BitmapSurfacePainter pen}) bars() {
    final store = BrushFrameStore();
    BrushFrameEditingCoordinator(
      initialFrameKey: frameKey,
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 64,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    ).commitSourceStroke(
      sourceDabs: [
        for (final x in [40.0, edge + 20])
          for (var i = 0; i < 64; i += 1)
            BrushDab(
              center: CanvasPoint(x: x, y: 4.0 * i),
              color: 0xFF202020,
              size: 10,
              opacity: 1,
              flow: 1,
              hardness: 1,
              tipShape: BrushTipShape.round,
              pressure: 1,
              sequence: i,
            ),
      ],
    );
    final cache = LayerFrameImageCache(frameStore: store);
    addTearDown(cache.dispose);
    return (
      cache: cache,
      pen: BitmapSurfacePainter(
        surface: store.currentSurfaceWithoutReplay(
          frameKey,
          canvasSize: canvasSize,
        )!,
        showTransparentBackground: false,
      ),
    );
  }

  CompositeNode<CanvasStackRow> rowOf({
    required bool drawnOn,
    List<ResolvedLayerEffect> effects = const [],
  }) => CompositeLeaf<CanvasStackRow>(
    drawnOn
        ? CanvasActiveLayerRow(opacity: 1, effects: effects)
        : CanvasLayerImageRequest(
            frameKey: frameKey,
            opacity: 1,
            effects: effects,
          ),
  );

  CompositeNode<CanvasStackRow> folder(
    List<CompositeNode<CanvasStackRow>> children, {
    double opacity = 1,
    List<ResolvedLayerEffect> effects = const [],
  }) => CompositeGroup(
    children: children,
    opacity: opacity,
    blendMode: LayerBlendMode.normal,
    effects: effects,
  );

  final scenes = <String, List<CompositeNode<CanvasStackRow>> Function(bool)>{
    'a blurred folder': (drawnOn) => [
      folder([rowOf(drawnOn: drawnOn)], effects: blur),
    ],
    'a folder at 55% in a blurred folder': (drawnOn) => [
      folder([
        folder([rowOf(drawnOn: drawnOn)], opacity: 0.55),
      ], effects: blur),
    ],
    'a blurred row': (drawnOn) => [rowOf(drawnOn: drawnOn, effects: blur)],
    'a blurring adjustment': (drawnOn) => [
      CompositeAdjustment(
        children: [rowOf(drawnOn: drawnOn)],
        effects: blur,
        mix: 1,
      ),
    ],
    'a blurring adjustment at half': (drawnOn) => [
      CompositeAdjustment(
        children: [rowOf(drawnOn: drawnOn)],
        effects: blur,
        mix: 0.5,
      ),
    ],
  };

  StackedFrame frameOf(
    List<CompositeNode<CanvasStackRow>> nodes,
    ({LayerFrameImageCache cache, BitmapSurfacePainter pen}) ink, {
    required bool drawnOn,
  }) => stackedFrameOf(
    nodes,
    page: (
      canvasSize: canvasSize,
      pasteboardReach: PasteboardReach.whole,
      paintPaper: true,
      paperBackground: ProjectBackground.defaultBackground,
    ),
    surfaceOf: (cel) =>
        ink.cache.storedSurfaceOrNull(cel, canvasSize: canvasSize),
    live: (
      rows: (
        activeSurfacePainter: drawnOn ? ink.pen : null,
        floatOverlay: null,
        liftedRows: const {},
      ),
      painters: LiftedRowPainters(),
    ),
  );

  Future<Uint8List> rgbaOf(WidgetTester tester, ui.Picture picture, Size at) =>
      tester.runAsync(() async {
        final image = picture.toImageSync(
          at.width.toInt(),
          at.height.toInt(),
        );
        picture.dispose();
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return data!.buffer.asUint8List();
      }).then((bytes) => bytes!);

  /// The view, its left edge at [left], as the frame drawn as it stands
  /// lays it.
  Future<Uint8List> asItStands(
    WidgetTester tester,
    StackedFrame frame,
    double left,
  ) {
    final recorder = ui.PictureRecorder();
    frame.paintOnScreen(
      Canvas(recorder),
      view,
      viewport: CanvasViewport(panX: -left, panY: -top),
      devicePixelRatio: 1,
    );
    return rgbaOf(tester, recorder.endRecording(), view);
  }

  /// The frame's own picture — the world over its extent, as the store
  /// lays it — and where it lies.
  Future<({Uint8List rgba, Rect extent})> pictureOf(
    WidgetTester tester,
    StackedFrame frame,
  ) async {
    final drawing = frame.drawing;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..translate(-drawing.extent.left, -drawing.extent.top);
    drawing.draw(canvas);
    return (
      rgba: await rgbaOf(tester, recorder.endRecording(), drawing.extent.size),
      extent: drawing.extent,
    );
  }

  for (final MapEntry(key: name, value: nodesOf) in scenes.entries) {
    for (final drawnOn in [false, true]) {
      // ⛔Not a blurred row while it is the row drawn on: its blur rides a
      // `saveLayer` the view cuts, and the exact route — the row rastered on
      // the grid — cost 2.1–2.6x on the path a stroke redraws every step
      // (🔬Windows app 2026-10-27, raster p50 4.4–5.0 → 10.3–11.5 ms; the
      // other scenes did not move). Whether to pay it is the user's:
      // nested-folder-buffers-read-past-the-view-Q1.
      if (name == 'a blurred row' && drawnOn) {
        continue;
      }
      testWidgets('$name, ${drawnOn ? 'its row drawn on' : 'a cel'}: '
          'a pan by a pixel moves the blur by a pixel, as the frame\'s '
          'picture lays it', (tester) async {
        debugLastSubtreeRaster = null;
        final ink = bars();
        final frame = frameOf(nodesOf(drawnOn), ink, drawnOn: drawnOn);
        final picture = await pictureOf(tester, frame);
        final width = view.width.toInt();
        final first = await asItStands(tester, frame, edge);
        final cells = debugLastSubtreeRaster?.destination;
        // How many bytes are off by how much: pan to pan on the first pan's
        // cells, pan to pan onto others, and from the picture.
        final moved = <int, int>{};
        final movedAcross = <int, int>{};
        final unlike = <int, int>{};
        void tally(Map<int, int> into, int by) {
          if (by > 0) {
            into[by] = (into[by] ?? 0) + 1;
          }
        }

        var onTheCells = 0;
        for (var k = 1; k <= 4; k += 1) {
          final left = edge + k;
          final shown = await asItStands(tester, frame, left);
          final same = debugLastSubtreeRaster?.destination == cells;
          onTheCells += same ? 1 : 0;
          for (var y = 0; y < view.height; y += 1) {
            for (var x = 0; x < width; x += 1) {
              final at = (y * width + x) * 4;
              final px = (left + x - picture.extent.left).toInt();
              final py = (top + y - picture.extent.top).toInt();
              final there = (py * picture.extent.width.toInt() + px) * 4;
              for (var c = 0; c < 4; c += 1) {
                if (x + k < width) {
                  tally(
                    same ? moved : movedAcross,
                    (shown[at + c] - first[(y * width + x + k) * 4 + c]).abs(),
                  );
                }
                tally(unlike, (shown[at + c] - picture.rgba[there + c]).abs());
              }
            }
          }
        }
        expect(
          onTheCells,
          greaterThan(0),
          reason: '⛔premise: some pan stays on the first pan\'s cells',
        );
        expect(
          moved,
          isEmpty,
          reason: 'on the same cells, the same bytes a pixel over',
        );
        expect(
          movedAcross.keys.where((by) => by > rounding),
          isEmpty,
          reason: 'bytes moved by how much onto other cells: $movedAcross',
        );
        expect(
          unlike.keys.where((by) => by > rounding),
          isEmpty,
          reason: 'bytes unlike the picture, by how much: $unlike',
        );
      });
    }
  }
}
