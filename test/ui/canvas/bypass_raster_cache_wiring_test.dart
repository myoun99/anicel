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
import 'package:anicel/src/ui/storyboard_timeline_layout.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';

/// ★★FINAL LAW: every canvas-content picture that draws artwork-aligned
/// edges carries `willChange: true` — the desktop (Skia) engine raster
/// cache is REFUSED for the artwork, permanently.
///
/// The full flip-flop history, pinned here because both legs were
/// device-verified and the losing leg keeps looking attractive:
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
///    `integral_layer_offset_test.dart` quantifies that one-frame gap
///    deterministically.
///
/// ⇒ Proven-on-device beats theoretically-clean. The hint is the law;
/// `IntegralLayerOffset` STAYS (they compose — the wrapper holds the
/// settled-state offset integral for every other picture under the
/// boundary the engine may still cache). The hint's cost is ~0: an idle
/// canvas schedules no frames at all, and on a neighbor's repaint the
/// replay is a few buffer blits, not a re-record. Impeller (mobile)
/// carries no such cache and ignores the hint entirely.
///
/// ⛔Retiring the hint again requires a device-verified replacement that
/// covers the LAYOUT-CHANGE frame, not just the settled state.
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
        timeline: {0: TimelineExposure.drawing(frameId, length: 4)},
      ),
    ],
  );

  testWidgets(
    'the editing stack picture opts OUT of the raster cache — '
    'willChange pinned TRUE (the #1103 law, restored over #1106)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              height: 100,
              child: CanvasLayerStackView(
                nodes: const [CanvasActiveLayerNode(opacity: 1)],
                imageCache: LayerFrameImageCache(
                  frameStore: BrushFrameStore(),
                ),
                canvasSize: const CanvasSize(width: 16, height: 16),
                viewport: CanvasViewport(zoom: 1),
                paintPaper: true,
                paperBackground: const ProjectBackground.color(0xFFFFFFFF),
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
        reason: 'device-proven law (#1103, re-proven 2026-08-17): the '
            'engine raster cache snaps a stable picture layer to integral '
            'device translation and the flip against live renders hops '
            'axis-aligned artwork edges by 1px at every engage/disengage '
            'moment. IntegralLayerOffset holds only the SETTLED frame '
            'integral — the frame of an ancestor layout change paints with '
            'stale compensation, so the hint must refuse the cache.',
      );
    },
  );

  testWidgets(
    'the playback view picture opts OUT of the raster cache — a paused '
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
        isTrue,
        reason: 'same class as the editing stack: this picture draws '
            'artwork-aligned edges into the canvas content boundary, and a '
            'PAUSED playback frame is a stable picture the engine cache '
            'would snap on engage — the 1px hop. While playing, the '
            'picture changes every frame and the hint costs nothing.',
      );
    },
  );

  testWidgets(
    'every parked track-stack picture opts OUT of the raster cache — a '
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
          isTrue,
          reason: 'the parked stack is the stillest canvas content there '
              'is — the engine cache would engage within frames and snap '
              'the artwork layer; the hint refuses it, and an idle parked '
              'canvas schedules no frames so the refusal is free.',
        );
      }
    },
  );
}
