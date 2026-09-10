import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/playback/canvas_playback_view.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/cut_frame_composite_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';
import 'package:anicel/src/ui/playback/playback_prerender_scheduler.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/models/composite_tree.dart';

/// ⛔**A TRIPWIRE, and it now pins the OPPOSITE of what it used to.** No
/// canvas-content picture carries `willChange: true` any more; the
/// desktop (Skia) raster cache is allowed to bake the artwork again.
///
/// The full flip-flop history stays, because every losing leg here has
/// been re-proposed at least once:
///
///  · #1100 A/B — the 1px axis-aligned edge hop at pen-down / pen-up /
///    layer switch / tool buttons was device-confirmed to be Skia's
///    picture raster cache: it snaps a STABLE picture's layer to integral
///    device translation and replays the cached raster there, while live
///    repaints render at the fractional offset panel layout produced.
///    Every cache engage/disengage moment flips between the two renders.
///  · #1101 — in-picture pan snap (`renderSnappedViewport`). Owns pan
///    jitter and stays; could not touch the transition hop, because the
///    snapped coordinate is the picture LAYER's device offset, which
///    panel layout owns and no in-picture transform can see.
///  · #1103 — `willChange: true` on the editing stack's picture.
///    Device-verified: ALL transition hops gone.
///  · #1106 — retired the hint for `IntegralLayerOffset` (a post-frame
///    self-measuring wrapper above the canvas content boundary) and
///    turned the cache back on. Device 2026-08-17: the hops CAME BACK —
///    active-layer switch, tool change, wheel-click pan start, at zoom >=
///    100% only (the nearest half of the display filter law; below 1 the
///    bilinear filter hides the same phase flip). The wrapper's
///    measurement lands one frame late, so the frame OF an ancestor
///    layout change — exactly what those chrome actions produce — paints
///    with the previous compensation while the unchanged picture is still
///    CACHED, and the snap is live again.
///    ⚠️This line used to send the reader to
///    `integral_layer_offset_test.dart`. R11 retired the wrapper and its
///    test together (`53d4b39b`), because the premise went: layout does
///    not produce a fractional offset any more. What quantifies the gap
///    now is `canvas_boundary_on_grid_test.dart`'s "ON THE FRAME OF A
///    LAYOUT CHANGE" group.
///
///  · R11 — the quantization round, and why this file now pins the
///    absence. Read #1106's failure precisely: it is NOT "the wrapper is
///    weaker than the hint", it is "the wrapper MEASURES, one frame late,
///    and the jump moments are layout-change frames". R11 measures
///    nothing. Every app-chosen offset from the window origin down is an
///    integral count of device pixels IN LAYOUT, so a layout-change frame
///    is on the grid in that same frame — the hole #1106 fell into is the
///    one R11 fills, which is what makes this not a repeat of it.
///
/// ⇒ **The protection MOVED; it was not dropped.** It lives in
/// `canvas_boundary_on_grid_test.dart`, whose "ON THE FRAME OF A LAYOUT
/// CHANGE" group pumps exactly ONE frame after a panel opens and after a
/// UI-scale change, and measures the uncompensated chain at 1.25, 1.35
/// and the 1.5x0.9 product. That is the measurement #1106 never had.
///
/// 🚨The mechanism the old text asserted was wrong in any case: the engine
/// source says the hint suppresses raster CACHING but not the snap — the
/// snap applies whenever a cache entry exists, and the cache key discards
/// translation. The hint never did what this file claimed it did; what it
/// did was stop the entry from existing.
///
/// ⛔If you are re-adding a hint, you are reverting a decision. Read the
/// history above, and check the symptom first: a 1px jump of an
/// axis-aligned artwork edge when a panel opens, a tool is picked or the
/// active layer changes, at zoom >= 100%, on WINDOWS only (Impeller
/// carries no such cache, so mobile never had it).
///
///  · R12 (2026-09-11) — and that is what happened. F-67: the hop came
///    back at pen-down/up, tool change and pan, zoom >= 100%; the hands-on
///    read the pinned grid probe ON the frame: device (40, 40), fraction
///    0, ratio 1.0 — the chain on the grid at 100% scaling, the case R11
///    said cannot hop. And `the_canvas_raster_holds_still_through_a_stroke`
///    measures the boundary's own raster byte-identical through a stroke
///    at 110%. So the flip is between the engine's cached raster and its
///    live one, for a reason the snap does not name. This file now pins
///    the hint PRESENT on the two DRAWING pictures (the ones that flip
///    still↔live under the hand) and ABSENT on the two playback pictures
///    (which change every tick; a hold is the cache's win).
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
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
        frames: [Frame(id: frameId, duration: 1, strokes: const [])],
        timeline: {0: const TimelineExposure.drawing(frameId, length: 4)},
      ),
    ],
  );

  testWidgets(
    'the editing stack picture refuses the raster cache — willChange pinned '
    'PRESENT (R12 put it back)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              height: 100,
              child: CanvasLayerStackView(
                nodes: const [CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1))],
                imageCache: LayerFrameImageCache(
                  frameStore: BrushFrameStore(),
                ),
                canvasSize: const CanvasSize(width: 16, height: 16),
                viewport: CanvasViewport(zoom: 1),
                paintPaper: true,
                paperBackground: ProjectBackground.defaultBackground,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final stackPaint = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(CanvasLayerStackView),
              matching: find.byType(CustomPaint),
            ),
          )
          .firstWhere((paint) => paint.painter != null);

      expect(
        stackPaint.willChange,
        isTrue,
        reason: 'R12 put the hint back on the drawing pictures: the hop '
            'returned with the chain ON the grid at 100% scaling (F-67 '
            'hands-on, 2026-09-11), so the cached and the live render of '
            'this display list differ for a reason the snap does not name, '
            'and refusing the cache is the one switch that removes the '
            'flip by construction. If you are taking it out again, the '
            'device A/B is the only oracle — read the history at the top.',
      );
    },
  );

  testWidgets(
    'the playback view picture no longer refuses the raster cache — a paused '
    'frame goes stable and would snap on cache engage',
    (tester) async {
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
      expect(paint.painter, isA<PlaybackFramePainter>());
      expect(
        paint.willChange,
        isFalse,
        reason: 'retired with the editing stack\'s. A PAUSED playback frame '
            'is a stable picture the cache will now bake — and it bakes it '
            'at the integral translation layout already chose, so there is '
            'no hop to flip into.',
      );
    },
  );

  testWidgets(
    'no parked track-stack picture refuses the raster cache any more — a '
    'parked gap shows a still stack that would snap on cache engage',
    (tester) async {
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

      final paints = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byKey(
                const ValueKey<String>('canvas-track-stack-frames'),
              ),
              matching: find.byType(CustomPaint),
            ),
          )
          .where((paint) => paint.painter is PlaybackFramePainter)
          .toList();
      expect(paints, isNotEmpty);
      for (final paint in paints) {
        expect(
          paint.willChange,
          isFalse,
          reason: 'retired with the editing stack\'s. The parked stack is '
              'the stillest canvas content there is, so the cache engages '
              'within frames — and now that is a WIN rather than a hop, '
              'because the layer offset it bakes at is the one layout '
              'chose.',
        );
      }
    },
  );
}
