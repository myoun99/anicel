import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_piece.dart';
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
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/brush/cut_piece_preview.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🎯A STROKE STEP DRAWS ITS PICTURE (2026-09-25). A patch over the real
/// base whose picture lands the same bytes on the screen goes there as that
/// picture, and no head is rastered — a render pass a step, since a
/// snapshot costs the same whatever its size.
///
/// Every screen of a stroke is held against the one the rastered head makes
/// of the same step (`debugDrawBufferPictures` off), byte for byte; and
/// every reason the picture would NOT be the same bytes is driven and must
/// raster the head instead.
///
/// ⚠️UNDER `runAsync`, WITH A TURN OF THE EVENT QUEUE AFTER EACH PAINT — the
/// real base is a real `Picture.toImage`, which the fake async zone never
/// completes; without it no step would patch the real base at all.
///
/// ⚠️CAPTURED THROUGH `toImageSync` for the reason
/// `a_cropped_cel_draws_the_same_bytes_test.dart` gives: the test runner's
/// Skia blends some images through a legacy blitter that rounds apart from
/// its pipeline, a difference only this runner has.
void main() {
  const canvasSize = CanvasSize(width: 256, height: 256);
  const tileSize = 64;
  const steps = 12;
  const view = Size(256, 256);
  const paper = ProjectBackground.color(0xFFF4EEE0);
  final screenKey = GlobalKey();

  BrushFrameKey key(String id) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(id),
    frameId: FrameId('$id-f'),
  );

  /// A stroke inside the tile at [at]: step i has drawn pixels 0…i of a
  /// line through it.
  List<BitmapSurfacePainter> strokeIn(
    TileCoord at, {
    ValueListenable<CutStampPreview?>? ghost,
  }) {
    final painters = <BitmapSurfacePainter>[];
    var tile = BitmapTile.blank(size: tileSize);
    for (var step = 0; step <= steps; step += 1) {
      tile = writeRgbaColorToBitmapTile(
        tile: tile,
        x: 3 + step * 4,
        y: 10 + step,
        color: RgbaColor(r: 200, g: 30, b: 30, a: 160),
      );
      painters.add(
        BitmapSurfacePainter(
          surface: BitmapSurface(
            canvasSize: canvasSize,
            tileSize: tileSize,
            tiles: {at: tile},
          ),
          showTransparentBackground: false,
          stampPreview: ghost,
        ),
      );
    }
    return painters;
  }

  final onPaper = strokeIn(TileCoord(x: 1, y: 1));

  const activeRow = CompositeLeaf<CanvasStackRow>(
    CanvasActiveLayerRow(opacity: 1),
  );

  // The rows under the stroke, for the scenes that need some: cels
  // committed to a store, their images warmed the way the view asks.
  const cels = <String, (int, List<(double, double)>)>{
    'below': (0xFF2040C0, [(100, 100), (150, 120)]),
    'aside': (0xFF20A060, [(60, 180), (200, 40)]),
  };

  BrushFrameStore storeWithCels() {
    final store = BrushFrameStore();
    for (final MapEntry(key: id, value: (color, points)) in cels.entries) {
      BrushFrameEditingCoordinator(
        initialFrameKey: key(id),
        frameStore: store,
        sessionStore: BrushFrameEditSessionStore(
          canvasSize: canvasSize,
          tileSize: tileSize,
        ),
        historyPolicy: const BrushHistoryPolicy(),
      ).commitSourceStroke(
        sourceDabs: [
          for (var i = 0; i < points.length; i += 1)
            BrushDab(
              center: CanvasPoint(x: points[i].$1, y: points[i].$2),
              color: color,
              size: 11,
              opacity: 1,
              flow: 1,
              hardness: 0.5,
              tipShape: BrushTipShape.round,
              pressure: 1,
              sequence: i,
            ),
        ],
      );
    }
    return store;
  }

  CompositeNode<CanvasStackRow> row(
    String id, {
    LayerBlendMode blendMode = LayerBlendMode.normal,
    CameraPose? pose,
  }) => CompositeLeaf<CanvasStackRow>(
    CanvasLayerImageRequest(
      frameKey: key(id),
      opacity: 1,
      blendMode: blendMode,
      pose: pose,
    ),
  );

  Iterable<CanvasLayerImageRequest> requestsIn(
    List<CompositeNode<CanvasStackRow>> nodes,
  ) sync* {
    for (final node in nodes) {
      switch (node) {
        case CompositeLeaf(payload: final CanvasLayerImageRequest request):
          yield request;
        case CompositeLeaf():
          break;
        case CompositeGroup(:final children):
        case CompositeAdjustment(:final children):
          yield* requestsIn(children);
      }
    }
  }

  Future<LayerFrameImageCache> imagesFor(
    WidgetTester tester,
    List<CompositeNode<CanvasStackRow>> nodes,
  ) async {
    final images = LayerFrameImageCache(frameStore: storeWithCels());
    addTearDown(images.dispose);
    for (final request in requestsIn(nodes)) {
      final warmed = await tester.runAsync(
        () => images.prepare(
          key: request.frameKey,
          canvasSize: canvasSize,
          quality: PlaybackQuality.forLevel(0),
          sourceEffects: request.sourceEffects,
          inkSuffices: request.inkSuffices,
        ),
      );
      expect(warmed, isNotNull, reason: 'fixture: ${request.frameKey}');
    }
    return images;
  }

  Future<void> paint(
    WidgetTester tester, {
    required DisplayBufferCache buffers,
    required LayerFrameImageCache images,
    required List<CompositeNode<CanvasStackRow>> nodes,
    required BitmapSurfacePainter surface,
    required CanvasViewport viewport,
    required ProjectBackground background,
    required bool paintPaper,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: screenKey,
            child: SizedBox(
              width: view.width,
              height: view.height,
              // Keyed by the cache: the view adopts the cache it is first
              // built with, so a stroke with a cache of its own needs a view
              // of its own — or its counts are another stroke's.
              child: CanvasLayerStackView(
                key: ObjectKey(buffers),
                nodes: nodes,
                imageCache: images,
                debugBufferCache: buffers,
                canvasSize: canvasSize,
                viewport: viewport,
                activeSurfacePainter: surface,
                paintPaper: paintPaper,
                paperBackground: background,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<Uint8List> capture() async {
    final boundary =
        screenKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = boundary.toImageSync();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// A stroke painted step by step over [below], each step's screen
  /// captured, and how many of its steps patched and drew their picture.
  Future<({List<Uint8List> screens, int patched, int pictures})> stroke(
    WidgetTester tester, {
    required CanvasViewport viewport,
    List<CompositeNode<CanvasStackRow>> below = const [],
    List<CompositeNode<CanvasStackRow>>? nodes,
    List<BitmapSurfacePainter>? painters,
    ProjectBackground background = paper,
    bool paintPaper = true,
  }) async {
    final all = nodes ?? [...below, activeRow];
    final images = await imagesFor(tester, all);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);
    final surfaces = painters ?? onPaper;
    final screens = <Uint8List>[];
    await tester.runAsync(() async {
      for (var step = 0; step <= steps; step += 1) {
        await paint(
          tester,
          buffers: buffers,
          images: images,
          nodes: all,
          surface: surfaces[step],
          viewport: viewport,
          background: background,
          paintPaper: paintPaper,
        );
        // The snapshot the step may have asked for lands here.
        await Future<void>.delayed(Duration.zero);
        if (step > 0) {
          screens.add(await capture());
        }
      }
    });
    return (
      screens: screens,
      patched: buffers.patchedCount,
      pictures: buffers.drawnCount,
    );
  }

  /// The same stroke with the head rastered at every step — the screens
  /// the pictures must reproduce.
  Future<List<Uint8List>> strokeByHeads(
    WidgetTester tester, {
    required CanvasViewport viewport,
    List<CompositeNode<CanvasStackRow>> below = const [],
  }) async {
    debugDrawBufferPictures = false;
    try {
      final made = await stroke(tester, viewport: viewport, below: below);
      expect(made.pictures, 0, reason: 'the head arm drew a picture');
      return made.screens;
    } finally {
      debugDrawBufferPictures = true;
    }
  }

  void expectSameScreens(List<Uint8List> pictures, List<Uint8List> heads) {
    expect(pictures, hasLength(heads.length));
    for (var step = 0; step < heads.length; step += 1) {
      final a = pictures[step];
      final b = heads[step];
      expect(a.length, b.length);
      var differing = 0;
      String? first;
      for (var i = 0; i < a.length; i += 1) {
        if (a[i] != b[i]) {
          differing += 1;
          if (first == null) {
            final pixel = i ~/ 4;
            first =
                '(${pixel % view.width.toInt()},${pixel ~/ view.width.toInt()})'
                ' c${i % 4} ${b[i]}→${a[i]}';
          }
        }
      }
      expect(
        differing,
        0,
        reason: 'step ${step + 1}: the picture is not the head — $first',
      );
    }
  }

  void useView(WidgetTester tester) {
    tester.view.physicalSize = view;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('a step over the real base draws its picture, and the screen is the '
      "head's, byte for byte", () {
    final viewports = <String, CanvasViewport>{
      '100%': CanvasViewport(),
      '200%': CanvasViewport(zoom: 2),
      '300%, panned': CanvasViewport(zoom: 3, panX: -97, panY: -130),
      '100%, flipped': CanvasViewport(flipHorizontal: true, panX: 256),
    };
    for (final entry in viewports.entries) {
      testWidgets(entry.key, (tester) async {
        useView(tester);
        final drawn = await stroke(tester, viewport: entry.value);
        expect(
          drawn.patched,
          greaterThanOrEqualTo(steps),
          reason: 'the steps did not patch, so nothing here was compared',
        );
        expect(drawn.pictures, steps, reason: 'a step rastered its head');
        expectSameScreens(
          drawn.screens,
          await strokeByHeads(tester, viewport: entry.value),
        );
      });
    }

    testWidgets('over folders and rows through normal and add', (
      tester,
    ) async {
      useView(tester);
      final below = [
        CompositeGroup<CanvasStackRow>(
          children: [row('below')],
          opacity: 0.8,
          blendMode: LayerBlendMode.normal,
        ),
        row('aside', blendMode: LayerBlendMode.add),
      ];
      final viewport = CanvasViewport(zoom: 2, panX: -40, panY: -60);
      final drawn = await stroke(tester, viewport: viewport, below: below);
      expect(drawn.pictures, steps);
      expectSameScreens(
        drawn.screens,
        await strokeByHeads(tester, viewport: viewport, below: below),
      );
    });
  });

  group('where the picture would not be the same bytes, the head is '
      'rastered', () {
    Future<void> expectHeads(
      WidgetTester tester, {
      CanvasViewport? viewport,
      List<CompositeNode<CanvasStackRow>> below = const [],
      List<CompositeNode<CanvasStackRow>>? nodes,
      List<BitmapSurfacePainter>? painters,
      ProjectBackground background = paper,
      bool paintPaper = true,
    }) async {
      useView(tester);
      final made = await stroke(
        tester,
        viewport: viewport ?? CanvasViewport(),
        below: below,
        nodes: nodes,
        painters: painters,
        background: background,
        paintPaper: paintPaper,
      );
      expect(
        made.patched,
        greaterThanOrEqualTo(steps),
        reason: 'the steps did not patch, so no picture was ever possible',
      );
      expect(made.pictures, 0);
    }

    testWidgets('between whole scales', (tester) async {
      await expectHeads(tester, viewport: CanvasViewport(zoom: 1.5));
    });

    testWidgets('on a rotated view', (tester) async {
      await expectHeads(
        tester,
        viewport: CanvasViewport(rotationDegrees: 90, panX: 256),
      );
    });

    testWidgets('on translucent paper', (tester) async {
      await expectHeads(
        tester,
        background: const ProjectBackground.color(0xC0F4EEE0),
      );
    });

    testWidgets('with no paper', (tester) async {
      await expectHeads(tester, paintPaper: false);
    });

    // Each edge of the paper: the clear would reach the pasteboard there.
    final pastEdges = <String, (TileCoord, CanvasViewport)>{
      'left': (TileCoord(x: -1, y: 1), CanvasViewport(panX: 128)),
      'top': (TileCoord(x: 1, y: -1), CanvasViewport(panY: 128)),
      'right': (TileCoord(x: 4, y: 1), CanvasViewport(panX: -128)),
      'bottom': (TileCoord(x: 1, y: 4), CanvasViewport(panY: -128)),
    };
    for (final MapEntry(key: edge, value: (at, viewport)) in pastEdges.entries) {
      testWidgets('off the paper, past its $edge edge', (tester) async {
        await expectHeads(
          tester,
          viewport: viewport,
          painters: strokeIn(at),
        );
      });
    }

    testWidgets('through a blend that is not in place', (tester) async {
      await expectHeads(
        tester,
        nodes: const [
          CompositeLeaf<CanvasStackRow>(
            CanvasActiveLayerRow(
              opacity: 1,
              blendMode: LayerBlendMode.multiply,
            ),
          ),
        ],
      );
    });

    testWidgets('over a row through a blend that is not in place', (
      tester,
    ) async {
      await expectHeads(
        tester,
        below: [row('below', blendMode: LayerBlendMode.multiply)],
      );
    });

    testWidgets('over a posed row', (tester) async {
      await expectHeads(
        tester,
        below: [
          row('below', pose: CameraPose(center: CanvasPoint(x: 130, y: 128))),
        ],
      );
    });

    testWidgets('over a folder through a blend that is not in place', (
      tester,
    ) async {
      await expectHeads(
        tester,
        below: [
          CompositeGroup<CanvasStackRow>(
            children: [row('below')],
            opacity: 1,
            blendMode: LayerBlendMode.multiply,
          ),
        ],
      );
    });

    testWidgets('over a folder holding a row through a blend that is not in '
        'place', (tester) async {
      await expectHeads(
        tester,
        below: [
          CompositeGroup<CanvasStackRow>(
            children: [row('below', blendMode: LayerBlendMode.multiply)],
            opacity: 1,
            blendMode: LayerBlendMode.normal,
          ),
        ],
      );
    });

    testWidgets('over an adjustment scope', (tester) async {
      await expectHeads(
        tester,
        below: [
          CompositeAdjustment<CanvasStackRow>(
            children: [row('below')],
            effects: [
              ResolvedLayerEffect(
                kind: EffectKind.brightnessContrast,
                values: const [20, 15],
              ),
            ],
            mix: 1,
          ),
        ],
      );
    });

    testWidgets('with a stamp ghost on the layer', (tester) async {
      final ghostImage = await tester.runAsync(() {
        final done = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          Uint8List(4 * 4 * 4)..fillRange(0, 4 * 4 * 4, 255),
          4,
          4,
          ui.PixelFormat.rgba8888,
          done.complete,
        );
        return done.future;
      });
      addTearDown(ghostImage!.dispose);
      final ghost = ValueNotifier<CutStampPreview?>(
        CutStampPreview(
          piece: CutPiece(
            image: BrushStampImage(
              id: 'ghost',
              width: 4,
              height: 4,
              rgba: Uint8List(4 * 4 * 4)..fillRange(0, 4 * 4 * 4, 255),
            ),
            originLeft: 0,
            originTop: 0,
          ),
          image: ghostImage,
          canvasRect: const Rect.fromLTWH(30.5, 40.25, 4, 4),
          opacity: 1,
          blendMode: BrushBlendMode.color,
        ),
      );
      addTearDown(ghost.dispose);
      await expectHeads(
        tester,
        painters: strokeIn(TileCoord(x: 1, y: 1), ghost: ghost),
      );
    });

    testWidgets('on iOS, whose screen is wide-gamut', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await expectHeads(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  testWidgets('the buffer counters line says how many patches drew their '
      'picture', (tester) async {
    useView(tester);
    InputInspector.reset();
    CanvasPaintGeometryProbe.reset();
    InputInspector.visible.value = true;
    addTearDown(() {
      InputInspector.reset();
      CanvasPaintGeometryProbe.reset();
    });
    final images = await imagesFor(tester, const [activeRow]);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);
    var drawn = -1;
    await tester.runAsync(() async {
      for (var step = 0; step <= steps; step += 1) {
        await paint(
          tester,
          buffers: buffers,
          images: images,
          nodes: const [activeRow],
          surface: onPaper[step],
          viewport: CanvasViewport(),
          background: paper,
          paintPaper: true,
        );
        await Future<void>.delayed(Duration.zero);
      }
      drawn = buffers.drawnCount;
      // The line prints on its cadence; forgotten, the next paint prints
      // what the buffer counts as it begins.
      CanvasPaintGeometryProbe.lastCounters = null;
      for (final painted in tester.renderObjectList<RenderCustomPaint>(
        find.descendant(
          of: find.byType(CanvasLayerStackView),
          matching: find.byType(CustomPaint),
        ),
      )) {
        painted.markNeedsPaint();
      }
      await tester.pump();
    });
    expect(drawn, steps);
    expect(InputInspector.notes['buf'], contains('drawn=$steps'));
  });

  testWidgets('a step before the first snapshot lands derives from the head, '
      'and rasters its own', (tester) async {
    useView(tester);
    final images = await imagesFor(tester, const [activeRow]);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);
    // The one snapshot slot held by a snapshot that never lands, so no real
    // base ever does: the step can only patch the head.
    buffers.promote(Completer<ui.Image>().future);
    for (final step in [0, 1]) {
      await paint(
        tester,
        buffers: buffers,
        images: images,
        nodes: const [activeRow],
        surface: onPaper[step],
        viewport: CanvasViewport(),
        background: paper,
        paintPaper: true,
      );
    }
    expect(buffers.derivedDepth, 1, reason: 'the step did not derive');
    expect(buffers.patchedCount, 1);
    expect(buffers.drawnCount, 0);
  });

  testWidgets('a still canvas is answered by the snapshot of its last '
      'picture, and composes nothing', (tester) async {
    useView(tester);
    final images = await imagesFor(tester, const [activeRow]);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);
    Future<void> paintStep(int step) => paint(
      tester,
      buffers: buffers,
      images: images,
      nodes: const [activeRow],
      surface: onPaper[step],
      viewport: CanvasViewport(),
      background: paper,
      paintPaper: true,
    );
    Future<void> repaint() async {
      for (final painted in tester.renderObjectList<RenderCustomPaint>(
        find.descendant(
          of: find.byType(CanvasLayerStackView),
          matching: find.byType(CustomPaint),
        ),
      )) {
        painted.markNeedsPaint();
      }
      await tester.pump();
      await Future<void>.delayed(Duration.zero);
    }

    await tester.runAsync(() async {
      for (var step = 0; step <= steps; step += 1) {
        await paintStep(step);
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        buffers.drawnCount,
        steps,
        reason: 'the stroke drew no pictures, so nothing here is about them',
      );
      // Still: the last patch is drawn again only until a snapshot of it
      // has been asked for and has landed.
      for (var i = 0; i <= DisplayBufferCache.promoteEvery; i += 1) {
        await repaint();
      }
      final drawnThen = buffers.drawnCount;
      final keptThen = buffers.keptCount;
      final composedThen = buffers.patchedCount + buffers.fullCount;
      await repaint();
      expect(
        buffers.keptCount,
        keptThen + 1,
        reason: 'the repaint was not answered by what the cache keeps',
      );
      expect(buffers.drawnCount, drawnThen);
      expect(buffers.patchedCount + buffers.fullCount, composedThen);
    });
  });
}
