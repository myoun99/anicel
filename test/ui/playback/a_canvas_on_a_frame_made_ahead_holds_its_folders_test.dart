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
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'package:anicel/src/ui/quiet_turns.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// 🚨A CANVAS STANDING ON A FRAME MADE AHEAD OF IT HOLDS THAT FRAME'S
/// FOLDERS (`FramePictures.holdNodesOf`; card
/// paint-walk-redoes-the-same-work-each-step): the warmer lays every frame
/// but the one a cut opens on, keeping none of their nodes, so a canvas
/// that stands on one draws them whole once, in a turn of their own — and
/// its strokes' steps are cut from them. A screen that draws nothing live
/// — a run — holds none.
void main() {
  const tileSize = 16;
  const canvasSize = CanvasSize(width: 32, height: 32);
  final view = CanvasViewport(panX: 8, panY: 4);

  BrushFrameKey celOf(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );
  final a = celOf('a');
  final b = celOf('b');
  final pen = celOf('pen');
  final cut = Cut(
    id: a.cutId,
    name: 'Cut',
    duration: 1,
    canvasSize: canvasSize,
    layers: [
      for (final cel in [a, b, pen])
        Layer(
          id: cel.layerId,
          name: 'Layer',
          frames: [Frame(id: cel.frameId, duration: 1, strokes: const [])],
          timeline: {0: TimelineExposure.drawing(cel.frameId, length: 1)},
        ),
    ],
  );
  final frame = (cut: cut, frameIndex: 0, paintPaper: false);

  BitmapSurface filled(List<int> colour) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (var ty = 0; ty < 2; ty += 1)
        for (var tx = 0; tx < 2; tx += 1)
          TileCoord(x: tx, y: ty): BitmapTile(
            size: tileSize,
            pixels: Uint8List.fromList([
              for (var at = 0; at < tileSize * tileSize; at += 1) ...colour,
            ]),
          ),
    },
  );

  /// Two rows in a folder at half strength — one picture of its own — under
  /// the row a pen is on, over an empty cel.
  List<CompositeNode<CanvasStackRow>> treeOf() => [
    CompositeGroup<CanvasStackRow>(
      children: [
        CompositeLeaf(CanvasLayerImageRequest(frameKey: a, opacity: 1)),
        CompositeLeaf(CanvasLayerImageRequest(frameKey: b, opacity: 0.6)),
      ],
      opacity: 0.5,
      blendMode: LayerBlendMode.normal,
      effects: const [],
    ),
    CompositeLeaf<CanvasStackRow>(
      CanvasActiveLayerRow(opacity: 1, frameKey: pen),
    ),
  ];

  Widget onScreen(Widget view) => onAScreen(
    GlobalKey(),
    size: const Size(48, 40),
    under: const Color(0xFF203040),
    view: view,
  );

  /// The run over the frame, its picture made ahead of any screen — its
  /// background work taking its turns in [turns] where a test names them.
  Future<StackRun> madeAhead(WidgetTester tester, {QuietTurns? turns}) async {
    final cels = BrushFrameStore();
    keepInAFile(cels, {
      a: filled(const [0x30, 0x60, 0x90, 0xFF]),
      b: filled(const [0x90, 0x30, 0x10, 0xFF]),
    });
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final store = FramePictureStore<FramePictureKey>(gpu: WritesNeverLand());
    addTearDown(store.dispose);
    final run = runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => treeOf(),
      quietTurns: turns,
    );
    await tester.runAsync(
      () => run.pictures.make(frame, shouldAbort: () => false),
    );
    expect(
      store.bytesOf(run.pictures.keyOfStack(treeOf(), frame)),
      isNotNull,
      reason: '⛔premise: the frame is made',
    );
    expect(
      run.pictures.heldNodes,
      hasLength(0),
      reason: '⛔premise: made ahead, it keeps no folder',
    );
    return run;
  }

  /// The rows a canvas that stands holds live: the pen's, nothing on it.
  LiveRows liveRows() => (
    activeSurfacePainter: BitmapSurfacePainter(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
      showTransparentBackground: false,
    ),
    floatOverlay: null,
    liftedRows: const {},
  );

  // While frames are held — a run playing — a job waits its turn behind
  // the one before it, and the next waits on it. ⚠️Made off the fake
  // clock: a turn given at once completes in the zone the turns were made
  // in, and the fake clock's microtasks do not run inside `runAsync`.
  Future<QuietTurns> held(WidgetTester tester) async => (await tester
      .runAsync(
        () async => QuietTurns(
          clock: QuietClock(
            held: () => true,
            quiet: () => null,
            gpuDone: () async {},
          ),
        ),
      ))!;

  testWidgets('🚨a canvas standing on it holds its folder, drawn once — a '
      'step patched in then draws none', (tester) async {
    final run = await madeAhead(tester);
    await tester.pumpWidget(
      onScreen(
        standingOn(
          run,
          picture: frame,
          nodes: treeOf(),
          viewport: view,
          live: liveRows(),
        ),
      ),
    );
    expect(
      await settleAsync(tester, () => run.pictures.heldNodes.length == 1),
      isTrue,
      reason: 'the folder is held',
    );

    debugSubtreeRasterCount = 0;
    await tester.runAsync(
      () => run.pictures.holdNodesOf(
        treeOf(),
        frame,
        shouldAbort: () => false,
      ),
    );
    expect(
      debugSubtreeRasterCount,
      0,
      reason: 'held once, it is not drawn again',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a run standing on it holds none', (tester) async {
    final run = await madeAhead(tester);
    await tester.pumpWidget(
      onScreen(
        FramePictureView(
          run: run,
          picture: frame,
          nodes: treeOf(),
          viewport: view,
          laysWhatItMisses: false,
          wholeFrames: true,
        ),
      ),
    );
    expect(
      await settleAsync(tester, () => run.pictures.store.pinnedBytes > 0),
      isTrue,
      reason: '⛔premise: the run shows the frame',
    );
    await lendBothClocks(tester, rounds: 10);
    expect(run.pictures.heldNodes, hasLength(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('🚨a hold gives its turn back — the next job is not kept '
      'waiting behind it', (tester) async {
    final turns = await held(tester);
    final run = await madeAhead(tester, turns: turns);
    await tester.runAsync(
      () => run.pictures.holdNodesOf(
        treeOf(),
        frame,
        shouldAbort: () => false,
      ),
    );
    expect(run.pictures.heldNodes, hasLength(1), reason: '⛔premise');

    final next = await tester.runAsync(
      () => Future.any([
        turns.inAQuiet(QuietSpan(), gone: () => false),
        Future<QuietTurn?>.delayed(const Duration(seconds: 2)),
      ]),
    );
    expect(next, isNotNull);
    await tester.runAsync(() => next!.landed());
  });

  testWidgets('🚨a canvas gone before its hold\'s turn holds nothing', (
    tester,
  ) async {
    final turns = await held(tester);
    final run = await madeAhead(tester, turns: turns);
    final before = await tester.runAsync(
      () => turns.inAQuiet(QuietSpan(), gone: () => false),
    );
    await tester.pumpWidget(
      onScreen(
        standingOn(
          run,
          picture: frame,
          nodes: treeOf(),
          viewport: view,
          live: liveRows(),
        ),
      ),
    );
    await lendBothClocks(tester, rounds: 3);
    expect(
      run.pictures.heldNodes,
      hasLength(0),
      reason: '⛔premise: the hold waits its turn',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => before!.landed());
    await lendBothClocks(tester, rounds: 10);
    expect(run.pictures.heldNodes, hasLength(0));
  });

  testWidgets('a hold asked off before its turn holds nothing', (
    tester,
  ) async {
    final run = await madeAhead(tester);
    await tester.runAsync(
      () => run.pictures.holdNodesOf(
        treeOf(),
        frame,
        shouldAbort: () => true,
      ),
    );
    expect(run.pictures.heldNodes, hasLength(0));
  });
}
