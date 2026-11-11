import 'dart:async';
import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/app_kernels_ahead.dart';
import 'package:anicel/src/native/engine_chain_holds.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/frame_demand.dart'
    show FrameGhosts;
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart'
    show PromotedStrokeTile;
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/media/viewer_page_loading.dart';
import 'package:anicel/src/ui/playback/engine_frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/frame_wait_mark.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart'
    show FramePictureKey;
import 'package:anicel/src/ui/widgets/still_raster.dart' show TickSceneLayer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart'
    show GpuComposite, debugKernelsCompiledHere;

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/a_plugin_that_shifts.dart';
import '../../helpers/a_shown_surface.dart';
import '../../helpers/an_effect_sampled.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// 🗣️I-132-Q34 a (유저 2026-10-30): 「머문다 — … 결과가 올 때까지 그
/// 프레임의 직전 완성 그림에 머문다」 — a canvas standing on a frame that
/// holds a plugin's step past a cel's own pixels never draws it as it
/// stands, where the step would be drawn as if off: what it shows is the
/// frame's picture, made waiting for the plugin, and a stroke's steps go
/// into it one patch at a time — a stroke shown late by the plugin's time.
/// Beside each, the same frame with no plugin, as it always was.
///
/// A frame whose effect chain's kernels are still to be compiled waits as
/// well (🗣️관제 2026-11-10 18:14, gpu-canonical-store ⑦: 「선 = UI 스레드가
/// 직접 하는 커널 컴파일 0개(시작 · S5 열기)」): the thread its frames are
/// built on compiles none of them — the screen stays on the picture it
/// showed while they are compiled off it, and shows the frame once they
/// are.
///
/// While a frame waits for the engine so — its tools still to be opened,
/// kernels still to be compiled — its place is marked (🗣️유저 2026-11-10,
/// gpu-canonical-store-Q12: 「캔버스 자리에 준비 중 표시를 둔다」); while it
/// waits for a plugin it is not.
void main() {
  const tileSize = defaultCelTileSize;
  // ⚠️Wide enough that a folder drawn whole with a plugin's reach on it
  // is held: none is past a page ([HeldSubtreeRasters]).
  const canvasSize = CanvasSize(width: 8 * tileSize, height: 8 * tileSize);
  const viewSize = Size(3.0 * tileSize, 2.5 * tileSize);
  const under = Color(0xFF203040);
  const stroke = [0x40, 0x00, 0x00, 0xFF];
  const ink = [0x00, 0x40, 0x00, 0xFF];
  const other = [0x00, 0x00, 0x40, 0xFF];
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('inked'),
    frameId: FrameId('f'),
  );
  const over = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('over'),
    frameId: FrameId('o'),
  );
  final cut = Cut(
    id: key.cutId,
    name: 'Cut',
    duration: 1,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: key.layerId,
        name: 'Inked',
        frames: [Frame(id: key.frameId, duration: 1, strokes: const [])],
        timeline: {0: TimelineExposure.drawing(key.frameId, length: 1)},
      ),
      Layer(
        id: over.layerId,
        name: 'Over',
        frames: [Frame(id: over.frameId, duration: 1, strokes: const [])],
        timeline: {0: TimelineExposure.drawing(over.frameId, length: 1)},
      ),
    ],
  );
  ResolvedLayerEffect aPlugin(ShiftingFxPlugin runner) => ResolvedLayerEffect(
    kind: EffectKind.plugin,
    plugin: shiftingFxPluginDescription,
    values: const [],
    run: fxPluginRunOf(runner),
  );
  const live = CompositeLeaf<CanvasStackRow>(
    CanvasActiveLayerRow(opacity: 1, frameKey: key),
  );

  /// The row a pen is on, in a folder whose chain is [effects].
  List<CompositeNode<CanvasStackRow>> inAFolder(
    List<ResolvedLayerEffect> effects,
  ) => [
    CompositeGroup<CanvasStackRow>(
      children: const [live],
      opacity: 1,
      blendMode: LayerBlendMode.normal,
      effects: effects,
    ),
  ];

  /// The row a pen is on, under a folder whose chain is [effects] holding
  /// another row, [over].
  List<CompositeNode<CanvasStackRow>> overThePen(
    List<ResolvedLayerEffect> effects,
  ) => [
    live,
    CompositeGroup<CanvasStackRow>(
      children: const [
        CompositeLeaf(CanvasLayerImageRequest(frameKey: over, opacity: 1)),
      ],
      opacity: 1,
      blendMode: LayerBlendMode.normal,
      effects: effects,
    ),
  ];

  group('a frame waits for its plugins', () {
    final runs = aPlugin(ShiftingFxPlugin(by: 1));
    final runsNot = ResolvedLayerEffect(
      kind: EffectKind.plugin,
      plugin: shiftingFxPluginDescription,
      values: const [],
    );
    test('where a folder\'s or an adjustment\'s chain, or a row\'s past its '
        'head, runs one — not where nothing runs it, nor at a cel\'s head', () {
      expect(waitsForItsPlugins(inAFolder([runs])), isTrue);
      expect(
        waitsForItsPlugins([
          CompositeAdjustment<CanvasStackRow>(
            children: const [live],
            effects: [runs],
            mix: 1,
          ),
        ]),
        isTrue,
      );
      final blur = ResolvedLayerEffect(kind: EffectKind.blur, values: [3]);
      for (final row in <CanvasStackRow>[
        CanvasActiveLayerRow(opacity: 1, frameKey: key, effects: [blur, runs]),
        CanvasLayerImageRequest(
          frameKey: key,
          opacity: 1,
          effects: [blur, runs],
        ),
      ]) {
        expect(
          waitsForItsPlugins([CompositeLeaf(row)]),
          isTrue,
          reason: '$row',
        );
      }

      expect(waitsForItsPlugins(inAFolder([runsNot])), isFalse);
      expect(waitsForItsPlugins(inAFolder([blur])), isFalse);
      expect(
        waitsForItsPlugins([
          CompositeLeaf(
            CanvasLayerImageRequest(frameKey: key, opacity: 1, effects: [runs]),
          ),
        ]),
        isFalse,
        reason: 'at a cel\'s head it runs over the cel\'s own pixels, as the '
            'cel is read',
      );
    });
  });

  /// A tile of [colour] wherever [inside] holds, clear elsewhere.
  BitmapTile tileOf(
    TileCoord coord,
    List<int> colour,
    bool Function(Offset at) inside,
  ) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var y = 0; y < tileSize; y += 1) {
      for (var x = 0; x < tileSize; x += 1) {
        final at = Offset(
          coord.x * tileSize + x + 0.5,
          coord.y * tileSize + y + 0.5,
        );
        if (inside(at)) {
          pixels.setRange(
            (y * tileSize + x) * 4,
            (y * tileSize + x) * 4 + 4,
            colour,
          );
        }
      }
    }
    return BitmapTile(size: tileSize, pixels: pixels);
  }

  /// A canvas standing on [nodes]' frame — its one row inked from a quarter
  /// of a tile to half of one, across and down, or its cel blank where
  /// [penOnABlankCel] — over [store]; what [screen] shows, the overlay its
  /// pen's steps are shown by, and a hand of the pen's row anew — on another
  /// frame's nodes where it is handed them, over another store's pictures
  /// where it is handed one. Where [parked], the frame is shown as the
  /// track stack shows a cut it parks on instead: whole, made where it is
  /// missed, nothing of it drawn live.
  Future<
    ({
      EngineFramePictureStore<FramePictureKey> store,
      FramePictureKey picture,
      ActiveStrokeOverlayModel overlay,
      Future<void> Function([
        List<CompositeNode<CanvasStackRow>>? nodes,
        EngineFramePictureStore<FramePictureKey>? laidBy,
      ])
      handAnew,
    })
  >
  standOn(
    WidgetTester tester,
    GlobalKey screen,
    List<CompositeNode<CanvasStackRow>> nodes, {
    EngineFramePictureStore<FramePictureKey>? laidBy,
    bool penOnABlankCel = false,
    bool parked = false,
  }) async {
    final cels = BrushFrameStore();
    keepInAFile(cels, {
      if (!penOnABlankCel)
        key: BitmapSurface(
          canvasSize: canvasSize,
          tileSize: tileSize,
          tiles: {
            TileCoord(x: 0, y: 0): tileOf(
              TileCoord(x: 0, y: 0),
              ink,
              (at) => const Rect.fromLTRB(
                tileSize / 4,
                tileSize / 4,
                tileSize / 2,
                tileSize / 2,
              ).contains(at),
            ),
          },
        ),
      over: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {
          TileCoord(x: 0, y: 1): tileOf(
            TileCoord(x: 0, y: 1),
            other,
            (at) => const Rect.fromLTRB(
              tileSize / 4,
              tileSize * 5 / 4,
              tileSize / 2,
              tileSize * 3 / 2,
            ).contains(at),
          ),
        },
      ),
    });
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    BitmapSurface thePensCel() => BrushFrameDisplayCacheService(
      frameStore: cels,
      canvasSize: canvasSize,
    ).prepareFramePreview(key).previewSurface;
    // Pre-blended on its cel, as every stroke of the app's is: a step's
    // tile is the row's own where it lands, on the engine's screen too.
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = thePensCel();
    addTearDown(overlay.dispose);
    BitmapSurfacePainter aPainter() => BitmapSurfacePainter(
      surface: thePensCel(),
      overlayModel: overlay,
      showTransparentBackground: false,
      lineage: 'a-frame-that-waits-${nodes.hashCode}',
    );
    final store = laidBy ?? aStoreOfPictures();
    addTearDown(store.dispose);
    var standing = nodes;
    StackRun runBy(EngineFramePictureStore<FramePictureKey> store) => runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => standing,
    );
    var run = runBy(store);
    final shown = (
      cut: cut,
      frameIndex: 0,
      paintPaper: false,
      ghosts: FrameGhosts.none,
    );
    // The pasteboard left of the page in view.
    final viewport = CanvasViewport(panX: tileSize / 2, panY: tileSize / 4);
    Future<void> standWith(BitmapSurfacePainter painter) => tester.pumpWidget(
      onAScreen(
        screen,
        size: viewSize,
        under: under,
        view: parked
            ? FramePictureView(
                run: run,
                picture: shown,
                nodes: standing,
                viewport: viewport,
                laysWhatItMisses: true,
              )
            : standingOn(
                run,
                picture: shown,
                nodes: standing,
                viewport: viewport,
                live: (
                  activeSurfacePainter: painter,
                  floatOverlay: null,
                  liftedRows: const {},
                ),
              ),
      ),
    );
    await standWith(aPainter());
    return (
      store: store,
      picture: run.pictures.keyOfStack(nodes, shown),
      overlay: overlay,
      handAnew: ([nodes, laidBy]) {
        standing = nodes ?? standing;
        if (laidBy != null) {
          run = runBy(laidBy);
        }
        return standWith(aPainter());
      },
    );
  }

  /// A step of the pen over the tile at [coord].
  Future<void> aStep(
    WidgetTester tester,
    ActiveStrokeOverlayModel overlay,
    TileCoord coord,
  ) async {
    overlay.showResultTiles([
      PromotedStrokeTile(coord, tileOf(coord, stroke, (_) => true), 1),
    ]);
    await tester.pump();
  }

  bool onlyTheScreen(Shot shot) {
    for (var at = 0; at < shot.rgba.length; at += 4) {
      if (Color.fromARGB(
            shot.rgba[at + 3],
            shot.rgba[at],
            shot.rgba[at + 1],
            shot.rgba[at + 2],
          ) !=
          under) {
        return false;
      }
    }
    return true;
  }

  /// The mark a place stands while a frame shown in it waits for the engine
  /// ([FrameWaitMark]) — stood for the test that asks, as the app stands it
  /// (`flutter_test_config.dart` says why the corpus does not).
  final theMark = find.byType(ViewerPageLoading);
  void theMarkStands() {
    FrameWaitMark.debugStands = true;
    addTearDown(() => FrameWaitMark.debugStands = false);
  }

  /// The frames a place's word is heard after, and its mark built or taken
  /// down in — and the one the mark's last turn had asked for.
  Future<void> theMarkFollows(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  for (final (name, waits) in [
    ('waits for a plugin', true),
    ('runs none', false),
  ]) {
    List<CompositeNode<CanvasStackRow>> nodesOf() =>
        inAFolder(waits ? [aPlugin(ShiftingFxPlugin(by: 2))] : const []);

    testWidgets('a frame that $name, its picture not there yet: '
        '${waits ? 'nothing drawn as it stands' : 'drawn as it stands'}, '
        'and its place not marked', (tester) async {
      theMarkStands();
      final screen = GlobalKey();
      final nodes = nodesOf();
      expect(waitsForItsPlugins(nodes), waits, reason: '⛔premise');
      final store = StoreLayingNothing();
      await itsToolsOpen(tester, store);
      await standOn(tester, screen, nodes, laidBy: store);
      await tester.pump();

      expect(onlyTheScreen(await shotOf(tester, screen)), waits);
      // 🗣️관제 2026-11-10 23:05: the mark is of the engine's getting ready,
      // and a plugin's result is not that.
      await theMarkFollows(tester);
      expect(theMark, findsNothing);
    });
  }

  /// A canvas standing on a frame that waits for a plugin, its picture
  /// made, over [store].
  Future<
    ({
      ActiveStrokeOverlayModel overlay,
      Future<void> Function([List<CompositeNode<CanvasStackRow>>? nodes])
      handAnew,
    })
  >
  standingMade(WidgetTester tester, _WritesWhenLet store) async {
    final (picture: picture, :overlay, :handAnew, store: _) = await standOn(
      tester,
      GlobalKey(),
      inAFolder([aPlugin(ShiftingFxPlugin(by: 2))]),
      laidBy: store,
    );
    expect(
      await settleAsync(tester, () => store.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    return (overlay: overlay, handAnew: handAnew);
  }

  testWidgets('a frame that waits for a plugin: one write at a time, the '
      'steps meanwhile going in together, in the next', (tester) async {
    final store = _WritesWhenLet();
    addTearDown(store.dispose);
    final (:overlay, handAnew: _) = await standingMade(tester, store);

    await aStep(tester, overlay, TileCoord(x: 0, y: 0));
    expect(store.asked, hasLength(1), reason: 'the first is on its way');
    await aStep(tester, overlay, TileCoord(x: 1, y: 1));
    await aStep(tester, overlay, TileCoord(x: 2, y: 2));
    expect(store.asked, hasLength(1), reason: 'the others wait behind it');

    store.letOneGo();
    expect(
      await settleAsync(tester, () => store.asked.length == 2),
      isTrue,
      reason: 'the next goes once the first is in',
    );
    final next = store.asked.last.rect;
    expect(
      next.contains(const Offset(tileSize * 1.5, tileSize * 1.5)) &&
          next.contains(const Offset(tileSize * 2.5, tileSize * 2.5)),
      isTrue,
      reason: 'the steps that waited, in one',
    );
    store.letAllGo();
    await lendBothClocks(tester, rounds: 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a frame that waits for a plugin: a step whose frame stands no '
      'more once its plugin has run does not go in', (tester) async {
    final store = _WritesWhenLet();
    addTearDown(store.dispose);
    final (:overlay, :handAnew) = await standingMade(tester, store);

    await aStep(tester, overlay, TileCoord(x: 0, y: 0));
    expect(store.asked, hasLength(1), reason: '⛔premise: on its way');
    // The pen's row handed anew before it goes in: the frame the step was
    // drawn by stands no more.
    await handAnew();

    store.letOneGo();
    expect(
      await settleAsync(tester, () => store.went.isNotEmpty),
      isTrue,
      reason: 'LIVENESS: answered',
    );
    expect(store.went, [false]);
    store.letAllGo();
    await tester.pumpWidget(const SizedBox());
  });

  /// The columns [colour] shows in on [shot].
  Set<int> inkColumnsOf(Shot shot, {List<int> colour = ink}) => {
    for (var at = 0; at < shot.rgba.length; at += 4)
      if (shot.rgba[at] == colour[0] &&
          shot.rgba[at + 1] == colour[1] &&
          shot.rgba[at + 2] == colour[2] &&
          shot.rgba[at + 3] == colour[3])
        at ~/ 4 % shot.width,
  };

  /// What [screen] shows once [nodes]' frame stands there, its picture
  /// made.
  Future<Shot> shownOnceMade(
    WidgetTester tester,
    List<CompositeNode<CanvasStackRow>> nodes,
  ) async {
    final screen = GlobalKey();
    final (:store, :picture, overlay: _, handAnew: _) = await standOn(
      tester,
      screen,
      nodes,
    );
    expect(
      await settleAsync(tester, () => store.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    return shotOf(tester, screen);
  }

  // 🚨Over the pen's row as well as round it: a folder that holds no row the
  // pen is on is drawn whole and held for the pen's steps
  // ([HeldSubtreeRasters]), and one held with its step drawn as if off
  // would be cut from by the next round, which then never met the step.
  for (final (where, nodesOf, colour) in [
    ('round the pen\'s row', inAFolder, ink),
    ('over the pen\'s row', overThePen, other),
  ]) {
    testWidgets('a frame that waits for a plugin $where is shown as its '
        'plugin made it', (tester) async {
      final asDrawn = inkColumnsOf(
        await shownOnceMade(tester, nodesOf(const [])),
        colour: colour,
      );
      expect(asDrawn, isNotEmpty, reason: '⛔CONTROL: the ink, as drawn');

      final shown = inkColumnsOf(
        await shownOnceMade(
          tester,
          nodesOf([aPlugin(ShiftingFxPlugin(by: 2))]),
        ),
        colour: colour,
      );

      // Two canvas pixels to the right, as many of the screen's each.
      final by = 2 * tester.view.devicePixelRatio.round();
      expect(shown, {for (final column in asDrawn) column + by});
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a frame that waits for a plugin, handed another whose picture '
      'is not there yet, stays on the picture it showed', (tester) async {
    final screen = GlobalKey();
    final (:store, :picture, overlay: _, :handAnew) = await standOn(
      tester,
      screen,
      inAFolder([aPlugin(ShiftingFxPlugin(by: 2))]),
    );
    expect(
      await settleAsync(tester, () => store.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    final before = await shotOf(tester, screen);
    expect(onlyTheScreen(before), isFalse, reason: '⛔premise: it is shown');

    await handAnew(inAFolder([aPlugin(ShiftingFxPlugin(by: 3))]));
    await tester.pump();

    expect(differences(before, await shotOf(tester, screen)), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  /// What a frame is laid with, on a composite of its own whose effect
  /// chains' kernels are still to be compiled — every other kernel the app
  /// compiles ahead compiled, and off this isolate, as the app compiles
  /// them — and how many kernels this thread had built by then.
  Future<({EngineFrameTools tools, int built})> toolsWhoseChainsAreToCome(
    WidgetTester tester,
  ) async {
    AppKernels.debugCompileHere = false;
    addTearDown(() => AppKernels.debugCompileHere = true);
    final composite = (await tester.runAsync(() async {
      await compileAppKernelsAhead();
      // Showing on screens as a test's are laid ([shownSurfaceOf]), which
      // is not on every platform as the app's own are.
      final screen = shownSurfaceOf(1, 1);
      final bgra = screen.bgra;
      screen.free();
      return GpuComposite.opening(appGpuEngine, bgra: bgra);
    }))!;
    // ⚠️Before the store that lays with it is made: freed after it.
    addTearDown(() {
      // ⚠️Freed only once its chains' compile is through: one on its way
      // holds it. Every test here waits for that; one that failed before
      // it leaves the composite to the process.
      if (!composite.chainsAreToCome) {
        composite.free();
      }
    });
    final letters = (await tester.runAsync(
      () => EngineLetters.open(composite),
    ))!;
    // Nor has the engine them: the app's own composite compiled its chains
    // in the list, and a kernel the engine keeps is any composite's, with
    // nothing to compile (rust/src/device.rs, `Kernels`).
    appGpuEngine.debugForgetKernels();
    expect(composite.chainsAreToCome, isTrue, reason: '⛔premise');
    return (
      tools: (composite: composite, letters: letters),
      built: debugKernelsCompiledHere,
    );
  }

  final blurs = fx(EffectKind.blur, {'blurriness': 3});

  // 🗣️gpu-canonical-store-Q12 (유저 2026-11-10): 「캔버스 자리에 준비 중 표시를
  // 둔다」 — its place is marked while it waits, and nothing turns once the
  // frame is shown (🗣️관제 2026-11-10 23:05: 「준비가 끝나면 표시가 프레임을
  // 돌리지 않는다」).
  testWidgets('a frame whose chain\'s kernels are still to be compiled, '
      'nothing shown yet: nothing drawn till they are, none compiled here, '
      'and its place marked till it is shown', (tester) async {
    theMarkStands();
    final (:tools, :built) = await toolsWhoseChainsAreToCome(tester);
    final screen = GlobalKey();
    // No picture comes: what is shown is the frame as it stands.
    final store = StoreLayingNothing(tools: () async => tools);
    await itsToolsOpen(tester, store);
    await standOn(tester, screen, inAFolder([blurs]), laidBy: store);
    await theMarkFollows(tester);

    // ⚠️Before the real clock is lent a turn: the compile, asked for by the
    // paint above, is through within one where the driver kept its kernels.
    expect(theMark, findsOneWidget);
    expect(onlyTheScreen(await shotOf(tester, screen)), isTrue);
    expect(
      tester.layers.whereType<TickSceneLayer>(),
      isEmpty,
      reason: 'no layer of a texture nothing was presented on',
    );
    expect(debugKernelsCompiledHere, built);

    expect(
      await settleAsync(
        tester,
        () async => !onlyTheScreen(await shotOf(tester, screen)),
      ),
      isTrue,
      reason: 'LIVENESS: shown once they are compiled',
    );
    expect(debugKernelsCompiledHere, built);
    await theMarkFollows(tester);
    expect(theMark, findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  // 🗣️gpu-canonical-store-Q15 (유저 2026-11-11): 「준비가 끝난 뒤에 그림을
  // 띄운다 — 그때까지 고리」 — a frame the engine could show already is kept
  // from the screen all the same, while a press on it would still stop the
  // app for a kernel's compile.
  testWidgets('a frame the app holds for its engine, its tools open and '
      'nothing to wait for: nothing of it on the screen till the app is let '
      'go', (tester) async {
    holdTheAppForItsEngine();
    addTearDown(debugLetTheAppGo);
    final screen = GlobalKey();
    final store = StoreLayingNothing();
    await itsToolsOpen(tester, store);
    await standOn(tester, screen, inAFolder(const []), laidBy: store);
    await tester.pump();

    expect(onlyTheScreen(await shotOf(tester, screen)), isTrue);

    debugLetTheAppGo();
    await tester.pump();

    expect(
      onlyTheScreen(await shotOf(tester, screen)),
      isFalse,
      reason: 'drawn as it stands, by the word alone — nothing handed anew',
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a frame handed another whose chain\'s kernels are still to be '
      'compiled stays on the picture it showed till they are', (tester) async {
    final (:tools, :built) = await toolsWhoseChainsAreToCome(tester);
    final screen = GlobalKey();
    final store = StoreLayingNothing(tools: () async => tools);
    await itsToolsOpen(tester, store);
    final (store: _, picture: _, overlay: _, :handAnew) = await standOn(
      tester,
      screen,
      inAFolder(const []),
      laidBy: store,
    );
    await tester.pump();
    final before = await shotOf(tester, screen);
    expect(onlyTheScreen(before), isFalse, reason: '⛔premise: it is shown');

    await handAnew(inAFolder([blurs]));

    expect(differences(before, await shotOf(tester, screen)), isEmpty);
    expect(
      await settleAsync(
        tester,
        () async =>
            differences(before, await shotOf(tester, screen)).isNotEmpty,
      ),
      isTrue,
      reason: 'LIVENESS: the frame handed is shown once they are compiled',
    );
    expect(debugKernelsCompiledHere, built);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a frame whose chain\'s kernels are still to be compiled has '
      'its picture made once they are, its store saying it waits till '
      'then', (tester) async {
    final (:tools, :built) = await toolsWhoseChainsAreToCome(tester);
    final store = StoreTellingItsWrites(tools: () async => tools);
    await itsToolsOpen(tester, store);
    final saidToWait = <bool>[];
    store.waits.addListener(() => saidToWait.add(store.waitsForKernels));
    final (store: _, :picture, overlay: _, handAnew: _) = await standOn(
      tester,
      GlobalKey(),
      inAFolder([blurs]),
      laidBy: store,
    );
    expect(store.laid, contains(picture), reason: '⛔premise: on its way');
    expect(store.bytesOf(picture), isNull, reason: '⛔premise: not made yet');

    expect(
      await settleAsync(tester, () => store.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: made once they are compiled',
    );
    expect(tester.takeException(), isNull);
    expect(debugKernelsCompiledHere, built);
    expect(saidToWait, [true, false]);
    await tester.pumpWidget(const SizedBox());
  });

  // A blank cel lays no picture, so none of its row's chain: the frame's
  // picture is made with the kernels still to come, and it is the pen's
  // first step that names the chain — where a step is written into the
  // picture shown.
  testWidgets('a pen\'s first step on a blank cel under a blur, the '
      'chain\'s kernels still to be compiled: the screen stays as it was '
      'till they are', (tester) async {
    final (:tools, :built) = await toolsWhoseChainsAreToCome(tester);
    final screen = GlobalKey();
    final store = StoreTellingItsWrites(tools: () async => tools);
    await itsToolsOpen(tester, store);
    final (store: _, :picture, :overlay, handAnew: _) = await standOn(
      tester,
      screen,
      [
        CompositeLeaf<CanvasStackRow>(
          CanvasActiveLayerRow(opacity: 1, frameKey: key, effects: [blurs]),
        ),
        const CompositeLeaf(
          CanvasLayerImageRequest(frameKey: over, opacity: 1),
        ),
      ],
      laidBy: store,
      penOnABlankCel: true,
    );
    expect(
      await settleAsync(tester, () => store.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    expect(
      tools.composite.chainsAreToCome,
      isTrue,
      reason: '⛔premise: made with no chain laid',
    );
    final before = await shotOf(tester, screen);
    expect(onlyTheScreen(before), isFalse, reason: '⛔premise: it is shown');

    await aStep(tester, overlay, TileCoord(x: 0, y: 0));

    expect(
      store.patched,
      isNotEmpty,
      reason: '⛔premise: the step was to be written into the picture',
    );
    expect(differences(before, await shotOf(tester, screen)), isEmpty);
    expect(
      await settleAsync(
        tester,
        () async =>
            differences(before, await shotOf(tester, screen)).isNotEmpty,
      ),
      isTrue,
      reason: 'LIVENESS: the step is shown once they are compiled',
    );
    expect(debugKernelsCompiledHere, built);
    await tester.pumpWidget(const SizedBox());
  });

  // 🗣️관제 2026-11-11 00:28: 「컴파일이 실패한 뒤 … 고리가 영원히 돌거나 직전
  // 그림에 영원히 머문다. 실제 실패가 그 끝나지 않는 재시도로 가지 않는지」
  // — a compile that ends in an error ends the wait as one that ends well
  // does: it is said by name, once, and the frame is laid by its paint all
  // the same, which compiles what it runs or says why it cannot (as a frame
  // the driver refuses is said, `ScreenTexture.present`).

  /// The chains' compile a test ends in an error ([GpuComposite
  /// .debugChainsCompile]) — made in [zone], the zone of what waits for it:
  /// an error goes to no listener of another zone's.
  Completer<void> theChainsCompileToFail({Zone? zone}) {
    final failed = (zone ?? Zone.current).run(Completer<void>.new);
    GpuComposite.debugChainsCompile = () => failed.future;
    addTearDown(() => GpuComposite.debugChainsCompile = null);
    return failed;
  }

  testWidgets('a frame whose chain\'s kernels could not be compiled off '
      'this isolate: said by name, laid by its paint all the same, its '
      'place marked no more and nothing turning', (tester) async {
    theMarkStands();
    final (:tools, :built) = await toolsWhoseChainsAreToCome(tester);
    final failed = theChainsCompileToFail();
    final screen = GlobalKey();
    // No picture comes: what waits for the compile is the paint alone.
    final store = StoreLayingNothing(tools: () async => tools);
    await itsToolsOpen(tester, store);
    await standOn(tester, screen, inAFolder([blurs]), laidBy: store);
    await theMarkFollows(tester);
    expect(theMark, findsOneWidget, reason: '⛔premise: marked while it waits');
    expect(
      onlyTheScreen(await shotOf(tester, screen)),
      isTrue,
      reason: '⛔premise: nothing drawn yet',
    );

    final failure = StateError('the chains would not compile');
    failed.completeError(failure);
    // The word of it, then the paint it asks for.
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), same(failure));
    expect(
      await settleAsync(
        tester,
        () async => !onlyTheScreen(await shotOf(tester, screen)),
      ),
      isTrue,
      reason: 'LIVENESS: laid by its paint',
    );
    expect(
      debugKernelsCompiledHere,
      greaterThan(built),
      reason: 'compiled where the frame is run, as before any compiled ahead',
    );
    await theMarkFollows(tester);
    expect(theMark, findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull, reason: 'said once');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a cut parked on whose picture waits for kernels that could '
      'not be compiled: its making fails once and is said by name, its '
      'store waits no more, its place is marked no more — and the frame is '
      'drawn as it stands', (tester) async {
    theMarkStands();
    final (:tools, built: _) = await toolsWhoseChainsAreToCome(tester);
    // What waits is the store's line, in no one's zone.
    final failed = theChainsCompileToFail(zone: Zone.root);
    final store = StoreTellingItsWrites(tools: () async => tools);
    await itsToolsOpen(tester, store);
    final saidToWait = <bool>[];
    store.waits.addListener(() => saidToWait.add(store.waitsForKernels));
    final screen = GlobalKey();
    final (store: _, :picture, overlay: _, handAnew: _) = await standOn(
      tester,
      screen,
      [
        CompositeGroup<CanvasStackRow>(
          children: const [
            CompositeLeaf(CanvasLayerImageRequest(frameKey: over, opacity: 1)),
          ],
          opacity: 1,
          blendMode: LayerBlendMode.normal,
          effects: [blurs],
        ),
      ],
      laidBy: store,
      parked: true,
    );
    expect(
      await settleAsync(tester, () => store.waitsForKernels),
      isTrue,
      reason: 'LIVENESS: its line stands behind the compile',
    );
    await theMarkFollows(tester);
    expect(theMark, findsOneWidget, reason: '⛔premise: marked while it waits');

    final failure = StateError('the chains would not compile');
    failed.completeError(failure);

    expect(
      await settleAsync(
        tester,
        () async => !onlyTheScreen(await shotOf(tester, screen)),
      ),
      isTrue,
      reason: 'LIVENESS: drawn as it stands, its making given up',
    );
    expect(tester.takeException(), same(failure));
    expect(saidToWait, [true, false]);
    expect(store.bytesOf(picture), isNull, reason: 'no picture of it was made');
    expect(
      store.laid.where((key) => key == picture),
      hasLength(1),
      reason: 'asked for once: not made again and again',
    );
    await theMarkFollows(tester);
    expect(theMark, findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull, reason: 'said once');
    await tester.pumpWidget(const SizedBox());
  });

  /// A canvas standing on a frame over a store whose tools are still to be
  /// opened, the app's engine open by then for the screen it shows through
  /// — and what opens them, or says they will not be: in no one's zone, as
  /// the app's are opened — an error goes to no listener of another zone's.
  Future<
    ({
      EngineFramePictureStore<FramePictureKey> store,
      Completer<EngineFrameTools> opened,
      EngineFrameTools tools,
    })
  >
  standingBeforeItsTools(WidgetTester tester) async {
    final tools = (await tester.runAsync(() => appEngineFrameTools))!;
    final opened = Zone.root.run(Completer<EngineFrameTools>.new);
    final store = StoreLayingNothing(tools: () => opened.future);
    await standOn(tester, GlobalKey(), inAFolder(const []), laidBy: store);
    await theMarkFollows(tester);
    return (store: store, opened: opened, tools: tools);
  }

  testWidgets('a frame whose engine\'s tools are still to be opened marks '
      'its place till they are, and nothing turns once they are', (
    tester,
  ) async {
    theMarkStands();
    final (:store, :opened, :tools) = await standingBeforeItsTools(tester);
    expect(theMark, findsOneWidget);

    await tester.runAsync(() {
      opened.complete(tools);
      return store.tools;
    });
    await theMarkFollows(tester);

    expect(theMark, findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  // 🗣️유저 2026-11-11: 「캔버스든 타임라인이든 구분안두고 … 공용창 띄워서」 ·
  // gpu-canonical-store-Q16 「창 한가운데 하나」 — the app stands behind its
  // one wait window while it is held, and a place whose
  // frames wait meanwhile, as they do for their tools, turns no mark under
  // it.
  testWidgets('a place whose frames wait stands no mark while the app is '
      'held for its engine, and its own once the app is let go', (
    tester,
  ) async {
    theMarkStands();
    holdTheAppForItsEngine();
    addTearDown(debugLetTheAppGo);
    final (:store, :opened, :tools) = await standingBeforeItsTools(tester);
    expect(theMark, findsNothing);

    debugLetTheAppGo();
    await theMarkFollows(tester);
    expect(theMark, findsOneWidget, reason: 'its tools are still to come');

    await tester.runAsync(() {
      opened.complete(tools);
      return store.tools;
    });
    await theMarkFollows(tester);
    expect(theMark, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a frame whose engine would not open marks its place no more: '
      'nothing waits for tools that will not come', (tester) async {
    theMarkStands();
    final (:store, :opened, tools: _) = await standingBeforeItsTools(tester);
    expect(theMark, findsOneWidget, reason: '⛔premise: marked till then');

    opened.completeError(StateError('no engine'));
    expect(
      await settleAsync(tester, () => !store.toolsAreToCome),
      isTrue,
      reason: 'LIVENESS: found unable to open',
    );
    await theMarkFollows(tester);

    expect(theMark, findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a canvas taken down with its place while it is marked says '
      'nothing to a place that is gone', (tester) async {
    theMarkStands();
    await standingBeforeItsTools(tester);
    expect(theMark, findsOneWidget, reason: '⛔premise: marked');

    await tester.pumpWidget(const SizedBox());

    expect(tester.takeException(), isNull);
  });

  /// A cut parked on: one row, shown whole.
  const parkedOn = <CompositeNode<CanvasStackRow>>[
    CompositeLeaf(CanvasLayerImageRequest(frameKey: over, opacity: 1)),
  ];

  // The store's line stands behind kernels still to be compiled
  // ([EngineFramePictureStore.waitsForKernels]): the place is marked where
  // nothing of the frame is drawn till its picture is there, and not where
  // the frame is drawn as it stands meanwhile — it is on the screen.
  for (final (name, nodesOf, parked, marked) in [
    ('a canvas standing on it', () => inAFolder(const []), false, false),
    ('a cut parked on, shown whole', () => parkedOn, true, true),
    (
      'a canvas standing on it, where it waits for a plugin besides',
      () => inAFolder([aPlugin(ShiftingFxPlugin(by: 2))]),
      false,
      true,
    ),
  ]) {
    testWidgets('a frame whose picture is on its way behind kernels still to '
        'be compiled, $name: its place '
        '${marked ? 'marked while they are' : 'not marked'}', (tester) async {
      theMarkStands();
      final store = _OnItsWayAndTold();
      await itsToolsOpen(tester, store);
      await standOn(
        tester,
        GlobalKey(),
        nodesOf(),
        laidBy: store,
        parked: parked,
      );
      await theMarkFollows(tester);
      expect(theMark, findsNothing, reason: 'on its way alone marks nothing');

      store.said.value = true;
      await theMarkFollows(tester);
      expect(theMark, marked ? findsOneWidget : findsNothing);

      store.said.value = false;
      await theMarkFollows(tester);
      expect(theMark, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a cut parked on whose picture is there, its store\'s line '
      'behind kernels still to be compiled: its place not marked', (
    tester,
  ) async {
    theMarkStands();
    final store = _MadeAndTold();
    await itsToolsOpen(tester, store);
    final (store: _, :picture, overlay: _, handAnew: _) = await standOn(
      tester,
      GlobalKey(),
      parkedOn,
      laidBy: store,
      parked: true,
    );
    expect(
      await settleAsync(tester, () => store.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: its picture is made',
    );
    await lendBothClocks(tester, rounds: 2);

    store.said.value = true;
    await theMarkFollows(tester);

    expect(theMark, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  // 🚨A MAKING THAT THREW IS NOT ASKED FOR AGAIN (🗣️관제 2026-11-11: 「실제
  // 실패가 그 끝나지 않는 재시도로 가지 않는지」). A screen that draws nothing
  // of its frame till its picture is there asked for the picture again the
  // moment its making had thrown, for as long as it threw, and said so by
  // name each time. It is drawn as its cels stand, as a frame the warmer's
  // making threw at is (`FramePictures.noteFailure`, 2026-10-24: 「a frame
  // whose making threw is drawn as its cels stand」).
  testWidgets('a cut parked on whose picture\'s making throws: asked for '
      'once, said by name once, and drawn as it stands', (tester) async {
    final failure = StateError('the driver refused');
    final store = StoreWhoseLaysThrow(failure);
    await itsToolsOpen(tester, store);
    final screen = GlobalKey();
    await standOn(tester, screen, parkedOn, laidBy: store, parked: true);

    expect(
      await settleAsync(
        tester,
        () async => !onlyTheScreen(await shotOf(tester, screen)),
      ),
      isTrue,
      reason: 'LIVENESS: drawn as it stands',
    );
    await lendBothClocks(tester, rounds: 4);

    expect(store.laid, hasLength(1));
    expect(tester.takeException(), same(failure));
    expect(tester.takeException(), isNull, reason: 'said once');
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a frame taken down while its place is marked marks it no '
      'more, and hears its store no more', (tester) async {
    theMarkStands();
    final store = _OnItsWayAndTold();
    await itsToolsOpen(tester, store);
    final screen = GlobalKey();
    await standOn(tester, screen, parkedOn, laidBy: store, parked: true);
    store.said.value = true;
    await theMarkFollows(tester);
    expect(theMark, findsOneWidget, reason: '⛔premise: marked');
    expect(store.said.isHeard, isTrue, reason: '⛔premise: heard');

    // The place stays; its frame goes.
    await tester.pumpWidget(
      onAScreen(screen, size: viewSize, under: under, view: const SizedBox()),
    );
    await theMarkFollows(tester);

    expect(theMark, findsNothing);
    expect(store.said.isHeard, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a frame handed another store\'s pictures marks its place by '
      'that store — its tools till they are opened, then its line — and '
      'hears the one it had no more', (tester) async {
    theMarkStands();
    final tools = (await tester.runAsync(() => appEngineFrameTools))!;
    final opened = Completer<EngineFrameTools>();
    final had = _OnItsWayAndTold();
    final handed = _OnItsWayAndTold(tools: () => opened.future);
    addTearDown(handed.dispose);
    await itsToolsOpen(tester, had);
    final (store: _, picture: _, overlay: _, :handAnew) = await standOn(
      tester,
      GlobalKey(),
      parkedOn,
      laidBy: had,
      parked: true,
    );
    await theMarkFollows(tester);
    expect(theMark, findsNothing, reason: '⛔premise: not marked');
    expect(had.said.isHeard, isTrue, reason: '⛔premise: heard');

    await handAnew(null, handed);
    await theMarkFollows(tester);

    expect(had.said.isHeard, isFalse);
    expect(theMark, findsOneWidget, reason: 'its tools are still to be opened');

    await tester.runAsync(() {
      opened.complete(tools);
      return handed.tools;
    });
    await theMarkFollows(tester);
    expect(theMark, findsNothing, reason: 'opened, and its line waits not');

    handed.said.value = true;
    await theMarkFollows(tester);
    expect(theMark, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

/// Says its line waits for kernels still to be compiled
/// ([EngineFramePictureStore.waitsForKernels]) when a test has it say so
/// ([said]).
mixin _ToldToSayItWaits on EngineFramePictureStore<FramePictureKey> {
  final _Said said = _Said();

  @override
  bool get waitsForKernels => said.value;

  @override
  Listenable get waits => _news;
  late final Listenable _news = Listenable.merge([super.waits, said]);
}

/// What a store told to says ([_ToldToSayItWaits]), and whether any view
/// hears it.
class _Said extends ValueNotifier<bool> {
  _Said() : super(false);

  bool get isHeard => hasListeners;
}

/// A store whose lays stay on their way.
class _OnItsWayAndTold = StoreLayingNothing with _ToldToSayItWaits;

/// A store whose pictures are made.
class _MadeAndTold = StoreTellingItsWrites with _ToldToSayItWaits;

/// A store whose writes through a frame's plugins go on when let
/// ([letOneGo]), saying what each was asked and whether it went in.
class _WritesWhenLet extends EngineFramePictureStore<FramePictureKey> {
  _WritesWhenLet() : super(tools: () => appEngineFrameTools);

  final List<({Rect rect, Completer<void> go})> asked = [];
  final List<bool> went = [];
  int _let = 0;
  bool _allGo = false;

  void letOneGo() => asked[_let++].go.complete();

  void letAllGo() {
    _allGo = true;
    while (_let < asked.length) {
      letOneGo();
    }
  }

  @override
  Future<bool> patchThrough({
    required FramePictureKey from,
    required FramePictureKey to,
    required Rect rect,
    required StackedFrame frame,
    required bool Function() stands,
    EngineChainHolds? holds,
  }) async {
    final go = Completer<void>();
    asked.add((rect: rect, go: go));
    if (_allGo) {
      letOneGo();
    }
    await go.future;
    final did = await super.patchThrough(
      from: from,
      to: to,
      rect: rect,
      frame: frame,
      stands: stands,
      holds: holds,
    );
    went.add(did);
    return did;
  }
}
