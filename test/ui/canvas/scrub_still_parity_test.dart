import 'dart:ui' as ui;

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
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/playback/canvas_playback_view.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/cut_frame_composite_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';
import 'package:anicel/src/ui/playback/playback_prerender_scheduler.dart';
import 'package:anicel/src/ui/storyboard_timeline_layout.dart';

/// 🚨★★★ SCRUB ↔ STILL PARITY (device report B2, 2026-08-17).
///
/// 「재생도 스크럽도 편집 캔버스」 — a ruler scrub serves the PLAYBACK
/// composite route ([PlaybackFramePainter] over the cut-frame composite
/// cache) while rest serves the EDITING stack ([CanvasLayerStackView]'s
/// buffer blit). The device saw the whole picture disagree by 1px on
/// axis-aligned edges between the two ("반올림"), at fractional device
/// phase (DPR 1.25/1.5 — where "100%" is still a fractional resample).
///
/// The mechanism was the blit filter: the editing buffer follows the T21
/// display law (`filterQualityForDisplayScale` — magnified/1:1 `none`,
/// reduced `low`) while the playback painter hardcoded `low`, so the same
/// canvas-resolution pixels under the same snapped transform landed
/// bilinear on one route and nearest on the other.
///
/// This file is the parity pin: the SAME cel content rendered through both
/// routes at fractional pan and a fractional DPR must be byte-identical at
/// device resolution. Plus the wiring pins: the two playback view mounts
/// must hand the painter the view's real DPR ((#1101's pan-phase snap) — a
/// route snapping at 1.0 while the other snaps at 1.25 is exactly a
/// whole-picture 1px disagreement).
///
/// ⚠️Scope of the law: it joins at the draw that IS the editing canvas's
/// one resample — canvas mode, canvas-resolution composite. Reduced-quality
/// caches (Half/Quarter) keep their bilinear upscale and can never be
/// byte-equal to the editing canvas — that is the quality setting, not a
/// parity bug. Camera mode projects through a pose the editing canvas
/// never renders, so there is nothing there to be byte-equal to.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const background = ProjectBackground.color(0xFFFFFFFF);
  const projectId = ProjectId('project');
  const trackId = TrackId('track');
  const cutId = CutId('cut');
  const layerId = LayerId('layer');
  const frameId = FrameId('frame-a');

  BrushFrameKey frameKey(Cut cut, LayerId layer, FrameId frame) =>
      BrushFrameKey(
        projectId: projectId,
        trackId: trackId,
        cutId: cut.id,
        layerId: layer,
        frameId: frame,
      );

  Cut cut() => Cut(
    id: cutId,
    name: 'Cut',
    duration: 4,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: layerId,
        name: 'A',
        frames: [
          Frame(id: frameId, duration: 1, strokes: const []),
        ],
        timeline: {0: TimelineExposure.drawing(frameId, length: 4)},
      ),
    ],
  );

  /// A hard-edged square of ink: the axis-aligned edges the device report
  /// names are what nearest-vs-bilinear disagree about at fractional
  /// device phase. A blank canvas would pass with the bug in place.
  BrushFrameStore storeWithInk() {
    final store = BrushFrameStore();
    BrushFrameEditingCoordinator(
      initialFrameKey: frameKey(cut(), layerId, frameId),
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
          center: CanvasPoint(x: 4, y: 4),
          color: 0xFF000000,
          size: 4,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.square,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
    return store;
  }

  /// Rasterizes [painter] the way the compositor does: DPR as the root
  /// scale, bytes at DEVICE resolution — the grid the device report's 1px
  /// disagreements live on. Rasterizing at logical resolution would erase
  /// exactly the fractional phase under test.
  Future<Uint8List> rasterize(
    WidgetTester tester,
    CustomPainter painter, {
    required Size logicalSize,
    required double dpr,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Offset.zero & (logicalSize * dpr),
    );
    canvas.scale(dpr);
    painter.paint(canvas, logicalSize);
    final picture = recorder.endRecording();
    try {
      final image = await tester.runAsync(
        () => picture.toImage(
          (logicalSize.width * dpr).round(),
          (logicalSize.height * dpr).round(),
        ),
      );
      final bytes = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      return bytes!.buffer.asUint8List();
    } finally {
      picture.dispose();
    }
  }

  /// Whether any pixel is the dab's opaque black — the "did the code under
  /// test actually run" oracle for both routes.
  bool hasInk(Uint8List rgba) {
    for (var i = 0; i < rgba.length; i += 4) {
      if (rgba[i] == 0 &&
          rgba[i + 1] == 0 &&
          rgba[i + 2] == 0 &&
          rgba[i + 3] == 255) {
        return true;
      }
    }
    return false;
  }

  int diffingPixels(Uint8List a, Uint8List b) {
    expect(a.length, b.length);
    var diffs = 0;
    for (var i = 0; i < a.length; i += 4) {
      if (a[i] != b[i] ||
          a[i + 1] != b[i + 1] ||
          a[i + 2] != b[i + 2] ||
          a[i + 3] != b[i + 3]) {
        diffs += 1;
      }
    }
    return diffs;
  }

  /// The EDITING route: the layer stack view's painter, pumped so the
  /// MediaQuery DPR reaches it exactly as the panel wires it.
  ///
  /// 🚨The layer image must be warmed under [WidgetTester.runAsync] BEFORE
  /// the pump: its build crosses real async (tile decode), which never
  /// lands under the fake clock — the first draft of this test compared a
  /// paper-only editing render and counted the whole ink block as "diff".
  /// The ink guard in [expectRouteParity] is what keeps that lie
  /// impossible.
  Future<CustomPainter> editingPainter(
    WidgetTester tester, {
    required BrushFrameStore store,
    required CanvasViewport viewport,
    required Size logicalSize,
  }) async {
    final images = LayerFrameImageCache(frameStore: store);
    await tester.runAsync(
      () => images.prepare(
        key: frameKey(cut(), layerId, frameId),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: logicalSize.width,
              height: logicalSize.height,
              child: CanvasLayerStackView(
                nodes: [
                  CanvasLayerImageNode(
                    CanvasLayerImageRequest(
                      frameKey: frameKey(cut(), layerId, frameId),
                      opacity: 1,
                    ),
                  ),
                ],
                imageCache: images,
                canvasSize: canvasSize,
                viewport: viewport,
                paintPaper: true,
                paperBackground: background,
              ),
            ),
          ),
        ),
      ),
    );
    // Warm first, then look — the image cache resolves rows on a later
    // pass (single_buffer_render_parity_test's trap).
    await tester.pumpAndSettle();
    final painted = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .toList();
    expect(painted, isNotEmpty);
    return painted.first.painter!;
  }

  Future<void> expectRouteParity(
    WidgetTester tester, {
    required double zoom,
    required double dpr,
    required Offset pan,
  }) async {
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.resetDevicePixelRatio);
    // Canvas edges land integral on the device grid (canvas · zoom · dpr
    // is whole) so the paper's own edge cannot confound the count; the
    // INK edges land fractional, which is where the two samplings answer
    // differently.
    const logicalSize = Size(16, 16);
    final viewport = CanvasViewport(zoom: zoom, panX: pan.dx, panY: pan.dy);

    final store = storeWithInk();
    final editing = await editingPainter(
      tester,
      store: store,
      viewport: viewport,
      logicalSize: logicalSize,
    );
    final editingBytes = await rasterize(
      tester,
      editing,
      logicalSize: logicalSize,
      dpr: dpr,
    );
    // 계측기를 먼저 의심하라: with no ink on either side the comparison
    // passes without the code under test ever running.
    expect(
      hasInk(editingBytes),
      isTrue,
      reason: 'the editing render must contain the drawn ink — a paper-only '
          'render means the layer image never resolved and the parity below '
          'would be vacuous.',
    );

    // The PLAYBACK route's picture: the real composite cache image (what
    // a scrub's parked track stack serves), through the real painter, at
    // the same viewport and DPR the views wire.
    final composites = CutFrameCompositeCache(
      layerImages: LayerFrameImageCache(frameStore: store),
      frameStore: store,
      frameKeyOf: frameKey,
    );
    addTearDown(composites.dispose);
    final composite = (await tester.runAsync(
      () => composites.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      ),
    ))!;
    final playback = PlaybackFramePainter(
      image: composite,
      canvasSize: canvasSize,
      viewport: viewport,
      devicePixelRatio: dpr,
      paperBackground: background,
    );
    final playbackBytes = await rasterize(
      tester,
      playback,
      logicalSize: logicalSize,
      dpr: dpr,
    );
    expect(hasInk(playbackBytes), isTrue);

    expect(
      diffingPixels(editingBytes, playbackBytes),
      0,
      reason:
          'zoom $zoom · dpr $dpr · pan $pan: the scrub/playback route and '
          'the editing stack must be the same pixels — a nonzero count is '
          'the device report\'s "반올림" (one route resampling bilinear '
          'while the other snaps nearest, or one snapping at the wrong '
          'DPR).',
    );
  }

  group('scrub ↔ still parity: both routes are the same pixels', () {
    testWidgets('at 100% zoom on a 1.25 DPR monitor, fractional pan', (
      tester,
    ) async {
      await expectRouteParity(
        tester,
        zoom: 1,
        dpr: 1.25,
        pan: const Offset(3.3, 2.7),
      );
    });

    testWidgets('at 150% zoom on a 1.5 DPR monitor, fractional pan', (
      tester,
    ) async {
      await expectRouteParity(
        tester,
        zoom: 1.5,
        dpr: 1.5,
        pan: const Offset(1.7, 0.6),
      );
    });
  });

  testWidgets(
    'a reduced-quality cache keeps its bilinear upscale (not the law\'s '
    'subject)',
    (tester) async {
      // The parity law joins ONLY at the canvas-resolution draw. A
      // Half/Quarter cache upscales inside the same drawImageRect, and
      // that upscale keeps today's bilinear — nearest here would turn
      // every degraded playback frame blocky, a look the editing canvas
      // never produces. The oracle: bilinear leaves intermediate grays
      // along the ink's edge; nearest leaves none.
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = storeWithInk();
      final composites = CutFrameCompositeCache(
        layerImages: LayerFrameImageCache(frameStore: store),
        frameStore: store,
        frameKeyOf: frameKey,
      );
      addTearDown(composites.dispose);
      final half = (await tester.runAsync(
        () => composites.prepareComposite(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.half,
        ),
      ))!;
      expect(half.width, lessThan(canvasSize.width));
      final painter = PlaybackFramePainter(
        image: half,
        canvasSize: canvasSize,
        viewport: CanvasViewport(),
        devicePixelRatio: 1.0,
        paperBackground: background,
      );
      final bytes = await rasterize(
        tester,
        painter,
        logicalSize: const Size(8, 8),
        dpr: 1.0,
      );
      var intermediates = 0;
      for (var i = 0; i < bytes.length; i += 4) {
        if (bytes[i + 3] == 255 && bytes[i] > 16 && bytes[i] < 240) {
          intermediates += 1;
        }
      }
      expect(
        intermediates,
        greaterThan(0),
        reason: 'the half cache\'s upscale must stay bilinear — zero '
            'intermediate grays means the display law leaked into the '
            'degraded tiers and playback at Half went blocky.',
      );
    },
  );

  group('the playback mounts wire the view\'s real DPR', () {
    // A route that snaps its pan at DPR 1.0 while the editing stack snaps
    // at 1.25/1.5 is a whole-picture 1px disagreement at fractional pans
    // — the #1101 report's exact shape. MediaQuery is the source both
    // routes must read.
    testWidgets('the parked track stack (what a ruler scrub serves)', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = BrushFrameStore();
      final composites = CutFrameCompositeCache(
        layerImages: LayerFrameImageCache(frameStore: store),
        frameStore: store,
        frameKeyOf: frameKey,
      );
      addTearDown(composites.dispose);
      final project = Project(
        id: projectId,
        name: 'Project',
        cameraSize: canvasSize,
        tracks: [
          Track(id: trackId, name: 'Track', cuts: [cut()]),
        ],
        createdAt: DateTime.utc(2026),
      );
      final layout = buildStoryboardTimelineLayout(project);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanvasTrackStackView(
              globalFrame: ValueNotifier<int?>(0),
              positionsOf: (globalFrame) => resolveTrackStackContributions(
                layout: layout,
                spansOf: (_) => const [],
                globalFrameIndex: globalFrame,
              ),
              compositeCache: composites,
              qualityOf: () => PlaybackQuality.full,
              cameraFrameSize: canvasSize,
              cameraViewEnabled: false,
              cameraPoseOf: (cut, frameIndex) =>
                  CameraPose(center: CanvasPoint(x: 4, y: 4)),
              pasteboardArgb: 0xFF123456,
            ),
          ),
        ),
      );

      final painters = [
        for (final paint in tester.widgetList<CustomPaint>(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('canvas-track-stack-frames'),
            ),
            matching: find.byType(CustomPaint),
          ),
        ))
          paint.painter! as PlaybackFramePainter,
      ];
      expect(painters, isNotEmpty);
      for (final painter in painters) {
        expect(
          painter.devicePixelRatio,
          1.5,
          reason: 'the track stack must hand the painter the view\'s DPR — '
              'a 1.0 default snaps the pan to a different grid than the '
              'editing stack and the whole picture hops on scrub.',
        );
      }
    });

    testWidgets('the playback view', (tester) async {
      tester.view.devicePixelRatio = 1.25;
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = BrushFrameStore();
      final composites = CutFrameCompositeCache(
        layerImages: LayerFrameImageCache(frameStore: store),
        frameStore: store,
        frameKeyOf: frameKey,
      );
      addTearDown(composites.dispose);
      final controller = CanvasPlaybackController(
        resolveProject: () => Project(
          id: projectId,
          name: 'Project',
          frameRate: const ProjectFrameRate.integer(10),
          cameraSize: canvasSize,
          tracks: [
            Track(id: trackId, name: 'Track', cuts: [cut()]),
          ],
          createdAt: DateTime.utc(2026),
        ),
        resolveActiveCutId: () => cutId,
        resolveActiveTrackId: () => trackId,
        resolveFrameRate: () => const ProjectFrameRate.integer(10),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanvasPlaybackView(
              controller: controller,
              compositeCache: composites,
              qualityOf: () => PlaybackQuality.full,
              prerenderProgress: ValueNotifier(PrerenderProgress.none),
              cameraViewEnabled: false,
              cameraFrameSize: canvasSize,
              cameraPoseOf: (cut, frameIndex) =>
                  CameraPose(center: CanvasPoint(x: 4, y: 4)),
            ),
          ),
        ),
      );

      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('canvas-playback-view')),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(
        (paint.painter! as PlaybackFramePainter).devicePixelRatio,
        1.25,
      );
    });
  });
}
