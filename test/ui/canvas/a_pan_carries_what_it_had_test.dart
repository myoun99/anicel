import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/canvas/display_resample.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/models/composite_tree.dart';

import '../../helpers/placement_reading.dart';

/// 🚨★★★A PAN CARRIES WHAT IT ALREADY HAD.
///
/// When the extent MOVES, the previous buffer is not wrong — it is OFFSET.
/// The buffer is canvas resolution, so one buffer pixel is one canvas pixel
/// at every zoom, and the overlap belongs exactly where the new rect says.
/// What is left to composite is the band the pan exposed.
///
/// ⛔ONE IMAGE STILL. The blit and the band go into the same recorder and
/// come out of one `toImageSync`, so there is no boundary at paint time for
/// a fractional scale to seam — which is what the tile grid was rejected for
/// and what a base-drawn-beside-a-patch would bring back.
///
/// 유저 2026-08-28: 「화면에서 보이는건 바뀌면안되고」. So the test that
/// matters is bytes: a carried buffer must draw what a cold composite draws.
void main() {
  setUpAll(LayerBlendShader.load);

  const canvasSize = CanvasSize(width: 32, height: 32);
  const projectId = ProjectId('p');
  const cutId = CutId('c');
  const trackId = TrackId('t');

  BrushFrameKey keyFor(String id) => BrushFrameKey(
    projectId: projectId,
    cutId: cutId,
    trackId: trackId,
    layerId: LayerId(id),
    frameId: FrameId(id),
  );

  // A stroke in each cel, the n-th 3 px to the right of the one before and
  // in the n-th ink: blue, and a yellow that multiplies it nearly black.
  const inks = [0xFF0000FF, 0xFFFFC020];

  LayerFrameImageCache cacheWithStrokes(List<String> ids) {
    final store = BrushFrameStore();
    for (final (n, id) in ids.indexed) {
      BrushFrameEditingCoordinator(
        initialFrameKey: keyFor(id),
        frameStore: store,
        sessionStore: BrushFrameEditSessionStore(
          canvasSize: canvasSize,
          tileSize: 8,
        ),
        historyPolicy: const BrushHistoryPolicy(),
      ).commitSourceStroke(
        sourceDabs: [
          for (var i = 0; i < 4; i += 1)
            BrushDab(
              center: CanvasPoint(x: 4.0 + i * 7 + n * 3, y: 5.0 + i * 6),
              color: inks[n],
              size: 5,
              opacity: 1,
              flow: 1,
              hardness: 1,
              tipShape: BrushTipShape.round,
              pressure: 1,
              sequence: i,
            ),
        ],
      );
    }
    return LayerFrameImageCache(frameStore: store);
  }

  /// A live layer with [pixels] inked red, [alpha] opaque.
  BitmapSurfacePainter liveWith(
    Iterable<(int, int)> pixels, {
    int alpha = 255,
  }) {
    final tiles = <TileCoord, BitmapTile>{};
    for (final (x, y) in pixels) {
      final at = TileCoord(x: x ~/ 8, y: y ~/ 8);
      tiles[at] = writeRgbaColorToBitmapTile(
        tile: tiles[at] ?? BitmapTile.blank(size: 8),
        x: x % 8,
        y: y % 8,
        color: RgbaColor(r: 255, g: 0, b: 0, a: alpha),
      );
    }
    return BitmapSurfacePainter(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: 8, tiles: tiles),
      showTransparentBackground: false,
    );
  }

  final live = liveWith([for (var i = 0; i < 6; i += 1) (i, i)]);
  final nodes = <CompositeNode<CanvasStackRow>>[
    CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: keyFor('under'), opacity: 1),
    ),
    const CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1)),
  ];

  /// The cels' images, warmed at [quality] — the one the view asks for at
  /// its level.
  Future<LayerFrameImageCache> warmCache(
    WidgetTester tester, {
    List<String> ids = const ['under'],
    PlaybackQuality quality = PlaybackQuality.full,
  }) async {
    final cache = cacheWithStrokes(ids);
    for (final id in ids) {
      await tester.runAsync(
        () => cache.prepare(
          key: keyFor(id),
          canvasSize: canvasSize,
          quality: quality,
          sourceEffects: const [],
        ),
      );
    }
    return cache;
  }

  /// The view of [rows] (the file's two by default) at [viewport], [side]
  /// logical px square, drawn on over [surface].
  Widget stackAt(
    CanvasViewport viewport,
    LayerFrameImageCache cache,
    DisplayBufferCache buffers, {
    List<CompositeNode<CanvasStackRow>>? rows,
    BitmapSurfacePainter? surface,
    double side = 40,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          // ⛔SMALL, so a pan actually moves the extent: the extent is
          // CONTENT ∩ VIEW, and a view that holds the whole page never
          // moves it (that case is `a_pan_is_not_a_recomposite_test`).
          width: side,
          height: side,
          child: CanvasLayerStackView(
            // 🚨KEYED BY THE CACHE: the view adopts the cache it is first
            // built with, so until 2026-10-18 the cold composite the carry
            // is held against was painted from the warm cache — the carried
            // image compared with itself.
            key: ObjectKey(buffers),
            nodes: rows ?? nodes,
            imageCache: cache,
            debugBufferCache: buffers,
            canvasSize: canvasSize,
            viewport: viewport,
            activeSurfacePainter: surface ?? live,
            paintPaper: true,
            paperBackground: ProjectBackground.defaultBackground,
          ),
        ),
      ),
    ),
  );

  Future<Uint8List> screenAt(
    WidgetTester tester,
    CanvasViewport viewport,
    LayerFrameImageCache cache,
    DisplayBufferCache buffers, {
    List<CompositeNode<CanvasStackRow>>? rows,
    BitmapSurfacePainter? surface,
    double side = 40,
  }) async {
    await tester.pumpWidget(
      stackAt(
        viewport,
        cache,
        buffers,
        rows: rows,
        surface: surface,
        side: side,
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
    final size = Size(side, side);
    final recorder = ui.PictureRecorder();
    painted.first.painter!.paint(Canvas(recorder, Offset.zero & size), size);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(side.round(), side.round());
    picture.dispose();
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  testWidgets('a carried buffer draws what a cold composite draws', (
    tester,
  ) async {
    final cache = await warmCache(tester);
    final moved = CanvasViewport(zoom: 2, panX: 5, panY: 4);

    final warm = DisplayBufferCache();
    addTearDown(warm.dispose);
    await screenAt(
      tester,
      CanvasViewport(zoom: 2, panX: 0, panY: 0),
      cache,
      warm,
    );
    final carried = await screenAt(tester, moved, cache, warm);

    final cold = DisplayBufferCache();
    addTearDown(cold.dispose);
    final fresh = await screenAt(tester, moved, cache, cold);
    expect(
      cold.fullCount,
      1,
      reason: 'the reference was not a cold composite of its own',
    );

    expect(
      carried,
      fresh,
      reason: 'the band the pan exposed was composited and the rest was '
          'carried — byte for byte, or the carry moved pixels it should not '
          'have',
    );
  });

  testWidgets('the carry actually ran, and it is not the patch path', (
    tester,
  ) async {
    final cache = await warmCache(tester);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);

    await tester.pumpWidget(
      stackAt(CanvasViewport(zoom: 2, panX: 0, panY: 0), cache, buffers),
    );
    await tester.pumpAndSettle();
    expect(
      buffers.scrolledCount,
      0,
      reason: 'fixture: nothing to carry on the first composite',
    );

    await tester.pumpWidget(
      stackAt(CanvasViewport(zoom: 2, panX: 5, panY: 4), cache, buffers),
    );
    await tester.pumpAndSettle();

    expect(
      buffers.scrolledCount,
      greaterThan(0),
      reason: 'the extent moved and overlapped, so the buffer was carried '
          'rather than composited whole',
    );
  });

  testWidgets('a POSED live layer never carries — the change cannot be '
      'located, so the pan composites whole', (tester) async {
    // A survivor of the mutation campaign (2026-09-04, the display-buffer
    // cut): `canScroll` lost its `located` half and every test stayed
    // green — none of them panned while the live surface sat somewhere
    // other than its own coordinates. A pose is exactly that case.
    final cache = await warmCache(tester);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);
    final posed = <CompositeNode<CanvasStackRow>>[
      CompositeLeaf<CanvasStackRow>(
        CanvasLayerImageRequest(frameKey: keyFor('under'), opacity: 1),
      ),
      CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(
        opacity: 1,
        placement: placedBy(
          TransformPose(center: CanvasPoint(x: 3, y: 2)),
          canvasSize,
        ),
      )),
    ];
    Future<void> pumpAt(CanvasViewport viewport) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: CanvasLayerStackView(
                  nodes: posed,
                  imageCache: cache,
                  debugBufferCache: buffers,
                  canvasSize: canvasSize,
                  viewport: viewport,
                  activeSurfacePainter: live,
                  paintPaper: true,
                  paperBackground: ProjectBackground.defaultBackground,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpAt(CanvasViewport(zoom: 2, panX: 0, panY: 0));
    final fullBefore = buffers.fullCount;
    await pumpAt(CanvasViewport(zoom: 2, panX: 5, panY: 4));
    expect(
      buffers.scrolledCount,
      0,
      reason: 'a live layer that cannot say where it changed is never carried',
    );
    expect(
      buffers.fullCount,
      greaterThan(fullBefore),
      reason: 'the moved extent was composited whole instead',
    );
  });

  testWidgets('a pan that clears the old rect entirely composites whole', (
    tester,
  ) async {
    // ⛔THE CONTROL. With no overlap there is nothing to carry, and the code
    // must say so rather than blitting an empty rect and leaving a hole.
    final cache = await warmCache(tester);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);

    await tester.pumpWidget(
      stackAt(CanvasViewport(zoom: 4, panX: 0, panY: 0), cache, buffers),
    );
    await tester.pumpAndSettle();
    final carriedBefore = buffers.scrolledCount;

    // Far enough that the visible window shares no canvas pixel with the
    // first one.
    await tester.pumpWidget(
      stackAt(CanvasViewport(zoom: 4, panX: -400, panY: -400), cache, buffers),
    );
    await tester.pumpAndSettle();

    expect(
      buffers.scrolledCount,
      carriedBefore,
      reason: 'nothing overlapped, so nothing was carried',
    );
  });

  testWidgets('the carry composites LESS than the whole rect', (tester) async {
    // 🚨THE COUNTER SAYS IT RAN; THIS SAYS IT SAVED SOMETHING. 🧪A mutation
    // that dropped the subtraction left the clip covering the whole rect:
    // correct pixels, no saving, and every other test green. That is the
    // shape this file exists to refuse.
    final cache = await warmCache(tester);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);

    await tester.pumpWidget(
      stackAt(CanvasViewport(zoom: 2, panX: 0, panY: 0), cache, buffers),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      stackAt(CanvasViewport(zoom: 2, panX: 5, panY: 4), cache, buffers),
    );
    await tester.pumpAndSettle();

    final area = buffers.lastComposedArea;
    expect(area, isNotNull, reason: 'fixture: a carry happened');
    // ⛔ZERO IS THE BEST ANSWER, not a failure: when the new extent is a
    // SUBSET of the old one the whole rect is carried and nothing is
    // composited at all. 🧪The first version of this test demanded area > 0
    // and failed on exactly that case.
    //
    // The claim is the ceiling: the window is 40 logical px at zoom 2 = 20
    // canvas px a side, so a carry that composites near 400 has carried
    // nothing in practice.
    expect(
      area,
      lessThan(20 * 20 * 0.75),
      reason: 'a carry that composites nearly the whole rect is a carry in '
          'name only',
    );
  });

  // 🚨★★★F-287: a carry over a stack holding a blend laid that blend over
  // the carried pixels once more — the 「캔버스 줌인 줌아웃할때마다」 half of
  // the card, whose stroke half is `a_stroke_step_draws_its_picture_test`.
  // On the Windows app the clip a carry stood on did not hold the GPU's
  // blend (the paint pass's `_recomposeOverCarried` has the measurement).
  // ↩️Such a carry was composed APART, and these pinned that route and held
  // it to the clip — a cold composite was 1/255 off in a few pixels with a
  // GPU screen row, a blend that rounded by the area it blended through —
  // until every advanced blend went over its backdrop in the shader
  // (a-blurred-folder-cut-by-the-view-moves-on-vulkan). The user's stacks,
  // as the plan hands them over, are held to a cold composite now, as the
  // first test here holds a stack of normal rows.
  group('F-287 — a carry through a blend draws what a cold composite draws',
      () {
    const ids = ['under', 'over'];
    const multiplied = LayerBlendMode.multiply;
    CompositeNode<CanvasStackRow> row(String id) =>
        CompositeLeaf<CanvasStackRow>(
          CanvasLayerImageRequest(frameKey: keyFor(id), opacity: 1),
        );
    CompositeNode<CanvasStackRow> blended(
      CompositeNode<CanvasStackRow> source,
      LayerBlendMode blendMode, {
      List<CompositeNode<CanvasStackRow>> over = const [],
    }) => CompositeBackdropBlend<CanvasStackRow>(
      backdrop: over,
      source: source,
      blendMode: blendMode,
    );
    const drawnOn = CompositeLeaf<CanvasStackRow>(
      CanvasActiveLayerRow(opacity: 1),
    );
    final stacks = <String, List<CompositeNode<CanvasStackRow>>>{
      // The user's: two rows in multiply, a normal row drawn on above.
      'two rows in multiply under the live row': [
        blended(
          row('over'),
          multiplied,
          over: [blended(row('under'), multiplied)],
        ),
        drawnOn,
      ],
      'the live row itself in screen': [
        blended(
          drawnOn,
          LayerBlendMode.screen,
          over: [row('under'), row('over')],
        ),
      ],
      'a folder in overlay': [
        blended(
          CompositeGroup<CanvasStackRow>(
            children: [row('under'), row('over')],
            opacity: 1,
            blendMode: LayerBlendMode.normal,
          ),
          LayerBlendMode.overlay,
        ),
        drawnOn,
      ],
      'a row in multiply inside a normal folder': [
        CompositeGroup<CanvasStackRow>(
          children: [
            blended(row('over'), multiplied, over: [row('under')]),
          ],
          opacity: 1,
          blendMode: LayerBlendMode.normal,
        ),
        drawnOn,
      ],
      'a row in multiply under an adjustment': [
        CompositeAdjustment<CanvasStackRow>(
          children: [
            blended(row('over'), multiplied, over: [row('under')]),
          ],
          effects: [
            ResolvedLayerEffect(
              kind: EffectKind.brightnessContrast,
              values: const [20, 15],
            ),
          ],
          mix: 1,
        ),
        drawnOn,
      ],
    };
    // A red cross through the middle of the page, so every band below
    // holds some of the live row.
    final crossed = liveWith([
      for (var i = 0; i < 32; i += 1) ...[(i, 16), (16, i)],
    ], alpha: 200);
    // Each a carry — the extent moves on the level it is on: from where, to
    // where, in a view `side` logical px square at `ratio` device px to
    // one, and whether a band is left to compose. At no pan the page's
    // corner is the view's, so a view moved right and down shows more page.
    final moves = [
      // A band down the right and one along the bottom.
      (
        name: 'a pan',
        from: CanvasViewport(zoom: 2),
        to: CanvasViewport(zoom: 2, panX: -6, panY: -4),
        side: 40.0,
        ratio: 3.0,
        banded: true,
      ),
      // The same two bands, the window growing from its corner.
      (
        name: 'a zoom out on its level',
        from: CanvasViewport(zoom: 2.5),
        to: CanvasViewport(zoom: 2),
        side: 40.0,
        ratio: 3.0,
        banded: true,
      ),
      // ⛔The new rect lies inside the old one: no band, and nothing to
      // compose.
      (
        name: 'a zoom in on its level',
        from: CanvasViewport(zoom: 2),
        to: CanvasViewport(zoom: 2.5),
        side: 40.0,
        ratio: 3.0,
        banded: false,
      ),
      // Below 100% the buffer is a level image: the bands lie on its grid,
      // two level pixels wide, composed at its scale.
      (
        name: 'a pan below 100%',
        from: CanvasViewport(zoom: 0.5),
        to: CanvasViewport(zoom: 0.5, panX: -2, panY: -2),
        side: 8.0,
        ratio: 1.0,
        banded: true,
      ),
    ];

    for (final MapEntry(key: stack, value: rows) in stacks.entries) {
      for (final at in moves) {
        testWidgets('$stack, ${at.name}', (tester) async {
          tester.view.devicePixelRatio = at.ratio;
          addTearDown(tester.view.resetDevicePixelRatio);
          final level = displayLevelOf(displayScaleOf(at.to.zoom, at.ratio));
          final cache = await warmCache(
            tester,
            ids: ids,
            quality: PlaybackQuality.forLevel(level),
          );
          Future<Uint8List> screen(
            CanvasViewport viewport,
            DisplayBufferCache buffers,
          ) => screenAt(
            tester,
            viewport,
            cache,
            buffers,
            rows: rows,
            surface: crossed,
            side: at.side,
          );

          final carried = DisplayBufferCache();
          addTearDown(carried.dispose);
          await screen(at.from, carried);
          final moved = await screen(at.to, carried);
          expect(carried.lastBufferLevel, level, reason: 'fixture: the level');
          expect(
            carried.scrolledCount,
            1,
            reason: 'fixture: the move was not carried',
          );
          expect(
            carried.lastComposedArea,
            at.banded ? greaterThan(0) : 0,
            reason: 'fixture: the bands',
          );

          final cold = DisplayBufferCache();
          addTearDown(cold.dispose);
          final fresh = await screen(at.to, cold);
          expect(
            cold.fullCount,
            1,
            reason: 'the reference was not a cold composite of its own',
          );
          expect(
            moved,
            fresh,
            reason: 'the bands composed and the rest carried — byte for byte '
                'the screen a cold composite makes',
          );
        });
      }
    }

    // ↩️'…and a stack that blends in place carries on its clip' was pinned
    // here, the route's own other half.
  });
}
