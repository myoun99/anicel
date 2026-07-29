import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/playback/canvas_playback_view.dart';
import 'package:anicel/src/ui/playback/cut_frame_composite_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';
import 'package:anicel/src/ui/playback/playback_prerender_scheduler.dart';

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  BrushFrameKey frameKey(Cut cut, LayerId layerId, FrameId frameId) =>
      BrushFrameKey(
        projectId: const ProjectId('project'),
        trackId: const TrackId('track'),
        cutId: cut.id,
        layerId: layerId,
        frameId: frameId,
      );

  Cut cut({TransformTrack? transformTrack}) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    duration: 2,
    canvasSize: canvasSize,
    transformTrack: transformTrack,
    layers: [
      Layer(
        id: const LayerId('layer'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('frame-a'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(const FrameId('frame-a'), length: 1),
        },
      ),
    ],
  );

  Project project({TransformTrack? transformTrack}) => Project(
    id: const ProjectId('project'),
    name: 'Project',
    frameRate: const ProjectFrameRate.integer(10),
    cameraSize: const CanvasSize(width: 4, height: 2),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Track',
        cuts: [cut(transformTrack: transformTrack)],
      ),
    ],
    createdAt: DateTime.utc(2026),
  );

  ({CutFrameCompositeCache composites, CanvasPlaybackController controller})
  fixture({TransformTrack? transformTrack}) {
    final store = BrushFrameStore();
    BrushFrameEditingCoordinator(
      initialFrameKey: frameKey(
        cut(),
        const LayerId('layer'),
        const FrameId('frame-a'),
      ),
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
    ).commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 1, y: 1),
          color: 0xFF000000,
          size: 2,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
    final composites = CutFrameCompositeCache(
      layerImages: LayerFrameImageCache(frameStore: store),
      frameStore: store,
      frameKeyOf: frameKey,
    );
    final controller = CanvasPlaybackController(
      resolveProject: () => project(transformTrack: transformTrack),
      resolveActiveCutId: () => const CutId('cut'),
      resolveActiveTrackId: () => const TrackId('track'),
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
    );
    return (composites: composites, controller: controller);
  }

  Future<void> pumpView(
    WidgetTester tester, {
    required CanvasPlaybackController controller,
    required CutFrameCompositeCache composites,
    bool cameraViewEnabled = false,
    ValueListenable<PrerenderProgress>? progress,
    bool Function(CutId cutId)? cutFxEnabledOf,
    bool Function(CutId cutId)? cutPictureVisibleOf,
    Widget? trackStack,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasPlaybackView(
            controller: controller,
            compositeCache: composites,
            qualityOf: () => PlaybackQuality.full,
            prerenderProgress:
                progress ?? ValueNotifier(PrerenderProgress.none),
            cameraViewEnabled: cameraViewEnabled,
            cameraFrameSize: const CanvasSize(width: 4, height: 2),
            cameraPoseOf: (cut, frameIndex) =>
                CameraPose(center: CanvasPoint(x: 4, y: 4)),
            cutFxEnabledOf: cutFxEnabledOf,
            cutPictureVisibleOf: cutPictureVisibleOf,
            trackStack: trackStack,
          ),
        ),
      ),
    );
  }

  PlaybackFramePainter painterOf(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('canvas-playback-view')),
        matching: find.byType(CustomPaint),
      ),
    );
    return paint.painter! as PlaybackFramePainter;
  }

  testWidgets('shows the warmed composite for the playback frame', (
    tester,
  ) async {
    final f = fixture();
    await tester.runAsync(() async {
      await f.composites.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );
      await f.composites.prepareComposite(
        cut: cut(),
        frameIndex: 1,
        quality: PlaybackQuality.full,
      );
    });

    f.controller.play(scope: PlaybackScope.activeCut);
    await pumpView(tester, controller: f.controller, composites: f.composites);

    expect(painterOf(tester).image, isNotNull);
    expect(painterOf(tester).cameraPose, isNull);

    f.controller.stop();
    await tester.pump();
    f.composites.dispose();
  });

  testWidgets('camera view mode projects through the frame pose', (
    tester,
  ) async {
    final f = fixture();
    f.controller.play(scope: PlaybackScope.activeCut);
    await pumpView(
      tester,
      controller: f.controller,
      composites: f.composites,
      cameraViewEnabled: true,
    );

    expect(painterOf(tester).cameraPose, isNotNull);
    expect(
      painterOf(tester).cameraFrameSize,
      const CanvasSize(width: 4, height: 2),
    );

    f.controller.stop();
    await tester.pump();
    f.composites.dispose();
  });

  testWidgets('the CUT pose (V track) reaches the painter — resolved in '
      'CAMERA space and remapped onto the canvas (R8-③) — while fade-only '
      'cuts stay on the pose-free path', (tester) async {
    // A geometric key activates the pose; the opacity lane alone must not.
    // Keys author in camera space (frame 4×2, center (2,1)); the canvas
    // (8×8) preview shifts center AND anchor by d = canvasC − frameC =
    // (2,3), so the camera-space delta replays 1:1 on the canvas.
    final posed = fixture(
      transformTrack: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 6, y: 4),
        ),
      ),
    );
    posed.controller.play(scope: PlaybackScope.activeCut);
    await pumpView(
      tester,
      controller: posed.controller,
      composites: posed.composites,
    );
    final canvasPose = painterOf(tester).cutPose;
    expect(canvasPose, isNotNull);
    expect(canvasPose!.center, CanvasPoint(x: 8, y: 7));
    expect(canvasPose.zoom, 1);
    expect(painterOf(tester).cutAnchorPoint, CanvasPoint(x: 4, y: 4));

    posed.controller.stop();
    await tester.pump();
    posed.composites.dispose();

    // The top-left snap regression: an UNTOUCHED key (= the camera-frame
    // center) must read as identity motion on the canvas — center and
    // anchor both land on the canvas center.
    final untouched = fixture(
      transformTrack: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 2, y: 1),
        ),
      ),
    );
    untouched.controller.play(scope: PlaybackScope.activeCut);
    await pumpView(
      tester,
      controller: untouched.controller,
      composites: untouched.composites,
    );
    expect(painterOf(tester).cutPose!.center, CanvasPoint(x: 4, y: 4));
    expect(painterOf(tester).cutAnchorPoint, CanvasPoint(x: 4, y: 4));

    untouched.controller.stop();
    await tester.pump();
    untouched.composites.dispose();

    final fadeOnly = fixture(
      transformTrack: TransformTrack.empty().copyWith(
        opacity: PropertyTrack<double>.empty().withKey(0, 0.5),
      ),
    );
    fadeOnly.controller.play(scope: PlaybackScope.activeCut);
    await pumpView(
      tester,
      controller: fadeOnly.controller,
      composites: fadeOnly.composites,
    );
    expect(painterOf(tester).cutPose, isNull, reason: 'zero-cost fade path');
    expect(painterOf(tester).fadeOpacity, 0.5);

    fadeOnly.controller.stop();
    await tester.pump();
    fadeOnly.composites.dispose();
  });

  testWidgets('the V-row display gates (R9): fx off bypasses the cut pose '
      'AND the fade; the eye off drops the picture (paper only)', (
    tester,
  ) async {
    // fx off: a posed + faded cut plays pose-free at full opacity.
    final posed = fixture(
      transformTrack: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 6, y: 4),
        ),
        opacity: PropertyTrack<double>.empty().withKey(0, 0.5),
      ),
    );
    posed.controller.play(scope: PlaybackScope.activeCut);
    await pumpView(
      tester,
      controller: posed.controller,
      composites: posed.composites,
      cutFxEnabledOf: (_) => false,
    );
    expect(painterOf(tester).cutPose, isNull, reason: 'pose bypassed');
    expect(painterOf(tester).fadeOpacity, 1, reason: 'fade bypassed');

    posed.controller.stop();
    await tester.pump();
    posed.composites.dispose();

    // eye off: the warmed composite is withheld from the painter — the
    // paper stays, the picture doesn't draw.
    final hidden = fixture();
    await tester.runAsync(() async {
      await hidden.composites.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );
    });
    hidden.controller.play(scope: PlaybackScope.activeCut);
    await pumpView(
      tester,
      controller: hidden.controller,
      composites: hidden.composites,
      cutPictureVisibleOf: (_) => false,
    );
    expect(painterOf(tester).image, isNull, reason: 'picture hidden');

    hidden.controller.stop();
    await tester.pump();
    hidden.composites.dispose();
  });

  testWidgets('a playlist GAP frame is a VOID (UI-R9 #2, superseding '
      'R10-⑥): picture AND paper withheld, no fade wash — the panel '
      'background shows through like the gap-parked scrub preview', (
    tester,
  ) async {
    // The single cut preceded by 3 empty frames: all-cuts playback spends
    // global frames 0..2 in the gap.
    final gapCut = cut().copyWith(leadingGapFrames: 3);
    final store = BrushFrameStore();
    final composites = CutFrameCompositeCache(
      layerImages: LayerFrameImageCache(frameStore: store),
      frameStore: store,
      frameKeyOf: frameKey,
    );
    final controller = CanvasPlaybackController(
      resolveProject: () => Project(
        id: const ProjectId('project'),
        name: 'Project',
        frameRate: const ProjectFrameRate.integer(10),
        cameraSize: const CanvasSize(width: 4, height: 2),
        tracks: [
          Track(id: const TrackId('track'), name: 'Track', cuts: [gapCut]),
        ],
        createdAt: DateTime.utc(2026),
      ),
      resolveActiveCutId: () => const CutId('cut'),
      resolveActiveTrackId: () => const TrackId('track'),
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
    );
    await tester.runAsync(() async {
      await composites.prepareComposite(
        cut: gapCut,
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );
    });

    controller.play(scope: PlaybackScope.allCuts); // global 0 = in the gap
    await pumpView(tester, controller: controller, composites: composites);
    expect(controller.position, isNull);
    expect(painterOf(tester).image, isNull, reason: 'gap shows no picture');
    expect(
      painterOf(tester).paintPaper,
      isFalse,
      reason: 'gap shows no paper either — a void, not the background',
    );
    expect(painterOf(tester).fadeOpacity, 1, reason: 'no wash in the gap');

    // Crossing into the cut restores the paper, the picture and the wash.
    controller.seekToGlobalFrame(3);
    await tester.pump();
    expect(painterOf(tester).image, isNotNull);
    expect(painterOf(tester).paintPaper, isTrue);
    expect(painterOf(tester).fadeOpacity, 1);

    controller.stop();
    await tester.pump();
    controller.dispose();
    composites.dispose();
  });

  testWidgets('cache misses keep the last displayed frame on screen', (
    tester,
  ) async {
    final f = fixture();
    await tester.runAsync(() async {
      // Only frame 0 is warmed; frame 1 will miss.
      await f.composites.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );
    });

    f.controller.play(scope: PlaybackScope.activeCut);
    await pumpView(tester, controller: f.controller, composites: f.composites);
    expect(painterOf(tester).image, isNotNull);

    // Advance to the uncached frame 1 (10fps → 100ms per frame).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(f.controller.position!.localFrameIndex, 1);
    expect(painterOf(tester).image, isNotNull, reason: 'stale frame held');

    f.controller.stop();
    await tester.pump();
    f.composites.dispose();
  });

  testWidgets('tapping the canvas cancels playback', (tester) async {
    final f = fixture();
    f.controller.play(scope: PlaybackScope.activeCut);
    await pumpView(tester, controller: f.controller, composites: f.composites);
    expect(f.controller.isActive, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-playback-view')),
    );
    await tester.pump();

    expect(f.controller.isActive, isFalse);
    f.composites.dispose();
  });

  testWidgets('canvas mode paints under the panel viewport transform', (
    tester,
  ) async {
    final f = fixture();
    f.controller.play(scope: PlaybackScope.activeCut);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasPlaybackView(
            controller: f.controller,
            compositeCache: f.composites,
            qualityOf: () => PlaybackQuality.full,
            prerenderProgress: ValueNotifier(PrerenderProgress.none),
            cameraViewEnabled: false,
            cameraFrameSize: const CanvasSize(width: 4, height: 2),
            cameraPoseOf: (cut, frameIndex) =>
                CameraPose(center: CanvasPoint(x: 4, y: 4)),
            viewport: CanvasViewport(zoom: 2, panX: 10, panY: 20),
          ),
        ),
      ),
    );

    final painter = painterOf(tester);
    expect(painter.viewport, CanvasViewport(zoom: 2, panX: 10, panY: 20));
    expect(painter.cameraPose, isNull);

    f.controller.stop();
    await tester.pump();
    f.composites.dispose();
  });

  testWidgets('pause then resume keeps ticking through the view vsync', (
    tester,
  ) async {
    final f = fixture();
    f.controller.play(scope: PlaybackScope.activeCut);
    await pumpView(tester, controller: f.controller, composites: f.composites);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(f.controller.position!.localFrameIndex, 1);

    f.controller.pause();
    await tester.pump();
    // Resume recreates the ticker: this asserted with a single-ticker
    // provider and playback stayed dead after pausing.
    f.controller.resume();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(f.controller.isPlaying, isTrue);
    expect(f.controller.position!.localFrameIndex, 0, reason: '2-frame wrap');
    expect(tester.takeException(), isNull);

    f.controller.stop();
    await tester.pump();
    f.composites.dispose();
  });

  testWidgets('shows warming progress while the cache fills', (tester) async {
    final f = fixture();
    final progress = ValueNotifier(
      const PrerenderProgress(cached: 1, total: 4),
    );

    f.controller.play(scope: PlaybackScope.activeCut);
    await pumpView(
      tester,
      controller: f.controller,
      composites: f.composites,
      progress: progress,
    );

    expect(
      find.byKey(const ValueKey<String>('canvas-playback-progress')),
      findsOneWidget,
    );
    expect(find.text('caching 1/4'), findsOneWidget);

    progress.value = const PrerenderProgress(cached: 4, total: 4);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('canvas-playback-progress')),
      findsNothing,
    );

    f.controller.stop();
    await tester.pump();
    f.composites.dispose();
  });

  testWidgets('with a trackStack the STACK is the frame (R3a): no single-'
      'cut painter runs, and the view keeps its own jobs — the ticker and '
      'tap-to-stop', (tester) async {
    final f = fixture();
    f.controller.play(scope: PlaybackScope.allCuts);

    await pumpView(
      tester,
      controller: f.controller,
      composites: f.composites,
      trackStack: const ColoredBox(
        key: ValueKey<String>('stack-stand-in'),
        color: Color(0xFF000000),
      ),
    );

    expect(find.byKey(const ValueKey<String>('stack-stand-in')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('canvas-playback-view')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is PlaybackFramePainter,
        ),
      ),
      findsNothing,
      reason: 'the stack paints the frame; the single-cut painter stands down',
    );

    expect(f.controller.isActive, isTrue);
    await tester.tap(find.byKey(const ValueKey<String>('canvas-playback-view')));
    await tester.pump();
    expect(f.controller.isActive, isFalse, reason: 'tap-to-stop survives');

    f.composites.dispose();
  });
}
