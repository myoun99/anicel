@Tags(['gpu'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart'
    show PromotedStrokeTile;
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart' show StackRun;
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// F-473 (유저 2026-10-26 「들고있다가 다른프레임 이동하면 남아있음 …
/// 제대로 층 안나눈게 혹시 원인인가?」, F-473-Q1 = 빌려 주기): while a
/// canvas shows over its frame what no cel stores, the frame's picture is
/// lent to it — held under the canvas's own key, the frame there all the
/// same — and given back once nothing such is shown; the canvas that goes
/// with it lent takes it along.
void main() {
  const tileSize = 16;
  const page = CanvasSize(width: 32, height: 32);
  const viewSize = Size(48, 40);
  const ink = [0x00, 0x40, 0x00, 0xFF];
  const ghost = [0x40, 0x00, 0x00, 0x80];
  const under = Color(0xFF203040);

  const bg = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('bg'),
    frameId: FrameId('bg'),
  );
  const cel = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('inked'),
    frameId: FrameId('a'),
  );

  BitmapTile tileOf(List<int>? Function(int x, int y) colourAt) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var y = 0; y < tileSize; y += 1) {
      for (var x = 0; x < tileSize; x += 1) {
        final colour = colourAt(x, y);
        if (colour != null) {
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

  final cut = Cut(
    id: bg.cutId,
    name: 'Cut',
    duration: 1,
    canvasSize: page,
    layers: [
      Layer(
        id: bg.layerId,
        name: 'Bg',
        frames: [Frame(id: bg.frameId, duration: 1, strokes: const [])],
        timeline: {0: TimelineExposure.drawing(bg.frameId, length: 1)},
      ),
      Layer(
        id: cel.layerId,
        name: 'Inked',
        frames: [Frame(id: cel.frameId, duration: 1, strokes: const [])],
        timeline: {0: TimelineExposure.drawing(cel.frameId, length: 1)},
      ),
    ],
  );
  final nodes = <CompositeNode<CanvasStackRow>>[
    const CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: bg, opacity: 1),
    ),
    const CompositeLeaf<CanvasStackRow>(
      CanvasActiveLayerRow(opacity: 1, frameKey: cel),
    ),
  ];
  final frame = (cut: cut, frameIndex: 0, paintPaper: false, ghosts: false);
  final ghostTile = PromotedStrokeTile(
    TileCoord(x: 0, y: 0),
    tileOf((x, y) => x > 3 && x < 12 && y > 3 && y < 12 ? ghost : null),
    1,
  );

  /// A canvas standing on the frame, its picture made: the store, the run
  /// and the overlay its live row draws.
  Future<
    ({
      FramePictureStore<FramePictureKey> store,
      StackRun run,
      ActiveStrokeOverlayModel overlay,
      WritesLand gpu,
      FramePictureKey key,
    })
  >
  standing(WidgetTester tester) async {
    final cels = BrushFrameStore();
    keepInAFile(cels, {
      bg: BitmapSurface(
        canvasSize: page,
        tileSize: tileSize,
        tiles: {
          for (var ty = 0; ty < 2; ty += 1)
            for (var tx = 0; tx < 2; tx += 1)
              TileCoord(x: tx, y: ty): tileOf((_, _) => ink),
        },
      ),
      cel: BitmapSurface(canvasSize: page, tileSize: tileSize, tiles: {}),
    });
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize);
    addTearDown(overlay.dispose);
    final gpu = WritesLand();
    final store = FramePictureStore<FramePictureKey>(gpu: gpu);
    addTearDown(store.dispose);
    final run = runOver(
      images,
      store,
      canvasSize: page,
      stackOf: (_) => nodes,
    );
    await tester.pumpWidget(
      onAScreen(
        GlobalKey(),
        size: viewSize,
        under: under,
        view: standingOn(
          run,
          picture: frame,
          nodes: nodes,
          viewport: CanvasViewport(),
          live: (
            activeSurfacePainter: BitmapSurfacePainter(
              surface: BrushFrameDisplayCacheService(
                frameStore: cels,
                canvasSize: page,
              ).prepareFramePreview(cel).previewSurface,
              overlayModel: overlay,
              showTransparentBackground: false,
              lineage: 'lent',
            ),
            floatOverlay: null,
            liftedRows: const {},
          ),
        ),
      ),
    );
    final key = run.pictures.keyOfStack(nodes, frame);
    expect(
      await settleAsync(tester, () => store.holds(key)),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    return (store: store, run: run, overlay: overlay, gpu: gpu, key: key);
  }

  /// Shows [tile] over the frame and waits for it to be in the picture.
  Future<void> shows(
    WidgetTester tester,
    ActiveStrokeOverlayModel overlay,
    FramePictureStore<FramePictureKey> store,
    FramePictureKey to,
    void Function() change,
  ) async {
    change();
    await tester.pump();
    await inThePicture(tester, store.landingOf(to));
  }

  testWidgets('shown a ghost, a canvas holds its frame\'s picture as its own '
      '— the frame there all the same — and gives it back once the ghost '
      'goes', (tester) async {
    final (:store, :run, :overlay, gpu: _, :key) = await standing(tester);
    final lent = keptByTheCanvas(tester, key);

    await shows(
      tester,
      overlay,
      store,
      lent,
      () => overlay.showResultTiles([ghostTile]),
    );
    expect(store.holds(lent), isTrue, reason: 'held as the canvas\'s own');
    expect(
      store.holds(key),
      isFalse,
      reason: 'no screen asking for the frame is handed the ghost',
    );
    expect(
      run.pictures.has(frame),
      isTrue,
      reason: 'the frame is there, lent — not missing for a walk to lay',
    );

    await shows(tester, overlay, store, key, overlay.reset);
    expect(store.holds(key), isTrue, reason: 'given back to the frame');
    expect(store.holds(lent), isFalse);

    await tester.pumpWidget(const SizedBox());
    expect(
      store.pinnedBytes,
      0,
      reason: 'the canvas gone holds nothing on screen: its hold went with '
          'the picture, lent and given back',
    );
  }, skip: noFlutterGpu != null);

  testWidgets('a canvas that goes with its frame\'s picture lent takes it '
      'along — the frame missing, to be laid as it is', (tester) async {
    final (:store, :run, :overlay, gpu: _, :key) = await standing(tester);
    final lent = keptByTheCanvas(tester, key);
    await shows(
      tester,
      overlay,
      store,
      lent,
      () => overlay.showResultTiles([ghostTile]),
    );
    expect(store.holds(lent), isTrue, reason: '⛔premise: lent');

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(store.settled);
    expect(store.holds(lent), isFalse, reason: 'let go with the canvas');
    expect(store.holds(key), isFalse, reason: 'never given back with a ghost');
    expect(run.pictures.has(frame), isFalse);
  }, skip: noFlutterGpu != null);

  testWidgets('a canvas that goes while its ghost is on its way into the '
      'picture takes the picture along — nothing comes in under the key it '
      'was lent under', (tester) async {
    final (:store, :run, :overlay, :gpu, :key) = await standing(tester);
    final lent = keptByTheCanvas(tester, key);
    gpu.holdsRenders = true;
    addTearDown(gpu.letAllThrough);
    overlay.showResultTiles([ghostTile]);
    await tester.pump();
    expect(
      await settleAsync(tester, () => gpu.rendersWaiting == 1),
      isTrue,
      reason: '⛔premise: the ghost is on its way into the picture',
    );
    expect(store.landingOf(lent), isNotNull, reason: '⛔premise: lent');

    await tester.pumpWidget(const SizedBox());
    expect(
      store.landingOf(lent),
      isNull,
      reason: 'nothing is on its way to the canvas gone',
    );
    gpu.letAllThrough();
    await lendBothClocks(tester, rounds: 4);
    expect(store.holds(lent), isFalse, reason: 'let go with the canvas');
    expect(store.holds(key), isFalse, reason: 'never given back with a ghost');
    expect(run.pictures.has(frame), isFalse);
  }, skip: noFlutterGpu != null);
}
