import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../../helpers/draw_on_current_frame.dart';

/// playback-plays-the-screen-material ③ (10-09): a RUN the canvas plays
/// changes frames WHOLE — a frame that is not there yet leaves the last
/// whole one on screen — and makes nothing itself: the run's maker makes
/// each frame's one picture (one-picture-per-frame ②-2), and the view
/// takes each as it lands ([FramePictureView]).
///
/// 유저 2026-10-08: 「재생했는데 재생바는 지나가고있는데 그림이 없어서
/// 비어있다던가」. Standing still the canvas shows rows as they come, as it
/// always has ([CanvasLayerStackView]); only a run holds a frame back.
///
/// ↩️The canvas stacked a run's frame from its rows' images
/// (`CanvasLayerStackView.run`), each asked at the level of the view it was
/// seen through, until a frame became one picture.
void main() {
  const canvasSize = CanvasSize(width: 16, height: 16);
  const tileSize = 16;
  const blue = 0xFF0000FF;
  const red = 0xFFFF0000;
  final screen = GlobalKey();

  final cut = Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 3,
    canvasSize: canvasSize,
    layers: const [],
  );

  BrushFrameKey keyOf(String cel) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: cut.id,
    layerId: const LayerId('l'),
    frameId: FrameId(cel),
  );

  /// Two cels, each its colour over the whole canvas, and one with nothing
  /// in it.
  LayerFrameImageCache images() {
    final store = BrushFrameStore();
    for (final (cel, colour) in [('blue', blue), ('red', red)]) {
      inkCelIn(
        store,
        keyOf(cel),
        canvasSize: canvasSize,
        at: CanvasPoint(x: 8, y: 8),
        size: 14,
        tipShape: BrushTipShape.square,
        color: colour,
        tileSize: tileSize,
      );
    }
    return LayerFrameImageCache(frameStore: store);
  }

  /// A frame that is [cel]'s picture alone.
  List<CompositeNode<CanvasStackRow>> frameOf(String cel) => [
    CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: keyOf(cel), opacity: 1),
    ),
  ];

  /// The cel each frame of the cut shows.
  const cels = ['blue', 'red', 'empty'];

  /// The run's frames' pictures, drawn of [cache]'s cels — frame 0 blue,
  /// 1 red, 2 a cel with nothing in it.
  FramePictures picturesOver(LayerFrameImageCache cache) {
    final store = FramePictureStore<FramePictureKey>();
    addTearDown(store.dispose);
    return FramePictures(
      store: store,
      layerImages: cache,
      stackOf: (picture) => frameOf(cels[picture.frameIndex]),
      pageOf: (picture) => (
        canvasSize: picture.cut.canvasSize,
        pasteboardReach: PasteboardReach.none,
        paintPaper: picture.paintPaper,
        paperBackground: ProjectBackground.defaultBackground,
      ),
    );
  }

  DemandedPicture at(String cel, {bool paintPaper = true}) =>
      (cut: cut, frameIndex: cels.indexOf(cel), paintPaper: paintPaper);

  /// What a run's maker does for a frame: its one picture.
  Future<void> makePicture(
    WidgetTester tester,
    FramePictures pictures,
    String cel, {
    bool paintPaper = true,
  }) => tester.runAsync(
    () => pictures.make(
      at(cel, paintPaper: paintPaper),
      shouldAbort: () => false,
    ),
  );

  /// What the canvas standing still makes for a row: its image.
  Future<void> makeRow(
    WidgetTester tester,
    LayerFrameImageCache cache,
    String cel,
  ) => tester.runAsync(
    () => cache.prepare(
      key: keyOf(cel),
      canvasSize: canvasSize,
      quality: PlaybackQuality.full,
      sourceEffects: const [],
      inkSuffices: true,
    ),
  );

  Future<void> pumpScreen(WidgetTester tester, Widget view) {
    // One canvas pixel a device pixel at 100%: the middle is the middle.
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: screen,
            child: SizedBox(width: 16, height: 16, child: view),
          ),
        ),
      ),
    );
  }

  /// The canvas playing a run: [cel]'s frame, as the run's maker made it.
  Future<void> pumpRun(
    WidgetTester tester,
    StackRun run,
    String cel, {
    CanvasViewport? viewport,
    bool paintPaper = true,
  }) => pumpScreen(
    tester,
    FramePictureView(
      run: run,
      picture: at(cel, paintPaper: paintPaper),
      nodes: frameOf(cel),
      viewport: viewport ?? CanvasViewport(),
    ),
  );

  /// The canvas standing still on [cel]'s frame.
  Future<void> pumpStill(
    WidgetTester tester,
    LayerFrameImageCache cache,
    String cel, {
    bool wholeFrames = false,
  }) => pumpScreen(
    tester,
    CanvasLayerStackView(
      nodes: frameOf(cel),
      imageCache: cache,
      canvasSize: canvasSize,
      viewport: CanvasViewport(),
      // The law is what this frame's paint draws, not what a kept
      // composite re-serves.
      debugDisableBake: true,
      wholeFrames: wholeFrames,
    ),
  );

  /// The colour at the middle of what the last pump put on screen.
  Future<int> middle(WidgetTester tester) async {
    final render =
        screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final argb = await tester.runAsync(() async {
      final image = await render.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      final rgba = data!.buffer.asUint8List();
      const o = (8 * 16 + 8) * 4;
      return (rgba[o + 3] << 24) |
          (rgba[o] << 16) |
          (rgba[o + 1] << 8) |
          rgba[o + 2];
    });
    return argb!;
  }

  Future<void> aWhile(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  ({StackRun run, ValueNotifier<int> landings}) runOver(
    FramePictures pictures,
  ) {
    final landings = ValueNotifier<int>(0);
    addTearDown(landings.dispose);
    return (run: (landings: landings, pictures: pictures), landings: landings);
  }

  testWidgets('🚨under a run, a frame whose picture is not there leaves the '
      'last whole frame on screen — and goes up when it lands', (
    tester,
  ) async {
    final cache = images();
    addTearDown(cache.dispose);
    final pictures = picturesOver(cache);
    final (:run, :landings) = runOver(pictures);
    await makePicture(tester, pictures, 'blue');

    await pumpRun(tester, run, 'blue');
    expect(await middle(tester), blue, reason: '⛔premise: blue is up');

    await pumpRun(tester, run, 'red');
    expect(
      await middle(tester),
      blue,
      reason: 'red is not made yet: the whole frame before it stays',
    );

    await makePicture(tester, pictures, 'red');
    landings.value += 1;
    await tester.pump();
    expect(await middle(tester), red, reason: 'it landed: the frame goes up');
  });

  testWidgets('🚨under a run the view makes nothing — the run\'s maker does',
      (tester) async {
    final cache = images();
    addTearDown(cache.dispose);
    final pictures = picturesOver(cache);
    final (:run, landings: _) = runOver(pictures);

    await pumpRun(tester, run, 'red');
    await aWhile(tester);
    expect(
      pictures.has(at('red')),
      isFalse,
      reason: 'a run\'s frames are its maker\'s',
    );
    expect(cache.estimatedBytes, 0, reason: 'nor a row of it');
  });

  testWidgets('a frame waits for nothing that will not come: one the maker '
      'gave up on is drawn as its cels stand, and one of nothing is its page '
      'alone — on its paper or not, and nothing of it made', (tester) async {
    final cache = images();
    addTearDown(cache.dispose);
    final pictures = picturesOver(cache);
    final (:run, landings: _) = runOver(pictures);
    await makePicture(tester, pictures, 'blue');
    await pumpRun(tester, run, 'blue');
    expect(await middle(tester), blue, reason: '⛔premise');

    pictures.noteFailure(at('red'));
    await pumpRun(tester, run, 'red');
    expect(
      await middle(tester),
      red,
      reason: 'red was given up on: the frame goes up as its cels stand',
    );
    expect(pictures.store.peek(pictures.keyOf(at('red'))), isNull);

    await pumpRun(tester, run, 'empty');
    expect(
      await middle(tester),
      ProjectBackground.defaultPaperArgb,
      reason: 'a cel with nothing in it, on its paper, is the paper — '
          'nothing still to come',
    );
    expect(
      pictures.store.estimatedBytes,
      pictures.store.bytesOf(pictures.keyOf(at('blue'))),
      reason: 'and no picture of the paper is made: blue\'s is all there is',
    );

    await makePicture(tester, pictures, 'blue', paintPaper: false);
    await pumpRun(tester, run, 'blue', paintPaper: false);
    expect(await middle(tester), blue, reason: '⛔premise');
    await pumpRun(tester, run, 'empty', paintPaper: false);
    expect(
      await middle(tester),
      0,
      reason: 'a cel with nothing in it, on no paper, is nothing still to '
          'come',
    );
  });

  testWidgets('🎯a run\'s frame is its one picture whatever the view it is '
      'seen through — the one the warmer made (D7-2-Q2)', (tester) async {
    final cache = images();
    addTearDown(cache.dispose);
    final pictures = picturesOver(cache);
    final (:run, landings: _) = runOver(pictures);
    // The canvas at 40%, over the middle the probe reads.
    final view = CanvasViewport(zoom: 0.4, panX: 5, panY: 5);
    expect(
      rowQualityThrough(view, 1),
      PlaybackQuality.half,
      reason: '⛔premise: 40% is a level a row would be asked at',
    );

    await makePicture(tester, pictures, 'blue');
    await pumpRun(tester, run, 'blue', viewport: view);
    expect(await middle(tester), blue, reason: 'one picture, no level');
  });

  testWidgets('🚨the frame on screen is held for the view — the budget lets '
      'go of it only once the view lets go', (tester) async {
    final cache = images();
    addTearDown(cache.dispose);
    final pictures = picturesOver(cache);
    final (:run, :landings) = runOver(pictures);
    final store = pictures.store;
    final blueKey = pictures.keyOf(at('blue'));
    await makePicture(tester, pictures, 'blue');
    await pumpRun(tester, run, 'blue');

    store.enforceBudget(maxBytes: 0, wantedAt: (_) => null);
    expect(store.peek(blueKey), isNotNull, reason: 'it is on screen');
    expect(await middle(tester), blue);

    await makePicture(tester, pictures, 'red');
    await pumpRun(tester, run, 'red');
    landings.value += 1;
    await tester.pump();
    expect(await middle(tester), red, reason: '⛔premise: red took its place');
    store.enforceBudget(maxBytes: 0, wantedAt: (_) => null);
    expect(store.peek(blueKey), isNull, reason: 'no screen holds it now');

    await tester.pumpWidget(const SizedBox());
    expect(store.pinnedBytes, 0, reason: 'a view gone holds nothing');
  });

  testWidgets('standing still, rows come as they are made: a frame not made '
      'yet is not held back — the view makes what it lacks', (tester) async {
    final cache = images();
    addTearDown(cache.dispose);
    await makeRow(tester, cache, 'blue');

    await pumpStill(tester, cache, 'blue');
    expect(await middle(tester), blue, reason: '⛔premise');

    await pumpStill(tester, cache, 'red');
    expect(
      await middle(tester),
      isNot(blue),
      reason: 'no run: the frame asked for is the frame shown',
    );
    await aWhile(tester);
    expect(await middle(tester), red, reason: 'the view made it');
  });

  /// F-206 (유저 2026-09-28: 「스크럽하던 뭐던 존재하는게 보여야함」): the
  /// track stack's cuts make their own rows and change frames whole, so a
  /// drag that parks one frame after another shows the last whole frame
  /// instead of a cut's bare paper.
  testWidgets('🚨changing frames whole is its own question: a view that makes '
      'its rows itself holds the last whole frame until its own make lands',
      (tester) async {
    final cache = images();
    addTearDown(cache.dispose);
    await makeRow(tester, cache, 'blue');

    await pumpStill(tester, cache, 'blue', wholeFrames: true);
    expect(await middle(tester), blue, reason: '⛔premise: blue is up');

    await pumpStill(tester, cache, 'red', wholeFrames: true);
    expect(
      await middle(tester),
      blue,
      reason: 'red is not made yet: the whole frame before it stays',
    );

    await aWhile(tester);
    expect(await middle(tester), red, reason: 'its own make landed: up');
  });
}
