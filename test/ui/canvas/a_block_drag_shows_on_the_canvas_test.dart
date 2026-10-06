import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/tree_nodes.dart' show preorderNodes;
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/camera/camera_frame_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show timelineFrameCellWidth;

import '../../helpers/repaint_strays.dart';
import '../timeline/timeline_cell_probe.dart';

/// canvas-follows-block-moves — 유저 2026-09-28: 「따라가게 — 끄는 동안
/// 캔버스도 바뀐다」.
///
/// A REAL pointer drags blocks on the timeline of the real app, and the
/// canvas the user is looking at — the mounted stack, not the session's
/// answer — shows what the drag leaves at the playhead, before the release.
///
/// The press itself stands on the grabbed cell: a mouse picks on the DOWN
/// (`AppInput.timelineCellPressSeeks`), so the playhead is on the grabbed
/// block and the grabbed row is the one being drawn on. Carrying the
/// selection moves that block OFF the playhead and brings the block behind
/// it ON — which is the row being drawn on handing its cel to an image.
void main() {
  const a = LayerId('bd-a');
  const b = LayerId('bd-b');
  const a3 = FrameId('bd-a3');
  const a5 = FrameId('bd-a5');
  const b3 = FrameId('bd-b3');
  const b5 = FrameId('bd-b5');
  const cutId = CutId('bd-cut');

  /// A row with one-frame blocks at 3 and 5.
  Layer drawingRow(
    LayerId id,
    FrameId at3,
    FrameId at5, {
    double opacity = 1,
  }) => Layer(
    id: id,
    name: id.value,
    opacity: opacity,
    frames: [
      Frame(id: at3, name: '1', duration: 1, strokes: const []),
      Frame(id: at5, name: '2', duration: 1, strokes: const []),
    ],
    timeline: {
      3: TimelineExposure.drawing(at3, length: 1),
      5: TimelineExposure.drawing(at5, length: 1),
    },
  );

  Project project() => Project(
    id: const ProjectId('bd-project'),
    name: 'Block drag',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('bd-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: cutId,
            name: 'bd-cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            layers: [
              // A half-opaque row: the panel wraps its drawing surface in
              // an Opacity, which is what a drag must not unwrap.
              drawingRow(a, a3, a5, opacity: 0.5),
              drawingRow(b, b3, b5),
              createCameraLayer(cutId: cutId),
            ],
          ),
        ],
      ),
    ],
  );

  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  /// The app on the project, standing on row A at frame 0, the timeline
  /// tall enough to reach every row.
  Future<EditorSessionManager> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    final session = sessionOf(tester);
    session.selectLayer(a);
    session.selectFrameIndex(0);
    await tester.pumpAndSettle();
    return session;
  }

  /// The stack the canvas has MOUNTED — what it paints.
  CanvasLayerStackView mountedStack(WidgetTester tester) =>
      tester.widget<CanvasLayerStackView>(find.byType(CanvasLayerStackView));

  List<CanvasStackRow> mountedRows(WidgetTester tester) => [
    for (final node in preorderNodes(mountedStack(tester).nodes))
      if (node case CompositeLeaf(:final payload)) payload,
  ];

  List<FrameId> imagesOn(WidgetTester tester, LayerId layerId) => [
    for (final request in mountedStack(tester).layers)
      if (request.frameKey.layerId == layerId) request.frameKey.frameId,
  ];

  CanvasActiveLayerRow? liveRow(WidgetTester tester) =>
      mountedRows(tester).whereType<CanvasActiveLayerRow>().firstOrNull;

  Offset cell(WidgetTester tester, LayerId layerId, int frame) =>
      timelineCellCenter(tester, layerId.value, frame);

  /// Sweeps a selection from [from] to [to] with a real pointer, then
  /// presses on [grab] inside it — the press stands the playhead there —
  /// and returns the pointer still down.
  Future<TestGesture> selectAndGrab(
    WidgetTester tester, {
    required (LayerId, int) from,
    required (LayerId, int) to,
    required (LayerId, int) grab,
  }) async {
    final start = cell(tester, from.$1, from.$2);
    await tester.dragFrom(
      start,
      cell(tester, to.$1, to.$2) - start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      cell(tester, grab.$1, grab.$2),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    return gesture;
  }

  Future<void> carry(TestGesture gesture, WidgetTester tester, int frames) async {
    for (var step = 0; step < frames; step += 1) {
      await gesture.moveBy(const Offset(timelineFrameCellWidth, 0));
      await tester.pump();
    }
  }

  testWidgets('the block behind the grabbed one arrives under the playhead: '
      'the row being drawn on shows it as an image before the release — '
      'without remounting the surface — and the brush takes it on the '
      'release', (tester) async {
    final session = await open(tester);
    State<StatefulWidget> surface() =>
        tester.state(find.byType(InteractiveBrushEditCanvasView));
    Finder wrap() => find.ancestor(
      of: find.byType(InteractiveBrushEditCanvasView),
      matching: find.byType(Opacity),
    );
    final gesture = await selectAndGrab(
      tester,
      from: (a, 3),
      to: (a, 5),
      grab: (a, 5),
    );
    try {
      expect(session.currentFrameIndex, 5, reason: 'the press stands there');
      expect(liveRow(tester)?.frameKey?.frameId, a5, reason: 'the premise');
      expect(wrap(), findsOneWidget, reason: 'the premise: a half-opaque row');
      final mounted = surface();

      await carry(gesture, tester, 2);

      expect(session.dragPreview.value, isA<BlockMoveDragPreview>());
      expect(
        liveRow(tester),
        isNull,
        reason: 'the live surface holds a5 — the drag shows a3 here',
      );
      expect(imagesOn(tester, a), [a3], reason: 'a3, as an image');
      expect(
        identical(surface(), mounted),
        isTrue,
        reason: 'a drag is not a remount of the drawing surface',
      );
      expect(wrap(), findsOneWidget, reason: 'the row\'s opacity stays wrapped');
      expect(
        session.requireActiveCut.layers.byId(a)!.timeline[5]!.frameId,
        a5,
        reason: 'DISPLAY only — nothing written before the release',
      );
    } finally {
      await gesture.up();
      await tester.pumpAndSettle();
    }

    expect(session.dragPreview.value, isNull);
    expect(
      liveRow(tester)?.frameKey?.frameId,
      a3,
      reason: 'the release hands a3 to the brush',
    );
    expect(imagesOn(tester, a), isEmpty);
  });

  testWidgets('several rows carried at once: the other row\'s block arrives '
      'under the playhead on the canvas before the release', (tester) async {
    final session = await open(tester);
    final gesture = await selectAndGrab(
      tester,
      from: (a, 3),
      to: (b, 5),
      grab: (a, 5),
    );
    try {
      expect(imagesOn(tester, b), [b5], reason: 'the premise: B shows b5');

      await carry(gesture, tester, 2);

      expect(
        imagesOn(tester, b),
        [b3],
        reason: 'B\'s block behind rode along — the canvas shows it',
      );
      expect(imagesOn(tester, a), [a3]);
    } finally {
      await gesture.up();
      await tester.pumpAndSettle();
    }

    expect(session.dragPreview.value, isNull);
    expect(imagesOn(tester, b), [b3], reason: 'the release keeps it there');
    expect(liveRow(tester)?.frameKey?.frameId, a3);
  });

  // canvas-wakes-for-what-it-shows: the whole canvas area was rebuilt for a
  // drag step, under the panel content's LayoutBuilder, so each step relaid
  // out and repainted all of it (09-29: layout the largest share of a step).
  testWidgets('a carried block repaints the canvas\'s tick layers and nothing '
      'else of it — a step does not rebuild the canvas area', (tester) async {
    await open(tester);
    final content = find.ancestor(
      of: find.byKey(const ValueKey<String>('canvas-editor-panel-content')),
      matching: find.byType(RepaintBoundary),
    );
    List<String> strays() => [
      for (final stray in repaintStrays(
        tester.renderObject(content.first),
        allowed: {
          for (final layer in find
              .descendant(of: content.first, matching: find.byType(TickLayer))
              .evaluate())
            layer.renderObject!,
        },
      ))
        nameOfBoundary(stray),
    ];
    final gesture = await selectAndGrab(
      tester,
      from: (a, 3),
      to: (b, 5),
      grab: (a, 5),
    );
    try {
      final steps = <String>[];
      for (var step = 1; step <= 2; step += 1) {
        await gesture.moveBy(const Offset(timelineFrameCellWidth, 0));
        // The step's frame, run to its layout and stopped before the paint.
        await tester.pump(const Duration(milliseconds: 16), EnginePhase.layout);
        final now = strays();
        if (now.isNotEmpty) {
          steps.add('step $step:\n${now.join('\n')}');
        }
        await tester.pump();
      }
      expect(
        imagesOn(tester, b),
        [b3],
        reason: '⛔premise: the steps moved the picture',
      );
      expect(steps, isEmpty, reason: steps.join('\n\n'));
    } finally {
      await gesture.up();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('the canvas wakes for a drag it shows and sleeps through one it '
      'does not', (tester) async {
    final session = await open(tester);
    final before = mountedStack(tester);

    session.dragPreview.value = const MovieEndDragPreview(trailingFrames: 7);
    await tester.pump();
    expect(
      identical(mountedStack(tester), before),
      isTrue,
      reason: 'a movie\'s end moves nothing the canvas draws',
    );

    final row = session.requireActiveCut.layers.byId(b)!;
    session.dragPreview.value = BlockMoveDragPreview(
      previewLayers: {
        b: row.copyWith(
          timeline: {0: const TimelineExposure.drawing(b3, length: 1)},
        ),
      },
    );
    await tester.pump();
    expect(identical(mountedStack(tester), before), isFalse);
    expect(imagesOn(tester, b), [b3]);

    session.dragPreview.value = null;
    await tester.pumpAndSettle();
  });

  testWidgets('camera keys carried with a block move the camera frame on '
      'the canvas before the release', (tester) async {
    final session = await open(tester);
    final camera = session.requireActiveCut.layers.cameraLayer!;
    session.selectLayer(camera.id);
    await tester.pumpAndSettle();
    CameraPose shown() =>
        tester.widget<CameraFrameOverlay>(find.byType(CameraFrameOverlay)).pose;
    final before = shown();
    final shifted = TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>.empty().withKey(
        0,
        CanvasPoint(x: before.center.x + 40, y: before.center.y),
      ),
    );

    // The block ride's two halves, as the drag hands them over.
    session.camera.showCameraKeysDragPreview(shifted);
    session.dragPreview.value = BlockMoveDragPreview(
      previewLayers: const {},
      cameraCutId: cutId,
      cameraTrack: shifted,
      cameraMarkerLayer: camera.copyWith(),
    );
    await tester.pump();

    expect(shown().center.x, before.center.x + 40);
    session.camera.showCameraKeysDragPreview(null);
    session.dragPreview.value = null;
    await tester.pumpAndSettle();
    expect(shown().center.x, before.center.x);
  });
}
