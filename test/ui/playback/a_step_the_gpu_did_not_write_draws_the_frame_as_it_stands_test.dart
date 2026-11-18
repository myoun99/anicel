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
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart'
    show PromotedStrokeTile;
import 'package:anicel/src/services/playback/frame_demand.dart' show FrameGhosts;
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// 🚨A STEP THE GPU DID NOT WRITE INTO THE PICTURE SHOWN DRAWS THE FRAME AS
/// IT STANDS, AND A FRAME AS IT STANDS THE GPU DID NOT DRAW IS DRAWN AGAIN
/// AT THE NEXT PAINT (the-ui-thread-never-enters-the-driver B1-a,
/// 2026-11-15): a canvas hands both to the engine unwaited
/// (`GpuScreen.compose`), so where one fails — the device gone as it lays,
/// memory short — is told by its done, not where it was asked. Shown as
/// the picture without the step, the stroke would leave the frame (F-509,
/// 유저 2026-10-30 「홍보 한참인데 진짜 비상사태」).
///
/// ⚠️Its own file: a device that is gone is gone for its process.
void main() {
  opensTheEnginesScreens();
  const tileSize = 128;
  const canvasSize = CanvasSize(width: 32, height: 32);
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('inked'),
    frameId: FrameId('f'),
  );
  final frame = (
    cut: Cut(
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
      ],
    ),
    frameIndex: 0,
    paintPaper: false,
    ghosts: FrameGhosts.none,
  );
  final nodes = [
    const CompositeLeaf<CanvasStackRow>(
      CanvasActiveLayerRow(opacity: 1, frameKey: key),
    ),
  ];
  final origin = TileCoord(x: 0, y: 0);

  /// A tile of [colour] where [where] holds, clear elsewhere.
  BitmapTile tileOf(List<int> colour, Rect where) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var y = 0; y < tileSize; y += 1) {
      for (var x = 0; x < tileSize; x += 1) {
        if (where.contains(Offset(x + 0.5, y + 0.5))) {
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

  final cel = BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      origin: tileOf(
        const [0x00, 0x40, 0x00, 0x80],
        Offset.zero & const Size(32, 32),
      ),
    },
  );

  testWidgets('🚨a step whose write the device refused once it was through '
      'shows the frame as it stands — and that, refused too, is drawn again '
      'at the next paint', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final cels = BrushFrameStore();
    keepInAFile(cels, {key: cel});
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = cel;
    addTearDown(overlay.dispose);
    final store = aStoreOfPictures();
    addTearDown(store.dispose);
    final run = runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => nodes,
    );
    await tester.pumpWidget(
      onAScreen(
        GlobalKey(),
        size: const Size(48, 40),
        under: const Color(0xFF203040),
        view: standingOn(
          run,
          picture: frame,
          nodes: nodes,
          viewport: CanvasViewport(),
          live: (
            activeSurfacePainter: BitmapSurfacePainter(
              surface: cel,
              overlayModel: overlay,
              showTransparentBackground: false,
              lineage: 'a-step-the-gpu-did-not-write',
            ),
            floatOverlay: null,
            liftedRows: const {},
          ),
        ),
      ),
    );
    final shown = run.pictures.keyOfStack(nodes, frame);
    expect(
      await settleAsync(tester, () => store.bytesOf(shown) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    await tester.pump();

    final reportTo = FlutterError.onError;
    final told = <String>[];
    FlutterError.onError = (details) => told.add('${details.context}');
    int drawnAsItStands() =>
        told.where((doing) => doing == 'drawing a frame as it stands').length;
    // The step's tile the engine's alone, as a live stroke's result is
    // (`BrushLiveStrokeRasterizer` lands it): its ask stores nothing.
    final stroked = EngineTileLedger.instance.debugOnEngine(
      tileOf(const [0x40, 0x00, 0x00, 0x80], const Rect.fromLTRB(4, 4, 12, 12)),
    );
    try {
      // Unheard: the word comes inside the first wait, which no ask of the
      // step makes — so the GPU it was handed to refuses it.
      appGpuEngine.debugLose();
      overlay.showResultTiles([PromotedStrokeTile(origin, stroked, 1)]);
      await tester.pump();
      expect(
        told,
        isNot(contains('writing a step into the picture shown')),
        reason: '⛔premise: refused once the GPU is through, not where asked',
      );

      expect(
        await settleAsync(tester, () => drawnAsItStands() > 0),
        isTrue,
        reason: 'the frame is drawn as it stands, which the device gone '
            'refuses too',
      );
      expect(told, contains('writing a step into the picture shown'));

      final before = drawnAsItStands();
      tester.renderObject(find.byType(FramePictureView)).markNeedsPaint();
      expect(
        await settleAsync(tester, () => drawnAsItStands() > before),
        isTrue,
        reason: 'composed again at the next paint: the screen keeps no '
            'canvas it failed on',
      );
    } finally {
      FlutterError.onError = reportTo;
    }
    await tester.pumpWidget(const SizedBox());
  });
}
