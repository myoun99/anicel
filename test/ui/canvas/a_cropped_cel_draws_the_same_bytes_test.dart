import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart' as model;
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/colour_key_shader.dart';
import 'package:anicel/src/ui/canvas/display_resample.dart';
import 'package:anicel/src/ui/canvas/layer_image_draw.dart';
import 'package:anicel/src/ui/playback/cut_frame_composite_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨★★★A CEL STORED AS ITS INK PUTS THE SAME BYTES ON SCREEN AS THE WHOLE
/// IMAGE DID (유저 2026-09-23: 「1/4해상도같은 결과바뀌는건 절대로
/// 허용안하고 … 보이는 결과 특히」; 09-24: 「남는경우같은것도 최대한 결과
/// 안바뀌는선에서」).
///
/// Every scene is rendered twice through the real editing stack — once with
/// the cache keeping every image whole, as it did before
/// (`debugStoresWholeContent`), once keeping the ink alone wherever the row
/// draws exactly from it (`inkCropDrawsTheSame`) — and the two screens must
/// match byte for byte. The scenes are the ways ink could show: inside the
/// canvas, on its left and top edge (where the ink and the whole image share
/// an edge), by the right and bottom edges of a canvas off the halving grid
/// (150×101), on the pasteboard, scattered to both ends; through `srcOver`
/// and `plus` (stored as ink) and through the advanced blends, poses and a
/// blur (kept whole), keyed, tinted, inside folders, around the active
/// layer; at every level of the display, and on the direct walk, which lays
/// the whole image back.
///
/// ⚠️CAPTURED THROUGH `toImageSync`, and that is not a convenience. The walk
/// lays a whole image back as a deferred image, which the test runner (Skia)
/// makes RGBA while a snapshot is its native N32 (`picture.cc`
/// `CreateDeferredImage` · `snapshot_controller_skia.cc`), and onto an N32
/// target Skia blends an N32 image at 1:1 through a legacy blitter that
/// rounds `srcOver` one way and everything else through its pipeline another
/// — ±1 that exists only in this runner. On Impeller both are the same
/// texture. An RGBA capture sends every image through the one pipeline, so
/// what this compares is the storage and not a blitter's rounding.
///
/// ⚠️The draw counters say both arms of the lay-down ran — a pin whose
/// scenes never drew ink, or never laid a whole image back, would be green
/// about nothing.
void main() {
  const tile = 16;
  const canvasSize = CanvasSize(width: 150, height: 101);
  const view = Size(176, 128);
  final screenKey = GlobalKey();

  setUpAll(ColourKeyShader.load);

  BrushFrameKey key(String id) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(id),
    frameId: FrameId('$id-f'),
  );

  BrushDab dab(double x, double y, int color, int sequence) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: color,
    size: 9,
    opacity: 1,
    flow: 1,
    hardness: 0.4,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
  );

  /// Where each cel's ink is. Tiles are 16: [interior] is a block in the
  /// middle, [leftTop] shares the canvas's left and top edges with the whole
  /// image, [rightBottom] reaches tiles past the canvas's odd edges,
  /// [pasteboard] has ink off the canvas on both sides, [sparse] spans the
  /// canvas corner to corner, [inner] keeps to the canvas's middle.
  const cels = <String, (int, List<(double, double)>)>{
    'interior': (0xFF2040C0, [(60, 44), (72, 52), (66, 60)]),
    'leftTop': (0xFFE04020, [(1, 1), (4, 30), (18, 3)]),
    'rightBottom': (0xFF20A060, [(147, 98), (131, 100), (149, 84)]),
    'pasteboard': (0xFFA020C0, [(-9, 20), (-3, 26), (158, 60), (166, 66)]),
    'sparse': (0xFFF0C020, [(8, 9), (141, 93)]),
    'inner': (0xFF308090, [(90, 30), (100, 70)]),
    'active': (0xFF101010, [(40, 70), (110, 20)]),
  };

  BrushFrameStore storeWithCels([CanvasSize size = canvasSize]) {
    final store = BrushFrameStore();
    for (final MapEntry(key: id, value: (color, points)) in cels.entries) {
      BrushFrameEditingCoordinator(
        initialFrameKey: key(id),
        frameStore: store,
        sessionStore: BrushFrameEditSessionStore(
          canvasSize: size,
          tileSize: tile,
        ),
        historyPolicy: const BrushHistoryPolicy(),
      ).commitSourceStroke(
        sourceDabs: [
          for (var i = 0; i < points.length; i += 1)
            dab(points[i].$1, points[i].$2, color, i),
        ],
      );
    }
    return store;
  }

  CompositeNode<CanvasStackRow> row(
    String id, {
    double opacity = 1,
    LayerBlendMode blendMode = LayerBlendMode.normal,
    CameraPose? pose,
    int? tint,
    List<ResolvedLayerEffect> effects = const [],
  }) => CompositeLeaf<CanvasStackRow>(
    CanvasLayerImageRequest(
      frameKey: key(id),
      opacity: opacity,
      blendMode: blendMode,
      pose: pose,
      tint: tint,
      effects: effects,
    ),
  );

  ResolvedLayerEffect effect(EffectKind kind, List<double> values) =>
      ResolvedLayerEffect(kind: kind, values: values);

  final center = CanvasPoint(x: 75, y: 50.5);

  final scenes = <String, List<CompositeNode<CanvasStackRow>>>{
    'ink rows through normal and add': [
      row('interior'),
      row('leftTop', opacity: 0.8),
      row('rightBottom', opacity: 0.7, blendMode: LayerBlendMode.add),
      row('pasteboard'),
      row('sparse', opacity: 0.5),
    ],
    'whole rows through the advanced blends': [
      row('interior', blendMode: LayerBlendMode.multiply),
      row('leftTop', opacity: 0.8, blendMode: LayerBlendMode.screen),
      row('rightBottom', blendMode: LayerBlendMode.overlay),
      row('pasteboard', opacity: 0.5, blendMode: LayerBlendMode.difference),
      row('sparse', blendMode: LayerBlendMode.darken),
    ],
    'ink and whole rows over each other': [
      row('pasteboard'),
      row('interior', blendMode: LayerBlendMode.multiply),
      row('leftTop', opacity: 0.8),
      row('rightBottom', opacity: 0.7, blendMode: LayerBlendMode.screen),
      row('sparse', opacity: 0.5, blendMode: LayerBlendMode.add),
    ],
    'posed rows': [
      row('interior', pose: CameraPose(center: CanvasPoint(x: 78, y: 48.5))),
      row(
        'leftTop',
        pose: CameraPose(center: CanvasPoint(x: 75.5, y: 50.75)),
      ),
      row(
        'rightBottom',
        pose: CameraPose(center: center, rotationDegrees: 15),
      ),
      row('pasteboard', pose: CameraPose(center: center, zoom: 0.6)),
      row('sparse'),
    ],
    'effects: blur, colour, a key at the head, a key after colour': [
      row('interior', effects: [effect(EffectKind.blur, [3, 3])]),
      row(
        'leftTop',
        effects: [effect(EffectKind.brightnessContrast, [20, 15])],
      ),
      row(
        'rightBottom',
        effects: [effect(EffectKind.hueSaturation, [30, 20, 0])],
      ),
      row(
        'pasteboard',
        effects: [effect(EffectKind.deleteColor, [160, 32, 192, 40, 100])],
      ),
      row(
        'sparse',
        effects: [
          effect(EffectKind.brightnessContrast, [10, 0]),
          effect(EffectKind.keepColor, [240, 192, 32, 60, 100]),
        ],
      ),
    ],
    'onion tints': [
      row('interior', tint: 0xFFFF0000, opacity: 0.6),
      row('leftTop', tint: 0xFF0000FF),
      row('pasteboard', tint: 0xFF00FF00, opacity: 0.4),
    ],
    // ⚠️The blurred folder holds only ink that keeps off the canvas's
    // edges: a blurred folder reaching past the composite trips the paint
    // pass's own assertion whatever the cache stores — board
    // `a-blurred-folder-outgrows-the-composite`, not this pin's finding.
    'folders with a blend and a blur': [
      CompositeGroup<CanvasStackRow>(
        children: [row('interior'), row('inner', opacity: 0.6)],
        opacity: 0.7,
        blendMode: LayerBlendMode.multiply,
        effects: [effect(EffectKind.blur, [2, 2])],
      ),
      CompositeGroup<CanvasStackRow>(
        children: [row('rightBottom'), row('leftTop')],
        opacity: 1,
        blendMode: LayerBlendMode.screen,
      ),
      row('pasteboard'),
    ],
    'around the active layer': [
      row('interior'),
      row('leftTop', blendMode: LayerBlendMode.multiply),
      CompositeLeaf<CanvasStackRow>(
        CanvasActiveLayerRow(opacity: 1, frameKey: key('active')),
      ),
      row('rightBottom', opacity: 0.8),
      row('pasteboard', blendMode: LayerBlendMode.screen),
      row('sparse'),
    ],
  };

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

  bool hasActiveRow(List<CompositeNode<CanvasStackRow>> nodes) => nodes.any(
    (node) =>
        node is CompositeLeaf<CanvasStackRow> &&
        node.payload is CanvasActiveLayerRow,
  );

  /// The stack's screen for [nodes], the cache keeping whole images or the
  /// ink — every row warmed first, the way the view will ask for it, so the
  /// first build adopts them all.
  Future<({Uint8List bytes, LayerFrameImageCache images})> screen(
    WidgetTester tester, {
    required bool whole,
    required List<CompositeNode<CanvasStackRow>> nodes,
    required CanvasViewport viewport,
    required bool walk,
  }) async {
    final store = storeWithCels();
    final images = LayerFrameImageCache(frameStore: store)
      ..debugStoresWholeContent = whole;
    final quality = PlaybackQuality.forLevel(
      displayLevelOf(displayScaleOf(viewport.zoom, 1)),
    );
    for (final request in requestsIn(nodes)) {
      final warmed = await tester.runAsync(
        () => images.prepare(
          key: request.frameKey,
          canvasSize: canvasSize,
          quality: quality,
          sourceEffects: request.sourceEffects,
          inkSuffices: request.inkSuffices,
        ),
      );
      expect(warmed, isNotNull, reason: 'fixture: ${request.frameKey}');
    }
    final active = hasActiveRow(nodes)
        ? BitmapSurfacePainter(
            surface: BrushFrameDisplayCacheService(
              frameStore: store,
              canvasSize: canvasSize,
            ).prepareFramePreview(key('active')).previewSurface,
            showTransparentBackground: false,
            lineage: 'a-cropped-cel',
          )
        : null;
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: screenKey,
              child: ClipRect(
                child: SizedBox(
                  width: view.width,
                  height: view.height,
                  child: CanvasLayerStackView(
                    nodes: nodes,
                    imageCache: images,
                    canvasSize: canvasSize,
                    viewport: viewport,
                    activeSurfacePainter: active,
                    paintPaper: true,
                    paperBackground: const ProjectBackground.color(0xFFF4EEE0),
                    debugDisableSingleBuffer: walk,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final render =
        screenKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = render.toImageSync();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return (bytes: bytes!, images: images);
  }

  final viewports = <String, CanvasViewport>{
    'level 0 (100%)': CanvasViewport(zoom: 1, panX: 18, panY: 12),
    'level 1 (50%)': CanvasViewport(zoom: 0.5, panX: 30, panY: 20),
    'level 2 (25%)': CanvasViewport(zoom: 0.25, panX: 40, panY: 30),
    'level 1 with a residual (37%)': CanvasViewport(
      zoom: 0.37,
      panX: 33,
      panY: 21,
    ),
    'rotated 20° at 71%': CanvasViewport(
      zoom: 0.71,
      panX: 60,
      panY: -10,
      rotationDegrees: 20,
    ),
    'magnified 230%': CanvasViewport(zoom: 2.3, panX: -40, panY: -30),
  };

  /// Where a byte pair differs, the first few.
  ({int count, List<String> where}) compare(Uint8List a, Uint8List b) {
    var count = 0;
    final where = <String>[];
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        count += 1;
        if (where.length < 6) {
          final pixel = i ~/ 4;
          where.add(
            '(${pixel % view.width.toInt()},${pixel ~/ view.width.toInt()})'
            'c${i % 4} ${a[i]}→${b[i]}',
          );
        }
      }
    }
    return (count: count, where: where);
  }

  // Magnified, the blurred folder's buffer reaches past the little of the
  // canvas on screen and the paint pass asserts before either arm has drawn
  // — the old arm included.
  String? skipFor(String scene, String viewport) =>
      scene == 'folders with a blend and a blur' && viewport == 'magnified 230%'
      ? 'board a-blurred-folder-outgrows-the-composite'
      : null;

  for (final scene in scenes.entries) {
    for (final viewport in viewports.entries) {
      for (final walk in [false, true]) {
        final route = walk ? 'the direct walk' : 'the display buffer';
        final name = '${scene.key} · ${viewport.key} · $route';
        final skip = skipFor(scene.key, viewport.key);
        if (skip != null) {
          test(name, () {}, skip: skip);
          continue;
        }
        testWidgets(name, (tester) async {
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetDevicePixelRatio);
          final old = await screen(
            tester,
            whole: true,
            nodes: scene.value,
            viewport: viewport.value,
            walk: walk,
          );
          addTearDown(old.images.dispose);
          debugCropsLaidDown = 0;
          debugWholesLaidBack = 0;
          final ink = await screen(
            tester,
            whole: false,
            nodes: scene.value,
            viewport: viewport.value,
            walk: walk,
          );
          addTearDown(ink.images.dispose);
          final moved = compare(old.bytes, ink.bytes);
          expect(
            moved.count,
            0,
            reason:
                'the ink is memory only — not one byte of the screen may '
                'move ($debugCropsLaidDown ink draws, $debugWholesLaidBack '
                'laid back whole) at ${moved.where}',
          );
        });
      }
    }
  }

  testWidgets('both arms ran: the buffer draws ink rows from their ink, the '
      'walk lays them back whole, and the advanced blends and poses keep '
      'their images whole', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final at50 = CanvasViewport(zoom: 0.5, panX: 30, panY: 20);

    debugCropsLaidDown = 0;
    debugWholesLaidBack = 0;
    final inkRows = await screen(
      tester,
      whole: false,
      nodes: scenes['ink rows through normal and add']!,
      viewport: at50,
      walk: false,
    );
    addTearDown(inkRows.images.dispose);
    expect(debugCropsLaidDown, greaterThan(0));
    expect(debugWholesLaidBack, 0);
    final interior = inkRows.images.validImageOrNull(
      key('interior'),
      PlaybackQuality.half,
      canvasSize: canvasSize,
      sourceEffects: const [],
    );
    expect(interior?.isInk, isTrue, reason: 'a normal row keeps its ink');

    // The anchor under every comparison above: the old arm really is whole.
    // Were the hatch to stop holding, both arms would store ink and every
    // one of them would pass comparing a thing with itself.
    final wholeRows = await screen(
      tester,
      whole: true,
      nodes: scenes['ink rows through normal and add']!,
      viewport: at50,
      walk: false,
    );
    addTearDown(wholeRows.images.dispose);
    expect(
      wholeRows.images
          .validImageOrNull(
            key('interior'),
            PlaybackQuality.half,
            canvasSize: canvasSize,
            sourceEffects: const [],
          )
          ?.isInk,
      isFalse,
    );

    debugCropsLaidDown = 0;
    debugWholesLaidBack = 0;
    final walked = await screen(
      tester,
      whole: false,
      nodes: scenes['ink rows through normal and add']!,
      viewport: at50,
      walk: true,
    );
    addTearDown(walked.images.dispose);
    expect(debugWholesLaidBack, greaterThan(0));
    expect(debugCropsLaidDown, 0);

    for (final name in [
      'whole rows through the advanced blends',
      'posed rows',
    ]) {
      debugCropsLaidDown = 0;
      debugWholesLaidBack = 0;
      final shot = await screen(
        tester,
        whole: false,
        nodes: scenes[name]!,
        viewport: at50,
        walk: false,
      );
      addTearDown(shot.images.dispose);
      final kept = shot.images.validImageOrNull(
        key('interior'),
        PlaybackQuality.half,
        canvasSize: canvasSize,
        sourceEffects: const [],
      );
      expect(kept?.isInk, isFalse, reason: '$name keep the whole image');
      expect(debugWholesLaidBack, 0, reason: name);
    }
  });

  // 🚨AT A WORKING SIZE, where the halving is not exact on every engine.
  // Impeller Vulkan samples each 2×2 block a little off its middle once an
  // image is a few hundred texels wide (🔬off the exact mean at 1,933
  // channels of a 585×414 image, 51,545 of a 2340×1654 one). That moves the
  // weights of a block's four texels, never which four, so a block outside
  // the ink still halves to nothing and the cut loses no trace — which is
  // what this says with bytes: ink stops at tile edges on all four sides,
  // the lay-back puts the cut level on a transparent raster the whole
  // level's size, and it must be that level exactly. (A cut one texel wider
  // "for the drift" was tried and measured unnecessary on Vulkan here.)
  testWidgets('a level cut out of the whole image lays back to the same '
      'bytes — at a working size, ink stopping at tile edges', (tester) async {
    const big = CanvasSize(width: 1172, height: 828);
    final store = BrushFrameStore();
    BrushFrameEditingCoordinator(
      initialFrameKey: key('big'),
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: big,
        tileSize: 256,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    ).commitSourceStroke(
      sourceDabs: [
        // Up to x 512 and y 512 from inside, and from x 256 / y 256 on.
        for (final (i, (x, y)) in const [
          (509.0, 300.0),
          (509.0, 420.0),
          (259.0, 380.0),
          (400.0, 259.0),
          (330.0, 509.0),
          (470.0, 470.0),
        ].indexed)
          BrushDab(
            center: CanvasPoint(x: x, y: y),
            color: 0xFF101060,
            size: 6,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: i,
          ),
      ],
    );
    await tester.runAsync(() async {
      for (final quality in [PlaybackQuality.half, PlaybackQuality.quarter]) {
        final whole = LayerFrameImageCache(frameStore: store)
          ..debugStoresWholeContent = true;
        final ink = LayerFrameImageCache(frameStore: store);
        Future<LayerFrameImage> level(LayerFrameImageCache cache) async =>
            (await cache.prepare(
              key: key('big'),
              canvasSize: big,
              quality: quality,
              sourceEffects: const [],
              inkSuffices: true,
            ))!;
        final w = await level(whole);
        final c = await level(ink);
        expect(c.isInk, isTrue, reason: 'fixture: $quality stored the ink');
        final step = (1 << quality.level).toDouble();
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawImage(
          c.image,
          (c.worldRect.topLeft - c.extent.topLeft) / step,
          ui.Paint()..filterQuality = ui.FilterQuality.none,
        );
        final picture = recorder.endRecording();
        final laid = await picture.toImage(w.image.width, w.image.height);
        picture.dispose();
        Future<Uint8List> bytes(ui.Image image) async =>
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        final a = await bytes(w.image);
        final b = await bytes(laid);
        var differing = 0;
        for (var i = 0; i < a.length; i += 1) {
          if (a[i] != b[i]) {
            differing += 1;
          }
        }
        expect(differing, 0, reason: '$quality');
        laid.dispose();
        whole.dispose();
        ink.dispose();
      }
    });
  });

  // The composite rasters at the tier's size, which is the canvas's rounded:
  // on a canvas whose sides divide by four every tier lays each image down
  // texel for texel and draws the ink as it is; on 150×101 a quarter is
  // 38/150 of the canvas, not a quarter, every draw resamples, and the ink
  // is laid back whole. Both roads, and both the same bytes as the whole.
  for (final (size, copiesEveryTier) in const [
    (CanvasSize(width: 152, height: 104), true),
    (canvasSize, false),
  ]) {
    testWidgets('the playback composite composes the same bytes from the ink '
        '— ${size.width}×${size.height}', (tester) async {
      BrushFrameKey frameKeyOf(Cut cut, LayerId layerId, FrameId frameId) =>
          BrushFrameKey(
            projectId: const ProjectId('p'),
            trackId: const TrackId('t'),
            cutId: cut.id,
            layerId: layerId,
            frameId: frameId,
          );
      model.Layer layer(
        String id, {
        double opacity = 1,
        LayerBlendMode blendMode = LayerBlendMode.normal,
      }) => model.Layer(
        id: LayerId(id),
        name: id,
        frames: [Frame(id: FrameId('$id-f'), duration: 1, strokes: const [])],
        timeline: {0: TimelineExposure.drawing(FrameId('$id-f'), length: 1)},
        opacity: opacity,
        blendMode: blendMode,
      );
      final cut = Cut(
        id: const CutId('c'),
        name: 'cut',
        duration: 1,
        canvasSize: size,
        layers: [
          layer('pasteboard'),
          layer('interior', blendMode: LayerBlendMode.multiply),
          layer('leftTop', opacity: 0.8),
          layer('rightBottom', opacity: 0.7, blendMode: LayerBlendMode.screen),
          layer('sparse', opacity: 0.5, blendMode: LayerBlendMode.add),
          layer('inner'),
        ],
      );
      final store = storeWithCels(size);
      await tester.runAsync(() async {
        for (final quality in PlaybackQuality.values) {
          Future<Uint8List> composed({required bool whole}) async {
            final images = LayerFrameImageCache(frameStore: store)
              ..debugStoresWholeContent = whole;
            final cache = CutFrameCompositeCache(
              layerImages: images,
              frameStore: store,
              frameKeyOf: frameKeyOf,
            );
            final image = await cache.prepareComposite(
              cut: cut,
              frameIndex: 0,
              quality: quality,
            );
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            cache.dispose();
            images.dispose();
            return data!.buffer.asUint8List();
          }

          final old = await composed(whole: true);
          debugCropsLaidDown = 0;
          debugWholesLaidBack = 0;
          final ink = await composed(whole: false);
          final copied = copiesEveryTier || quality != PlaybackQuality.quarter;
          expect(
            copied ? debugCropsLaidDown : debugWholesLaidBack,
            greaterThan(0),
            reason: 'fixture: at $quality the ink was '
                '${copied ? 'drawn as it is' : 'laid back whole'}',
          );
          if (copiesEveryTier) {
            // The multiply and the screen rows asked for their whole images,
            // so nothing was stored as ink that had to be laid back.
            expect(debugWholesLaidBack, 0, reason: '$quality');
          }
          var differing = 0;
          for (var i = 0; i < old.length; i += 1) {
            if (old[i] != ink[i]) {
              differing += 1;
            }
          }
          expect(differing, 0, reason: '$quality');
        }
      });
    });
  }
}
