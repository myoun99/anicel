import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/canvas/canvas_point_gizmo.dart';
import 'package:anicel/src/ui/canvas/layer_transform_box.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// 🚨The gizmos edit a row's OWN pose, and a row's own pose lives in its
/// PARENT's space — the folders above it. On the canvas that space is where
/// the folders' placement puts it, so a gizmo stands where its value shows
/// and a drag lands back through the same placement.
///
/// 🔬Found with the placement law (a-posed-folder-and-the-pen, 2026-09-25):
/// the pen, the pixel verbs and the selection tools all cross through
/// `layerPlacementAt`, and the gizmos alone drew the row's own value as if
/// the canvas were its parent — inside a folder moved right by 200 the
/// crosshair sat 200 to the left of the picture it moves.
void main() {
  const folder = LayerId('gz-folder');
  const row = LayerId('gz-row');
  const cel = FrameId('gz-cel');
  final centre = CanvasPoint(
    x: defaultCutCanvasSize.width / 2,
    y: defaultCutCanvasSize.height / 2,
  );

  Project project(TransformPose folderPose) => Project(
    id: const ProjectId('gz-project'),
    name: 'Gizmo',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('gz-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('gz-cut'),
            name: 'gz-cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: row,
                name: 'A',
                folderId: folder,
                frames: [
                  Frame(id: cel, name: 'c', duration: 1, strokes: const []),
                ],
                timeline: const {0: TimelineExposure.drawing(cel, length: 1)},
              ),
              createFolderLayer(id: folder, name: 'F').copyWith(
                transformTrack: TransformTrack(keyframes: {0: folderPose}),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// The app on [folderPose]'s project, standing on the row's Transform
  /// group — every gizmo it declares shows. The cel gets ink first, because
  /// the box frames the row's INK and a blank cel has none to frame.
  Future<EditorSessionManager> standOnTheRowsTransform(
    WidgetTester tester,
    TransformPose folderPose,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project(folderPose))),
    );
    await tester.pumpAndSettle();
    final session = sessionOf(tester);
    session.selectLayer(row);
    await pumpFrames(tester);
    final landed = session.pixelEditingCoordinator!.commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: centre.x + 30, y: centre.y + 20),
          color: 0xFF112233,
          size: 8,
          opacity: 1,
          flow: 1,
          hardness: 1,
          pressure: 1,
          sequence: 0,
        ),
      ],
      cacheInvalidationSink: session.renderCaches.cacheInvalidationHub,
    );
    expect(landed, isNotNull, reason: 'LIVENESS — the ink landed');
    session.standOnRow(LaneRowAddress(row, transformGroupHeaderLane.laneId));
    await pumpFrames(tester);
    return session;
  }

  CanvasPointGizmo gizmo(WidgetTester tester, HandleGlyph glyph) =>
      tester.widget<CanvasPointGizmo>(
        find.byWidgetPredicate(
          (widget) => widget is CanvasPointGizmo && widget.glyph == glyph,
        ),
      );

  TransformPose ownPose(EditorSessionManager session) =>
      session.layerPoseAtFrame(
        session.requireActiveCut.layers.byId(row)!,
        session.currentFrameIndex,
      );

  void expectPoint(CanvasPoint actual, CanvasPoint expected, String reason) {
    expect(actual.x, closeTo(expected.x, 0.001), reason: reason);
    expect(actual.y, closeTo(expected.y, 0.001), reason: reason);
  }

  group('in a folder moved right by 200', () {
    final movedRight = TransformPose(
      center: CanvasPoint(x: centre.x + 200, y: centre.y),
    );

    testWidgets('the crosshair stands on the picture it moves, and a drag '
        'moves the row by the drag', (tester) async {
      final session = await standOnTheRowsTransform(tester, movedRight);
      final crosshair = gizmo(tester, HandleGlyph.crosshair);
      expectPoint(
        crosshair.point,
        CanvasPoint(x: centre.x + 200, y: centre.y),
        'the row\'s pivot shows 200 to the right, where the folder puts it',
      );

      crosshair.onCommitted(CanvasPoint(x: centre.x + 230, y: centre.y + 10));
      await tester.pump();
      expectPoint(
        ownPose(session).center,
        CanvasPoint(x: centre.x + 30, y: centre.y + 10),
        'the row moved by the drag, in its folder',
      );
    });

    testWidgets('the anchor stands where the folder shows it, and lands back '
        'through it', (tester) async {
      final session = await standOnTheRowsTransform(tester, movedRight);
      final anchor = gizmo(tester, HandleGlyph.anchor);
      expectPoint(
        anchor.point,
        CanvasPoint(x: centre.x + 200, y: centre.y),
        'the anchor, carried by the folder like everything in it',
      );

      anchor.onCommitted(CanvasPoint(x: centre.x + 210, y: centre.y + 5));
      await tester.pump();
      expectPoint(
        session.layerAnchorPointAtFrame(
          session.requireActiveCut.layers.byId(row)!,
          session.currentFrameIndex,
        ),
        CanvasPoint(x: centre.x + 10, y: centre.y + 5),
        'dropped 10 right of where it showed, in the folder',
      );
    });
  });

  group('in a folder turned 30°', () {
    final turned = TransformPose(center: centre, rotationDegrees: 30);

    testWidgets('the box turns the picture as the folder shows it, and its '
        'turn is the row\'s own', (tester) async {
      final session = await standOnTheRowsTransform(tester, turned);
      final box = tester.widget<LayerTransformBox>(
        find.byType(LayerTransformBox),
      );
      expect(box.pose.rotationDegrees, closeTo(30, 0.001));

      box.onRotationCommitted(50);
      await tester.pump();
      expect(
        ownPose(session).rotationDegrees,
        closeTo(20, 0.001),
        reason: 'shown at 50° under a 30° folder is 20° of its own',
      );
    });
  });

  group('in a folder scaled 2x', () {
    final twice = TransformPose(center: centre, zoom: 2);

    testWidgets('a crosshair drag lands under the pointer — half the drag, '
        'in the folder', (tester) async {
      final session = await standOnTheRowsTransform(tester, twice);
      final crosshair = gizmo(tester, HandleGlyph.crosshair);
      expectPoint(crosshair.point, centre, 'the centre stays the centre');

      crosshair.onCommitted(CanvasPoint(x: centre.x + 40, y: centre.y + 20));
      await tester.pump();
      expectPoint(
        ownPose(session).center,
        CanvasPoint(x: centre.x + 20, y: centre.y + 10),
        'a 2x folder doubles what the row moves, so the row moves half',
      );
    });

    testWidgets('the box frames the picture as the folder shows it, and its '
        'scale is the row\'s own', (tester) async {
      final session = await standOnTheRowsTransform(tester, twice);
      final box = tester.widget<LayerTransformBox>(
        find.byType(LayerTransformBox),
      );
      expect(
        box.pose.zoom,
        closeTo(2, 0.001),
        reason: 'the box draws the row at the zoom the canvas shows it',
      );

      box.onScaleCommitted(3);
      await tester.pump();
      expect(
        ownPose(session).zoom,
        closeTo(1.5, 0.001),
        reason: 'shown at 3x under a 2x folder is 1.5x of its own',
      );
    });
  });
}
