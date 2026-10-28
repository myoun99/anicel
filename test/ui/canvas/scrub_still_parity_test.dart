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
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/camera_shot.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/composite_tree.dart';

import '../../helpers/settle_async.dart';

/// 🚨★★★ SCRUB ↔ STILL PARITY (device report B2, 2026-08-17).
///
/// 「재생도 스크럽도 편집 캔버스」 — the device saw a ruler scrub and the
/// canvas at rest disagree by 1px on axis-aligned edges ("반올림") at
/// fractional device phase (DPR 1.25/1.5): the scrub served a composite
/// through its own painter, which hardcoded `low` where the editing buffer
/// follows the T21 display law (`filterQualityForDisplayScale`).
///
/// ↩️This file pinned the two routes byte for byte until 2026-10-10, when
/// the last screen that showed a composite drew its cuts on the editing
/// stack too (playback-plays-the-screen-material): one route, so the
/// same pixels by construction. What stands is the law the editing route
/// keeps — the DEVICE scale decides its sampling — and the wiring: every
/// mount around a cut's picture hands its painter the view's real DPR
/// (#1101's pan-phase snap — a painter snapping at 1.0 while the picture
/// snaps at 1.25 is exactly a whole-picture 1px disagreement).
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const background = ProjectBackground.defaultBackground;
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
        timeline: {0: const TimelineExposure.drawing(frameId, length: 4)},
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
      historyPolicy: const BrushHistoryPolicy(),
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
  /// test actually run" oracle.
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

  /// Pixels that are neither the ink's black nor the paper's white: what
  /// bilinear leaves along a hard edge at a fractional device phase, and
  /// what nearest never produces.
  int blendedPixels(Uint8List rgba) {
    var blended = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      if (rgba[i + 3] == 255 && rgba[i] > 16 && rgba[i] < 240) {
        blended += 1;
      }
    }
    return blended;
  }

  /// The frames' pictures a screen shows, read from [store]'s cels, in a
  /// store of their own.
  StackRun picturesOf(BrushFrameStore store) {
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    final pictures = FramePictureStore<FramePictureKey>();
    addTearDown(pictures.dispose);
    final landings = ValueNotifier<int>(0);
    addTearDown(landings.dispose);
    return (
      landings: landings,
      pictures: FramePictures(
        store: pictures,
        layerImages: images,
        stackOf: (_) => const [],
        pageOf: (picture) => (
          canvasSize: picture.cut.canvasSize,
          pasteboardReach: PasteboardReach.whole,
          paintPaper: picture.paintPaper,
          paperBackground: background,
        ),
      ),
    );
  }

  /// The EDITING route: the frame's one picture as the canvas shows it,
  /// pumped so the MediaQuery DPR reaches its painter exactly as the panel
  /// wires it.
  ///
  /// 🚨The picture must LAND before the painter is looked at: it is made
  /// across real async (a raster), which never lands under the fake clock —
  /// a paper-only render would pass any law about how the ink is sampled,
  /// which is why each use asks [hasInk].
  Future<CustomPainter> editingPainter(
    WidgetTester tester, {
    required BrushFrameStore store,
    required CanvasViewport viewport,
    required Size logicalSize,
  }) async {
    final run = picturesOf(store);
    final nodes = [
      CompositeLeaf<CanvasStackRow>(
        CanvasLayerImageRequest(
          frameKey: frameKey(cut(), layerId, frameId),
          opacity: 1,
        ),
      ),
    ];
    final picture = (cut: cut(), frameIndex: 0, paintPaper: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: logicalSize.width,
              height: logicalSize.height,
              child: FramePictureView(
                run: run,
                picture: picture,
                nodes: nodes,
                viewport: viewport,
                laysWhatItMisses: true,
              ),
            ),
          ),
        ),
      ),
    );
    final made = run.pictures.keyOfStack(nodes, picture);
    expect(
      await settleAsync(
        tester,
        () => run.pictures.store.bytesOf(made) != null,
      ),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    final painted = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(FramePictureView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .toList();
    expect(painted, isNotEmpty);
    return painted.first.painter!;
  }

  testWidgets(
    'the scale is the DEVICE scale: 140% on a ratio-2 tablet samples '
    'nearest (유저 09-16 표시배율 100%부터는 필터가 걸리면안되)',
    (tester) async {
      // Render zoom 0.7 on a ratio-2 screen is 140% on screen. The
      // zoom-alone law read 0.7, called it a reduction and filtered: the
      // ink's edges — canvas 2..6, device 2.8..8.4, fractional — came out
      // bilinear-blended on a MAGNIFIED view. The window sits inside the
      // canvas, so only the ink's black and the paper's white can appear;
      // a blended pixel is the filter.
      const dpr = 2.0;
      const logicalSize = Size(5, 5);
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewport = CanvasViewport(zoom: 0.7);

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
      expect(hasInk(editingBytes), isTrue);
      expect(
        blendedPixels(editingBytes),
        0,
        reason: 'the editing route filtered a magnified view: the law read '
            'the render zoom (0.7) instead of the device scale (1.4).',
      );
    },
  );

  group('the playback mounts wire the view\'s real DPR', () {
    // A painter that snaps its pan at DPR 1.0 while the picture it frames
    // snaps at 1.25/1.5 is a whole-picture 1px disagreement at fractional
    // pans — the #1101 report's exact shape. MediaQuery is the source every
    // one of them must read.
    testWidgets('the parked track stack (what a ruler scrub serves)', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.resetDevicePixelRatio);

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
              stackOf: (_, _) => const [],
              pictures: picturesOf(BrushFrameStore()),
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
          // The cut's picture is painted at the ratio it reads from the
          // view ([FramePictureView]); these are its stage and what lies
          // over it.
          if (paint.painter case final PlaybackFramePainter painter) painter,
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

    /// ↩️This was the composite view's — the picture a run seen through the
    /// camera played on, until it moved onto the canvas (10-10). The frame,
    /// the letterbox and the apron around the canvas's picture are what
    /// that view's painter still draws there.
    testWidgets('the camera\'s shot around a run on the canvas', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.25;
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CameraShot(
              view: CanvasViewport(),
              shot: (
                pose: CameraPose(center: CanvasPoint(x: 4, y: 4)),
                frameSize: canvasSize,
                frameView: CanvasViewport(),
              ),
              canvasSize: canvasSize,
              background: ProjectBackground.defaultBackground,
              pasteboardColor: const Color(0xFF123456),
              pasteboardNone: false,
              pasteboardReach: PasteboardReach.whole,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      final ground = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(CameraShot),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.painter is PlaybackFramePainter,
          ),
        ),
      );
      expect(
        (ground.painter! as PlaybackFramePainter).devicePixelRatio,
        1.25,
      );
    });
  });
}
