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
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/draw_on_current_frame.dart';

/// playback-plays-the-screen-material ③ (10-09): a RUN the canvas plays
/// changes frames WHOLE — a frame whose rows are not all there leaves the
/// last whole one on screen, as a run's composite always did — and makes
/// none of its rows itself: the run's maker makes them, and the view takes
/// each as it lands.
///
/// 유저 2026-10-08: 「재생했는데 재생바는 지나가고있는데 그림이 없어서
/// 비어있다던가」. Standing still the canvas shows rows as they come, as it
/// always has; only a run holds a frame back.
void main() {
  const canvasSize = CanvasSize(width: 16, height: 16);
  const tileSize = 16;
  const blue = 0xFF0000FF;
  const red = 0xFFFF0000;
  final screen = GlobalKey();

  BrushFrameKey keyOf(String cel) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
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

  /// What a run's maker does for a row: its image, at the level the view
  /// draws at.
  Future<void> make(
    WidgetTester tester,
    LayerFrameImageCache cache,
    String cel, {
    PlaybackQuality quality = PlaybackQuality.full,
  }) => tester.runAsync(
    () => cache.prepare(
      key: keyOf(cel),
      canvasSize: canvasSize,
      quality: quality,
      sourceEffects: const [],
      inkSuffices: true,
    ),
  );

  Future<void> pumpStack(
    WidgetTester tester,
    LayerFrameImageCache cache,
    List<CompositeNode<CanvasStackRow>> nodes, {
    StackRun? run,
    CanvasViewport? viewport,
    bool wholeFrames = false,
  }) {
    // One canvas pixel a device pixel at 100%: the middle is the middle.
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: screen,
            child: SizedBox(
              width: 16,
              height: 16,
              child: CanvasLayerStackView(
                nodes: nodes,
                imageCache: cache,
                canvasSize: canvasSize,
                viewport: viewport ?? CanvasViewport(),
                // The law is what this frame's paint draws, not what a kept
                // composite re-serves.
                debugDisableBake: true,
                run: run,
                wholeFrames: wholeFrames,
              ),
            ),
          ),
        ),
      ),
    );
  }

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


  testWidgets('🚨under a run, a frame whose rows are not all there leaves the '
      'last whole frame on screen — and goes up when they land', (
    tester,
  ) async {
    final cache = images();
    addTearDown(cache.dispose);
    final landings = ValueNotifier<int>(0);
    addTearDown(landings.dispose);
    final StackRun run = (landings: landings, gaveUpOn: (_) => false);
    await make(tester, cache, 'blue');

    await pumpStack(tester, cache, frameOf('blue'), run: run);
    expect(await middle(tester), blue, reason: '⛔premise: blue is up');

    await pumpStack(tester, cache, frameOf('red'), run: run);
    expect(
      await middle(tester),
      blue,
      reason: 'red is not made yet: the whole frame before it stays',
    );

    await make(tester, cache, 'red');
    landings.value += 1;
    await tester.pump();
    expect(await middle(tester), red, reason: 'it landed: the frame goes up');
  });

  testWidgets('🚨a view that stood still before the run hears its landings — '
      'the run comes to it as an update, and the frame goes up when its rows '
      'land', (tester) async {
    final cache = images();
    addTearDown(cache.dispose);
    final landings = ValueNotifier<int>(0);
    addTearDown(landings.dispose);
    await make(tester, cache, 'blue');

    // Standing still first: the run then comes to THIS view, which the
    // canvas keeps across a run's start (a_cut_played_alone_plays_on_the_
    // canvas_test pins that).
    await pumpStack(tester, cache, frameOf('blue'));
    expect(await middle(tester), blue, reason: '⛔premise: blue is up');

    await pumpStack(
      tester,
      cache,
      frameOf('red'),
      run: (landings: landings, gaveUpOn: (_) => false),
    );
    expect(await middle(tester), blue, reason: 'red is not made yet');

    await make(tester, cache, 'red');
    landings.value += 1;
    await tester.pump();
    expect(
      await middle(tester),
      red,
      reason: 'it landed, and the view that took the run on heard it',
    );
  });

  testWidgets('standing still, rows come as they are made: a frame not made '
      'yet is not held back', (tester) async {
    final cache = images();
    addTearDown(cache.dispose);
    await make(tester, cache, 'blue');

    await pumpStack(tester, cache, frameOf('blue'));
    expect(await middle(tester), blue, reason: '⛔premise');

    await pumpStack(tester, cache, frameOf('red'));
    expect(
      await middle(tester),
      isNot(blue),
      reason: 'no run: the frame asked for is the frame shown',
    );
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
    await make(tester, cache, 'blue');

    await pumpStack(tester, cache, frameOf('blue'), wholeFrames: true);
    expect(await middle(tester), blue, reason: '⛔premise: blue is up');

    await pumpStack(tester, cache, frameOf('red'), wholeFrames: true);
    expect(
      await middle(tester),
      blue,
      reason: 'red is not made yet: the whole frame before it stays',
    );

    // No run: the view makes red itself.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(await middle(tester), red, reason: 'its own make landed: up');
  });

  testWidgets('🚨under a run the view makes none of its rows — the run\'s '
      'maker does; standing still it makes what it lacks', (tester) async {
    final cache = images();
    addTearDown(cache.dispose);
    final landings = ValueNotifier<int>(0);
    addTearDown(landings.dispose);
    bool redIsMade() =>
        cache.validImageOrNull(
          keyOf('red'),
          PlaybackQuality.full,
          canvasSize: canvasSize,
          sourceEffects: const [],
        ) !=
        null;

    await pumpStack(
      tester,
      cache,
      frameOf('red'),
      run: (landings: landings, gaveUpOn: (_) => false),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(redIsMade(), isFalse, reason: 'a run\'s rows are its maker\'s');

    await pumpStack(tester, cache, frameOf('red'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(redIsMade(), isTrue, reason: 'standing still, the view makes it');
  });

  testWidgets('a frame waits for nothing that will not come: a row the maker '
      'gave up on, or one with nothing in it, is there', (tester) async {
    final cache = images();
    addTearDown(cache.dispose);
    final landings = ValueNotifier<int>(0);
    addTearDown(landings.dispose);
    await make(tester, cache, 'blue');
    await pumpStack(
      tester,
      cache,
      frameOf('blue'),
      run: (landings: landings, gaveUpOn: (row) => row.frameKey == keyOf('red')),
    );
    expect(await middle(tester), blue, reason: '⛔premise');

    await pumpStack(
      tester,
      cache,
      frameOf('red'),
      run: (landings: landings, gaveUpOn: (row) => row.frameKey == keyOf('red')),
    );
    expect(
      await middle(tester),
      isNot(blue),
      reason: 'red was given up on: the frame goes up without it',
    );

    await make(tester, cache, 'blue');
    await pumpStack(
      tester,
      cache,
      frameOf('blue'),
      run: (landings: landings, gaveUpOn: (_) => false),
    );
    await pumpStack(
      tester,
      cache,
      frameOf('empty'),
      run: (landings: landings, gaveUpOn: (_) => false),
    );
    expect(
      await middle(tester),
      isNot(blue),
      reason: 'a cel with nothing in it is nothing still to come',
    );
  });

  testWidgets('under a run the view asks its rows at the level of the view it '
      'is seen through — the one the warmer makes them at', (tester) async {
    final cache = images();
    addTearDown(cache.dispose);
    final landings = ValueNotifier<int>(0);
    addTearDown(landings.dispose);
    // The canvas at 40%, over the middle the probe reads.
    final view = CanvasViewport(zoom: 0.4, panX: 5, panY: 5);
    final level = rowQualityThrough(view, 1);
    expect(level, PlaybackQuality.half, reason: '⛔premise: 40% is a level');

    await make(tester, cache, 'blue');
    await pumpStack(
      tester,
      cache,
      frameOf('blue'),
      run: (landings: landings, gaveUpOn: (_) => false),
      viewport: view,
    );
    expect(
      await middle(tester),
      isNot(blue),
      reason: 'made at full, asked at half: not there yet',
    );

    await make(tester, cache, 'blue', quality: level);
    landings.value += 1;
    await tester.pump();
    expect(await middle(tester), blue, reason: 'made at its level, it is');
  });
}
