/// Each test lays a frame on two engines, and each engine compiles the
/// frame's kernels where it is first laid on: the bound is this file's own
/// (`timeline_grid_tile_generation_test.dart` says why).
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuScreen;
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/frame_demand.dart'
    show FrameGhosts;
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/engine_frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart' show StackRun;
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/the_apps_engine_let_go.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
/// 않고 새 장치를 열어 사본으로 되살린다」 — a frame on screen as the app
/// lets its engine go lets go of what it showed, a picture and a texture of
/// that engine, and stands again as it stood: its picture laid with the
/// next engine's tools, or drawn as its cels stand on a screen of them.
///
/// The frames are let go of here as a session's rig lets go of them
/// (`PlaybackRig`, pinned where the rig is: the warmer makes them again).
///
/// On the app's own engine, which each test loses: the one after it finds
/// the next.
void main() {
  opensTheEnginesScreens();
  const tileSize = defaultCelTileSize;
  const canvasSize = CanvasSize(width: 2 * tileSize, height: tileSize);
  const viewSize = Size(2.0 * tileSize, 1.0 * tileSize);
  const under = Color(0xFF000000);
  const red = [0xFF, 0x00, 0x00, 0xFF];

  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );
  final cut = Cut(
    id: key.cutId,
    name: 'Cut',
    duration: 1,
    canvasSize: canvasSize,
    layers: const [],
  );
  // No paper: the screen shows the cel alone.
  final frame = (
    cut: cut,
    frameIndex: 0,
    paintPaper: false,
    ghosts: FrameGhosts.none,
  );
  final screen = GlobalKey();

  /// A cel of red, its bytes here.
  BitmapSurface aRedCel() => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (var tx = 0; tx < 2; tx += 1)
        TileCoord(x: tx, y: 0): BitmapTile(
          size: tileSize,
          pixels: Uint8List.fromList([
            for (var i = 0; i < tileSize * tileSize; i += 1) ...red,
          ]),
        ),
    },
  );

  List<CompositeNode<CanvasStackRow>> nodes() => [
    const CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: key, opacity: 1),
    ),
  ];

  Future<void> standOn(WidgetTester tester, StackRun run) => tester.pumpWidget(
    onAScreen(
      screen,
      size: viewSize,
      under: under,
      view: standingOn(
        run,
        picture: frame,
        nodes: nodes(),
        viewport: CanvasViewport(),
        live: (activeSurfacePainter: null, floatOverlay: null, liftedRows: {}),
      ),
    ),
  );

  List<int> pixelAt(Shot shot, int x, int y) =>
      shot.rgba.sublist((y * shot.width + x) * 4, (y * shot.width + x) * 4 + 4);

  /// A run over the red cel, its frames' pictures kept by [store].
  StackRun runOn(EngineFramePictureStore<FramePictureKey> store) {
    addTearDown(store.dispose);
    final images = LayerFrameImageCache(
      frameStore: BrushFrameStore()..storeBakedSurface(key, aRedCel()),
    );
    addTearDown(images.dispose);
    return runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => nodes(),
    );
  }

  /// The device goes and the app lets its engine go, the frames with it.
  void theEngineGoes(StackRun run) {
    theAppsEngineLostAndLetGo();
    run.pictures.letGoWithTheirEngine();
  }

  testWidgets('🚨a frame whose picture is on screen shows again as it did, '
      'its picture laid with the next engine\'s tools — and holds nothing '
      'of the one it showed', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = aStoreOfPictures();
    final run = runOn(store);
    await standOn(tester, run);
    final shown = run.pictures.keyOfStack(nodes(), frame);
    expect(
      await settleAsync(tester, () => store.peek(shown) != null),
      isTrue,
      reason: '⛔premise: the frame\'s picture is made',
    );
    await standOn(tester, run);
    final before = await shotOf(tester, screen);
    expect(pixelAt(before, 20, 8), red, reason: '⛔premise: it is shown');
    final first = store.peek(shown);
    final kept = GpuScreen.liveBytes;

    theEngineGoes(run);
    await tester.pump();

    expect(GpuScreen.liveBytes, lessThan(kept), reason: 'held by none');
    expect(
      await settleAsync(tester, () => store.peek(shown) != null),
      isTrue,
      reason: 'laid again, with the next tools',
    );
    await standOn(tester, run);
    expect(identical(store.peek(shown), first), isFalse);
    expect(differences(before, await shotOf(tester, screen)), isEmpty);
  });

  testWidgets('the screen shows nothing through a texture that went '
      'with its engine, of itself — whoever lets go of its frames, and '
      'before they do', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = aStoreOfPictures();
    final run = runOn(store);
    await standOn(tester, run);
    final shown = run.pictures.keyOfStack(nodes(), frame);
    expect(
      await settleAsync(tester, () => store.peek(shown) != null),
      isTrue,
      reason: '⛔premise: the frame\'s picture is made',
    );
    await standOn(tester, run);
    expect(
      pixelAt(await shotOf(tester, screen), 20, 8),
      red,
      reason: '⛔premise: it is shown',
    );

    theAppsEngineLostAndLetGo();
    await tester.pump();

    expect(
      pixelAt(await shotOf(tester, screen), 20, 8),
      [0x00, 0x00, 0x00, 0xFF],
      reason: 'what lies under it',
    );
    run.pictures.letGoWithTheirEngine();
  });

  testWidgets('a frame drawn as it stands, its picture not there, stands '
      'again on a screen of the next engine\'s tools — which the view '
      'asks for, no lay coming to', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = StoreLayingNothing();
    final run = runOn(store);
    await standOn(tester, run);
    await itsToolsOpen(tester, store);
    await standOn(tester, run);
    final before = await shotOf(tester, screen);
    expect(pixelAt(before, 20, 8), red, reason: '⛔premise: it stands');
    final kept = GpuScreen.liveBytes;

    theEngineGoes(run);
    await tester.pump();

    expect(GpuScreen.liveBytes, lessThan(kept), reason: 'its own screen');
    expect(
      await settleAsync(tester, () => store.toolsOpen != null),
      isTrue,
      reason: 'asked for by the view',
    );
    await standOn(tester, run);
    expect(differences(before, await shotOf(tester, screen)), isEmpty);
  });
}
