import 'dart:typed_data';

import 'package:flutter/material.dart';
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
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart'
    show PromotedStrokeTile;
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/settle_async.dart';

/// 🚨A PAGE A PEN DRAWS ON IS A PICTURE TOO (first-stroke-on-a-new-project-
/// trails, 2026-10-28): a canvas standing on a frame of its page alone — a
/// new project's, a blank cel's — makes its picture, and the first stroke's
/// steps are written into it as every later stroke's are. Drawn as it
/// stood, each step of that stroke composed the whole view (🔬Surface Pro
/// 11: step → ink p50 117–123 ms, the second stroke p50 33).
///
/// A screen that draws nothing live still makes no picture of a page alone
/// (`FramePictures.drawsOnlyItsPage`), and draws it as it stands.
///
/// The writes never land ([WritesNeverLand]): a step on its way into the
/// picture is the oracle, the GPU's own writes are pinned elsewhere
/// (`a_stroke_is_written_into_the_picture_shown_test`).
void main() {
  const tileSize = 16;
  const canvasSize = CanvasSize(width: 32, height: 32);
  const viewSize = Size(48, 40);
  const under = Color(0xFF203040);
  const cel = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('blank'),
    frameId: FrameId('f'),
  );
  final cut = Cut(
    id: cel.cutId,
    name: 'Cut',
    duration: 1,
    canvasSize: canvasSize,
    layers: [],
  );
  final page = (cut: cut, frameIndex: 0, paintPaper: true, ghosts: FrameGhosts.none);
  final view = CanvasViewport(panX: 8, panY: 4);
  final screen = GlobalKey();

  /// The pen's row: on [frameKey]'s cel, or on none yet.
  List<CompositeNode<CanvasStackRow>> rowOn(BrushFrameKey? frameKey) => [
    CompositeLeaf<CanvasStackRow>(
      CanvasActiveLayerRow(opacity: 1, frameKey: frameKey),
    ),
  ];

  BitmapTile tileOf(List<int> colour) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var at = 0; at < pixels.length; at += 4) {
      pixels.setRange(at, at + 4, colour);
    }
    return BitmapTile(size: tileSize, pixels: pixels);
  }

  final first = TileCoord(x: 0, y: 0);
  final ink = tileOf(const [0x40, 0x00, 0x00, 0x80]);

  /// A step of the stroke on [overlay].
  void step(ActiveStrokeOverlayModel overlay) =>
      overlay.showResultTiles([PromotedStrokeTile(first, ink, 1)]);

  BitmapSurfacePainter painterOver(
    BitmapSurface surface,
    ActiveStrokeOverlayModel overlay,
  ) => BitmapSurfacePainter(
    surface: surface,
    overlayModel: overlay,
    showTransparentBackground: false,
    lineage: 'a-pen-on-a-blank-page',
  );

  /// The cels, their pictures and the store of the frames', torn down after.
  ({BrushFrameStore cels, StackRun run, FramePictureStore<FramePictureKey> store})
  aPage(List<CompositeNode<CanvasStackRow>> Function() nodes) {
    final cels = BrushFrameStore();
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final store = FramePictureStore<FramePictureKey>(gpu: WritesNeverLand());
    addTearDown(store.dispose);
    final run = runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => nodes(),
    );
    return (cels: cels, run: run, store: store);
  }

  Future<void> standOn(
    WidgetTester tester,
    StackRun run, {
    required List<CompositeNode<CanvasStackRow>> nodes,
    required LiveRows live,
  }) => tester.pumpWidget(
    onAScreen(
      screen,
      size: viewSize,
      under: under,
      view: standingOn(
        run,
        key: const ValueKey(0),
        picture: page,
        nodes: nodes,
        viewport: view,
        live: live,
      ),
    ),
  );

  testWidgets('🚨a canvas standing on a frame of its page alone makes its '
      'picture, and the first stroke\'s step is written into it — not the '
      'frame drawn as it stands', (tester) async {
    final nodes = rowOn(cel);
    final (cels: _, :run, :store) = aPage(() => nodes);
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize);
    addTearDown(overlay.dispose);
    final blank = run.pictures.keyOfStack(nodes, page);
    expect(
      run.pictures.drawsOnlyItsPage(blank),
      isTrue,
      reason: '⛔premise: a blank cel on its paper is the page alone',
    );

    await standOn(
      tester,
      run,
      nodes: nodes,
      live: (
        activeSurfacePainter: painterOver(
          BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
          overlay,
        ),
        floatOverlay: null,
        liftedRows: const {},
      ),
    );
    expect(
      await settleAsync(tester, () => store.bytesOf(blank) != null),
      isTrue,
      reason: 'the page\'s picture is made for the pen standing on it',
    );
    await lendBothClocks(tester, rounds: 2);

    step(overlay);
    await tester.pump();
    expect(
      store.landingOf(keptByTheCanvas(tester, blank)),
      isNotNull,
      reason: 'the step is on its way into the page\'s picture',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('🚨a pen\'s row that comes to the page after its picture — a '
      'cel made on it — has its step written into it, and the stroke that '
      'lands moves the picture to the frame\'s next key', (tester) async {
    var nodes = rowOn(null);
    final (:cels, :run, :store) = aPage(() => nodes);
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize);
    addTearDown(overlay.dispose);
    final blank = run.pictures.keyOfStack(nodes, page);

    await standOn(
      tester,
      run,
      nodes: nodes,
      live: (
        activeSurfacePainter: null,
        floatOverlay: null,
        liftedRows: const {},
      ),
    );
    expect(
      await settleAsync(tester, () => store.bytesOf(blank) != null),
      isTrue,
      reason: '⛔premise: the page\'s picture is taken with no pen\'s row',
    );
    await lendBothClocks(tester, rounds: 2);

    nodes = rowOn(cel);
    expect(
      run.pictures.keyOfStack(nodes, page),
      blank,
      reason: '⛔premise: a blank cel made on it is the same page',
    );
    LiveRows liveOver(BitmapSurface surface) => (
      activeSurfacePainter: painterOver(surface, overlay),
      floatOverlay: null,
      liftedRows: const {},
    );
    await standOn(
      tester,
      run,
      nodes: nodes,
      live: liveOver(BitmapSurface(canvasSize: canvasSize, tileSize: tileSize)),
    );
    step(overlay);
    await tester.pump();
    expect(
      store.landingOf(keptByTheCanvas(tester, blank)),
      isNotNull,
      reason: 'the step is on its way into the page\'s picture — ⛔not the '
          'frame drawn as it stands, the row\'s change untold',
    );

    final stored = BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: {first: ink},
    );
    cels.storeBakedSurface(cel, stored);
    cels.markCelEdited(cel);
    overlay.reset();
    final drawn = run.pictures.keyOfStack(nodes, page);
    expect(drawn, isNot(blank), reason: '⛔premise: the frame\'s key moved');
    await standOn(tester, run, nodes: nodes, live: liveOver(stored));
    expect(
      store.landingOf(drawn),
      isNotNull,
      reason: 'the stroke landed on the cel the pen was on: the picture '
          'moves to the frame\'s next key — ⛔not laid again whole',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a run — a screen that draws nothing live — makes no picture '
      'of a page alone, and draws it as it stands', (tester) async {
    final nodes = rowOn(cel);
    final (cels: _, :run, :store) = aPage(() => nodes);
    final blank = run.pictures.keyOfStack(nodes, page);

    await tester.pumpWidget(
      onAScreen(
        screen,
        size: viewSize,
        under: under,
        view: FramePictureView(
          run: run,
          picture: page,
          nodes: nodes,
          viewport: view,
        ),
      ),
    );
    await lendBothClocks(tester, rounds: 4);

    expect(store.bytesOf(blank), isNull, reason: 'no picture of the page');
    final shot = await shotOf(tester, screen);
    // The page lies from the view's pan: its middle is paper, not the
    // screen under it.
    final ratio = tester.view.devicePixelRatio;
    final at = ((20 * ratio).round() * shot.width + (24 * ratio).round()) * 4;
    expect(
      shot.rgba.sublist(at, at + 4),
      isNot([0x20, 0x30, 0x40, 0xFF]),
      reason: 'LIVENESS: the page is drawn as it stands',
    );
  });
}
