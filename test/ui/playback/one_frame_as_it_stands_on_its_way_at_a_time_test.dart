import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/frame_demand.dart' show FrameGhosts;
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
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'package:anicel/src/ui/playback/stand_pace.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/a_plugin_that_shifts.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// The raster thread in a test's hands: each frame on it is past when the
/// test says, as long after as it says.
final class _Raster {
  final Queue<Completer<void>> _fences = Queue();
  int _now = 0;

  /// How many fences were laid: how many frames went out, each told once.
  int laid = 0;

  late final StandPace pace = StandPace(behind: _fence, nowMicros: () => _now);

  Future<void> _fence() {
    expect(
      SchedulerBinding.instance.schedulerPhase,
      SchedulerPhase.postFrameCallbacks,
      reason: 'behind the frame it is to tell of, not ahead of it',
    );
    laid += 1;
    final fence = Completer<void>();
    _fences.add(fence);
    return fence.future;
  }

  /// The frame on its way is past, [micros] after it went: just long enough
  /// to keep the next one waiting, unless told.
  void past({int micros = 33000, Object? error}) {
    _now += micros;
    final fence = _fences.removeFirst();
    if (error == null) {
      fence.complete();
    } else {
      fence.completeError(error);
    }
  }
}

/// 🚨★★ONE FRAME AS IT STANDS ON ITS WAY AT A TIME ([StandPace]; card
/// a-dragged-opacity-slider-lags-at-rest): the law a stroke's steps go by
/// (`_stepOnItsWay`, F-512), for the trees a drag hands a canvas. Each stood
/// and composed as it came, two frames of the whole stack stood in line on
/// the raster thread, the value let go of behind them. A frame the raster
/// thread keeps up with goes as it was handed, and nothing but the tree
/// waits: a picture there to take, the live rows handed anew.
void main() {
  const tileSize = 16;
  const canvasSize = CanvasSize(width: 32, height: 32);
  const viewSize = Size(48, 40);
  const fill = [0x30, 0x60, 0x90, 0xFF];
  const under = Color(0xFF203040);
  final view = CanvasViewport(panX: 8, panY: 4);

  const inked = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('inked'),
    frameId: FrameId('f'),
  );
  final cut = Cut(
    id: inked.cutId,
    name: 'Cut',
    duration: 1,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: inked.layerId,
        name: 'Layer',
        frames: [Frame(id: inked.frameId, duration: 1, strokes: const [])],
        timeline: {0: TimelineExposure.drawing(inked.frameId, length: 1)},
      ),
    ],
  );
  // No paper: what lies under the ink is the screen's own.
  final frame = (
    cut: cut,
    frameIndex: 0,
    paintPaper: false,
    ghosts: FrameGhosts.none,
  );
  final screen = GlobalKey();

  BitmapSurface filled() => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (var ty = 0; ty < 2; ty += 1)
        for (var tx = 0; tx < 2; tx += 1)
          TileCoord(x: tx, y: ty): BitmapTile(
            size: tileSize,
            pixels: Uint8List.fromList([
              for (var at = 0; at < tileSize * tileSize; at += 1) ...fill,
            ]),
          ),
    },
  );

  List<CompositeNode<CanvasStackRow>> treeAt(double opacity) => [
    CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: inked, opacity: opacity),
    ),
  ];

  LiveRows liveRows() => (
    activeSurfacePainter: BitmapSurfacePainter(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
      showTransparentBackground: false,
      lineage: 'one-frame-as-it-stands',
    ),
    floatOverlay: null,
    liftedRows: const {},
  );

  StackRun runOn(WritesNeverLand gpu) {
    final cels = BrushFrameStore();
    keepInAFile(cels, {inked: filled()});
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final store = FramePictureStore<FramePictureKey>(gpu: gpu);
    addTearDown(store.dispose);
    return runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => treeAt(1),
    );
  }

  /// The gpu of a run no picture of which lands: the frame stands as it does.
  WritesNeverLand noPictureLands() {
    final gpu = WritesNeverLand()..holdsRenders = true;
    addTearDown(gpu.letAllThrough);
    return gpu;
  }

  Widget shownTree(
    StackRun run,
    LiveRows live,
    _Raster raster,
    List<CompositeNode<CanvasStackRow>> nodes, {
    bool wholeFrames = false,
  }) => onAScreen(
    screen,
    size: viewSize,
    under: under,
    view: FramePictureView(
      run: run,
      picture: frame,
      nodes: nodes,
      viewport: view,
      live: live,
      laysWhatItMisses: true,
      wholeFrames: wholeFrames,
      standPace: raster.pace,
    ),
  );

  Widget shown(
    StackRun run,
    LiveRows live,
    _Raster raster,
    double opacity, {
    bool wholeFrames = false,
  }) => shownTree(run, live, raster, treeAt(opacity), wholeFrames: wholeFrames);

  RenderCustomPaint theView(WidgetTester tester) =>
      tester.renderObject<RenderCustomPaint>(
        find.descendant(
          of: find.byType(FramePictureView),
          matching: find.byType(CustomPaint),
        ),
      );

  /// Whether a tree handed now stands: paints what it was handed.
  Future<bool> standsAt(
    WidgetTester tester,
    StackRun run,
    LiveRows live,
    _Raster raster,
    double opacity, {
    bool wholeFrames = false,
  }) async {
    await tester.pumpWidget(
      shown(run, live, raster, opacity, wholeFrames: wholeFrames),
      phase: EnginePhase.layout,
    );
    final stands = theView(tester).debugNeedsPaint;
    // A frame stopped at layout leaves its paint to one nothing scheduled.
    tester.binding.scheduleFrame();
    await tester.pump();
    return stands;
  }

  /// The red the ink shows at, over the screen's own.
  Future<int> redOnThePage(WidgetTester tester) async {
    final shot = await shotOf(tester, screen);
    return shot.rgba[(12 * shot.width + 20) * 4];
  }

  /// The red of [opacity]'s ink over [under].
  double redAt(double opacity) => fill[0] * opacity + 0x20 * (1 - opacity);

  /// The frame stands at 0.2, its cel read and the raster thread found to
  /// lag behind it, and at 0.4 on its way.
  Future<void> behindTheRaster(
    WidgetTester tester,
    StackRun run,
    LiveRows live,
    _Raster raster,
  ) async {
    await tester.pumpWidget(shown(run, live, raster, 0.2));
    expect(
      await settleAsync(
        tester,
        () => run.pictures.allInHand(treeAt(0.2), frame),
      ),
      isTrue,
      reason: 'LIVENESS: the cel is read',
    );
    expect(raster.laid, 1, reason: '⛔premise: the first frame went out');
    raster.past();
    await tester.pump();
    expect(
      await standsAt(tester, run, live, raster, 0.4),
      isTrue,
      reason: '⛔premise: nothing is on its way',
    );
    expect(raster.laid, 2, reason: '⛔premise: on its way');
  }

  testWidgets('🚨what is handed while the raster thread lags behind the frame '
      'on its way waits, and only the newest stands once it is past', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final raster = _Raster();
    final run = runOn(noPictureLands());
    final live = liveRows();
    await behindTheRaster(tester, run, live, raster);

    expect(await standsAt(tester, run, live, raster, 0.6), isFalse);
    expect(await standsAt(tester, run, live, raster, 0.8), isFalse);
    expect(raster.laid, 2, reason: 'nothing more went out');
    expect(await redOnThePage(tester), closeTo(redAt(0.4), 1));

    raster.past();
    await tester.pump();
    await tester.pump();

    expect(await redOnThePage(tester), closeTo(redAt(0.8), 1));
    expect(raster.laid, 3, reason: 'one frame, of the newest');

    raster.past();
    await tester.pump();
    await tester.pump();

    expect(raster.laid, 3, reason: 'and nothing more is owed');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a frame the raster thread keeps up with goes out as each tree '
      'is handed, and one no fence has spoken of yet', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final raster = _Raster();
    final run = runOn(noPictureLands());
    final live = liveRows();
    await tester.pumpWidget(shown(run, live, raster, 0.2));
    expect(
      await settleAsync(
        tester,
        () => run.pictures.allInHand(treeAt(0.2), frame),
      ),
      isTrue,
      reason: 'LIVENESS: the cel is read',
    );

    expect(
      await standsAt(tester, run, live, raster, 0.4),
      isTrue,
      reason: 'on its way, and nothing known of the raster thread',
    );

    raster.past(micros: 32999);
    await tester.pump();
    await standsAt(tester, run, live, raster, 0.6);
    expect(raster.laid, 2, reason: '⛔premise: on its way');
    expect(
      await standsAt(tester, run, live, raster, 0.8),
      isTrue,
      reason: 'under the bound the last one was past in time',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('🚨a picture that is there is taken at once, one on its way or '
      'not — and the next tree does not wait for what went before it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final raster = _Raster();
    final gpu = WritesNeverLand();
    addTearDown(gpu.letAllThrough);
    final run = runOn(gpu);
    final live = liveRows();
    await tester.pumpWidget(shown(run, live, raster, 0.2));
    final there = run.pictures.keyOfStack(treeAt(0.2), frame);
    expect(
      await settleAsync(tester, () => run.pictures.store.bytesOf(there) != null),
      isTrue,
      reason: 'LIVENESS: its picture is made',
    );
    await tester.pump();
    raster.past();
    await tester.pump();

    gpu.holdsRenders = true;
    await tester.pumpWidget(shown(run, live, raster, 0.4));
    expect(raster.laid, 2, reason: '⛔premise: on its way, and it lags');

    expect(
      await standsAt(tester, run, live, raster, 0.2),
      isTrue,
      reason: 'its picture is there',
    );
    expect(await redOnThePage(tester), closeTo(redAt(0.2), 1));
    raster.past();
    await tester.pump();
    expect(raster.laid, 2, reason: 'a picture sends out no frame as it stands');

    await tester.pumpWidget(shown(run, live, raster, 0.8));
    expect(raster.laid, 3, reason: '⛔premise: on its way, and it lags');
    expect(
      await standsAt(tester, run, live, raster, 0.2),
      isTrue,
      reason: 'taken again',
    );

    expect(
      await standsAt(tester, run, live, raster, 0.6),
      isTrue,
      reason: 'what is shown is that picture: nothing is drawn behind it',
    );
    gpu.letAllThrough();
    gpu.holdsRenders = false;
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('🚨the live rows handed anew do not wait', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final raster = _Raster();
    final run = runOn(noPictureLands());
    final live = liveRows();
    await behindTheRaster(tester, run, live, raster);

    expect(await standsAt(tester, run, liveRows(), raster, 0.6), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('🚨nor does another run, nor whole frames asked for', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final raster = _Raster();
    final run = runOn(noPictureLands());
    final live = liveRows();
    await behindTheRaster(tester, run, live, raster);

    expect(
      await standsAt(tester, run, live, raster, 0.4, wholeFrames: true),
      isTrue,
      reason: 'the same tree, for frames made whole',
    );
    expect(await standsAt(tester, run, live, raster, 0.4), isTrue);

    expect(
      await standsAt(tester, runOn(noPictureLands()), live, raster, 0.4),
      isTrue,
      reason: 'the same tree, of another run',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('⛔a frame that waits for its plugins is not drawn as it stands: '
      'it sends nothing out', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final raster = _Raster();
    final run = runOn(noPictureLands());
    await tester.pumpWidget(
      shownTree(run, liveRows(), raster, [
        CompositeGroup<CanvasStackRow>(
          children: treeAt(1),
          opacity: 1,
          blendMode: LayerBlendMode.normal,
          effects: [
            ResolvedLayerEffect(
              kind: EffectKind.plugin,
              plugin: shiftingFxPluginDescription,
              values: const [],
              run: fxPluginRunOf(ShiftingFxPlugin(by: 1)),
            ),
          ],
        ),
      ]),
    );
    await tester.pump();

    expect(raster.laid, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('handed back the tree that stands, nothing is owed', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final raster = _Raster();
    final run = runOn(noPictureLands());
    final live = liveRows();
    await behindTheRaster(tester, run, live, raster);

    expect(await standsAt(tester, run, live, raster, 0.6), isFalse);
    expect(await standsAt(tester, run, live, raster, 0.4), isFalse);

    raster.past();
    await tester.pump();
    await tester.pump();

    expect(raster.laid, 2, reason: 'the one that stands stands');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a fence that failed holds nothing back', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final raster = _Raster();
    final run = runOn(noPictureLands());
    final live = liveRows();
    await behindTheRaster(tester, run, live, raster);

    expect(await standsAt(tester, run, live, raster, 0.6), isFalse);
    raster.past(micros: 1, error: StateError('no raster'));
    await tester.pump();
    await tester.pump();

    expect(await redOnThePage(tester), closeTo(redAt(0.6), 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a view gone with one on its way stands nothing', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final raster = _Raster();
    final run = runOn(noPictureLands());
    final live = liveRows();
    await behindTheRaster(tester, run, live, raster);
    expect(await standsAt(tester, run, live, raster, 0.6), isFalse);

    await tester.pumpWidget(const SizedBox());
    raster.past();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(raster.laid, 2);
  });

  testWidgets('⛔a view that waits for whole frames sends nothing out as it '
      'stands, and nothing waits for it', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final raster = _Raster();
    final run = runOn(noPictureLands());
    await tester.pumpWidget(
      onAScreen(
        screen,
        size: viewSize,
        under: under,
        view: FramePictureView(
          run: run,
          picture: frame,
          nodes: treeAt(0.2),
          viewport: view,
          laysWhatItMisses: true,
          standPace: raster.pace,
        ),
      ),
    );
    await tester.pump();

    expect(raster.laid, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
