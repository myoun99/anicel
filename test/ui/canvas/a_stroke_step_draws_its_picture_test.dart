import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:anicel/src/models/composite_tree.dart';
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
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/canvas/display_resample.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/placement_reading.dart';

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

  // A row blended over its backdrop is composed by this shader.
  setUpAll(LayerBlendShader.load);

  BrushFrameKey key(String id) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(id),
    frameId: FrameId('$id-f'),
  );

  /// A stroke inside the tile at [at]: step i has drawn pixels 0…i of a
  /// line through it.
  List<BitmapSurfacePainter> strokeIn(TileCoord at) {
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
    TransformPose? pose,
  }) => CompositeLeaf<CanvasStackRow>(
    CanvasLayerImageRequest(
      frameKey: key(id),
      opacity: 1,
      blendMode: blendMode,
      placement: pose == null ? null : placedBy(pose, canvasSize),
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
        case CompositeBackdropBlend(:final children):
          yield* requestsIn(children);
      }
    }
  }

  /// The rows' images, warmed at [level]'s quality — the one the view asks
  /// for there; a row it has to wait for arrives in the middle of a stroke.
  Future<LayerFrameImageCache> imagesFor(
    WidgetTester tester,
    List<CompositeNode<CanvasStackRow>> nodes, {
    int level = 0,
  }) async {
    final images = LayerFrameImageCache(frameStore: storeWithCels());
    addTearDown(images.dispose);
    for (final request in requestsIn(nodes)) {
      final warmed = await tester.runAsync(
        () => images.prepare(
          key: request.frameKey,
          canvasSize: canvasSize,
          quality: PlaybackQuality.forLevel(level),
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
  /// captured, and how many of its steps patched, drew their picture and
  /// were composed apart.
  Future<({List<Uint8List> screens, int patched, int pictures, int apart})>
  stroke(
    WidgetTester tester, {
    required CanvasViewport viewport,
    List<CompositeNode<CanvasStackRow>> below = const [],
    List<CompositeNode<CanvasStackRow>>? nodes,
    List<BitmapSurfacePainter>? painters,
    ProjectBackground background = paper,
    bool paintPaper = true,
  }) async {
    final all = nodes ?? [...below, activeRow];
    final images = await imagesFor(
      tester,
      all,
      level: displayLevelOf(
        displayScaleOf(viewport.zoom, tester.view.devicePixelRatio),
      ),
    );
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
      apart: buffers.composedApartCount,
    );
  }

  /// The same stroke with the head rastered at every step — the screens
  /// the pictures must reproduce.
  Future<List<Uint8List>> strokeByHeads(
    WidgetTester tester, {
    required CanvasViewport viewport,
    List<CompositeNode<CanvasStackRow>> below = const [],
    List<CompositeNode<CanvasStackRow>>? nodes,
  }) async {
    debugDrawBufferPictures = false;
    try {
      final made = await stroke(
        tester,
        viewport: viewport,
        below: below,
        nodes: nodes,
      );
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

    // ↩️Through an advanced blend these rastered their heads, every step,
    // while a row composed over its backdrop never drew its picture — the
    // stroke under one included, whose step composes the row again.
    // The trees as the plan hands them over: each row in an advanced blend
    // already composed over what lies below it in its scope.
    CompositeNode<CanvasStackRow> folder(CompositeNode<CanvasStackRow> child) =>
        CompositeGroup<CanvasStackRow>(
          children: [child],
          opacity: 1,
          blendMode: LayerBlendMode.normal,
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
    final throughABlend = <String, List<CompositeNode<CanvasStackRow>>>{
      'the live row through multiply': [
        blended(activeRow, LayerBlendMode.multiply),
      ],
      'over a row through multiply': [
        blended(row('below'), LayerBlendMode.multiply),
        activeRow,
      ],
      'under a row through linear burn': [
        blended(
          row('aside'),
          LayerBlendMode.linearBurn,
          over: [row('below'), activeRow],
        ),
      ],
      'over a folder through multiply': [
        blended(folder(row('below')), LayerBlendMode.multiply),
        activeRow,
      ],
      'over a folder holding a row through multiply': [
        folder(blended(row('below'), LayerBlendMode.multiply)),
        activeRow,
      ],
    };
    for (final MapEntry(key: scene, value: nodes) in throughABlend.entries) {
      testWidgets(scene, (tester) async {
        useView(tester);
        final viewport = CanvasViewport(zoom: 2, panX: -40, panY: -60);
        final drawn = await stroke(tester, viewport: viewport, nodes: nodes);
        expect(drawn.pictures, steps, reason: 'a step rastered its head');
        expectSameScreens(
          drawn.screens,
          await strokeByHeads(tester, viewport: viewport, nodes: nodes),
        );
      });
    }
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

    testWidgets('over a posed row', (tester) async {
      await expectHeads(
        tester,
        below: [
          row(
            'below',
            pose: TransformPose(center: CanvasPoint(x: 130, y: 128)),
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

    // ↩️'with a stamp ghost on the layer' was pinned here: the painter's
    // ghost was drawn where the pointer was, off the texel grid, so a step
    // with one rastered its head. Since brush-fidelity-Q9 (유저 2026-10-18
    // 「통일하면 좋음」) the ghost is the overlay's tiles, on the grid.

    testWidgets('on iOS, whose screen is wide-gamut', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await expectHeads(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  // 🚨★★★F-287: a step over a stack holding a blend that is not in place is
  // composed APART. On the Windows app the clip such a step stood on did
  // not hold the blend, which was laid over the carried pixels once more
  // on every patch (the paint pass's `_recomposeOverCarried` has the
  // measurement). This engine's clip holds, so what is pinned here is the
  // route — every patch goes apart, and only such a stack's — and that the
  // route lays down the bytes the clip did.
  group('F-287 — a step through a blend that is not in place is composed '
      'apart, and lays the bytes the clip did', () {
    const multiplied = LayerBlendMode.multiply;
    // The user's: two rows in multiply, a normal row drawn on above.
    final usersStack = <CompositeNode<CanvasStackRow>>[
      row('below', blendMode: multiplied),
      row('aside', blendMode: multiplied),
      activeRow,
    ];
    final stacks = <String, List<CompositeNode<CanvasStackRow>>>{
      'two rows in multiply under the live row': usersStack,
      'the live row itself in screen': [
        row('below'),
        const CompositeLeaf<CanvasStackRow>(
          CanvasActiveLayerRow(opacity: 1, blendMode: LayerBlendMode.screen),
        ),
      ],
      'a folder in overlay': [
        CompositeGroup<CanvasStackRow>(
          children: [row('below')],
          opacity: 1,
          blendMode: LayerBlendMode.overlay,
        ),
        activeRow,
      ],
      'a row in multiply inside a normal folder': [
        CompositeGroup<CanvasStackRow>(
          children: [row('below', blendMode: multiplied)],
          opacity: 1,
          blendMode: LayerBlendMode.normal,
        ),
        activeRow,
      ],
      'a row in multiply under an adjustment': [
        CompositeAdjustment<CanvasStackRow>(
          children: [row('below', blendMode: multiplied)],
          effects: [
            ResolvedLayerEffect(
              kind: EffectKind.brightnessContrast,
              values: const [20, 15],
            ),
          ],
          mix: 1,
        ),
        activeRow,
      ],
    };
    final views = <String, (CanvasViewport, bool)>{
      '100%': (CanvasViewport(), true),
      // Below 100% the buffer is a level image: the region composed apart
      // lands 1:1 only if it is drawn at the buffer's own scale.
      '50%': (CanvasViewport(zoom: 0.5), true),
      // Translucent where nothing is drawn: a blit that blended instead of
      // replacing would lay the step over its own previous frame.
      '100%, no paper': (CanvasViewport(), false),
    };

    Future<void> expectApart(
      WidgetTester tester, {
      required List<CompositeNode<CanvasStackRow>> nodes,
      required CanvasViewport viewport,
      bool paintPaper = true,
      List<BitmapSurfacePainter>? painters,
    }) async {
      useView(tester);
      final apart = await stroke(
        tester,
        viewport: viewport,
        nodes: nodes,
        painters: painters,
        paintPaper: paintPaper,
      );
      expect(
        apart.patched,
        greaterThanOrEqualTo(steps),
        reason: 'the steps did not patch, so nothing here was compared',
      );
      expect(apart.apart, apart.patched, reason: 'a patch stood on its clip');
      debugRecomposeApart = false;
      try {
        final clipped = await stroke(
          tester,
          viewport: viewport,
          nodes: nodes,
          painters: painters,
          paintPaper: paintPaper,
        );
        expect(clipped.apart, 0, reason: 'the reference went apart');
        expectSameScreens(apart.screens, clipped.screens);
      } finally {
        debugRecomposeApart = true;
      }
    }

    for (final MapEntry(key: stack, value: nodes) in stacks.entries) {
      for (final MapEntry(key: at, value: (viewport, paintPaper))
          in views.entries) {
        testWidgets('$stack, at $at', (tester) async {
          await expectApart(
            tester,
            nodes: nodes,
            viewport: viewport,
            paintPaper: paintPaper,
          );
        });
      }
    }

    // ↩️'a stamp ghost on the live row, whatever the rows wear' was pinned
    // here (10-19): the painter drew the ghost in the stamp's composite
    // mode, a blend not in place. Since brush-fidelity-Q9 (유저 2026-10-18
    // 「통일하면 좋음」) the ghost is the overlay's pre-blended tiles and
    // draws in no blend, so the stroke's own cases above are its cases.

    // A region composed apart is an image of what it is given, and a step's
    // dirty rect is the live tiles it changed — which reach past the view.
    testWidgets('a step that changes only what lies past the view composes '
        'nothing apart: the region is held to the buffer', (tester) async {
      useView(tester);
      // At 200% the view holds the canvas's top-left quarter; the stroke
      // is in its bottom-right tile, a tile away from it.
      final made = await stroke(
        tester,
        viewport: CanvasViewport(zoom: 2),
        nodes: usersStack,
        painters: strokeIn(TileCoord(x: 3, y: 3)),
      );
      expect(
        made.patched,
        greaterThanOrEqualTo(steps),
        reason: 'the steps did not patch, so nothing here was asked',
      );
      expect(made.apart, 0, reason: 'a step composed apart past the buffer');
    });

    testWidgets('…and a stack that blends in place stands on its clip, its '
        'steps still drawn as their pictures', (tester) async {
      useView(tester);
      final made = await stroke(
        tester,
        viewport: CanvasViewport(),
        below: [row('below'), row('aside')],
      );
      expect(made.patched, greaterThanOrEqualTo(steps));
      expect(made.apart, 0);
      expect(made.pictures, steps);
    });
  });

  // 🚨A dab's tile is not where a POSED live row shows it. The row's
  // placement lays the tile somewhere else, so a step patched over the
  // tile's own rect repaints where nothing changed and leaves the stroke
  // out.
  testWidgets('a POSED live row shows each step where the row lies — every '
      'screen is the one a first paint of that step makes', (tester) async {
    useView(tester);
    // 80 to the right: the tile the stroke is in, 64..128 across, shows
    // over 144..208 — clear of itself.
    const right = 80;
    final posed = [
      CompositeLeaf<CanvasStackRow>(
        CanvasActiveLayerRow(
          opacity: 1,
          placement: placedBy(
            TransformPose(center: CanvasPoint(x: 128.0 + right, y: 128)),
            canvasSize,
          ),
        ),
      ),
    ];
    final made = await stroke(tester, viewport: CanvasViewport(), nodes: posed);

    final images = await imagesFor(tester, posed);
    final first = <Uint8List>[];
    await tester.runAsync(() async {
      for (var step = 1; step <= steps; step += 1) {
        final buffers = DisplayBufferCache();
        addTearDown(buffers.dispose);
        await paint(
          tester,
          buffers: buffers,
          images: images,
          nodes: posed,
          surface: onPaper[step],
          viewport: CanvasViewport(),
          background: paper,
          paintPaper: true,
        );
        first.add(await capture());
      }
    });

    final width = view.width.toInt();
    for (var step = 1; step <= steps; step += 1) {
      final screen = made.screens[step - 1];
      // Step i's pixel, where the stroke put it in its tile at (1, 1).
      final at = ((64 + 10 + step) * width + 64 + 3 + step * 4 + right) * 4;
      const paperAt = (250 * 256 + 250) * 4;
      expect(
        screen.sublist(at, at + 4),
        isNot(screen.sublist(paperAt, paperAt + 4)),
        reason: 'step $step: its pixel is not on the screen',
      );
      expect(
        listEquals(screen, first[step - 1]),
        isTrue,
        reason: 'step $step is not what a first paint of it shows',
      );
    }
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
