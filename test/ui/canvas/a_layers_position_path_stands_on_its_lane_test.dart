import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_path_settings.dart';
import 'package:anicel/src/models/camera_pose.dart';
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
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/camera_projection_matrix.dart'
    show shotPlacement;
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/camera/camera_path_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_offset.dart';
import 'package:anicel/src/ui/canvas/row_transform_box.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// I-89-Q9 — a layer's position walks a path on the canvas by the camera's
/// code (유저 2026-10-12: 「같은 코드로 레이어 위치 레인에도」): drawn
/// standing on its position lane, where the box that moves its keys is,
/// laid where the layer's position shows — through its folders, or an SE
/// row's shot — and its curved keys' handles worked there, one undo each.
void main() {
  void reset() =>
      CameraPathSettings.settings.value = const CameraPathSettings();
  setUp(reset);
  tearDown(reset);

  const folder = LayerId('lp-folder');
  const row = LayerId('lp-row');
  const cel = FrameId('lp-cel');
  final centre = CanvasPoint(
    x: defaultCutCanvasSize.width / 2,
    y: defaultCutCanvasSize.height / 2,
  );

  /// The row's position: 200 right at frame 5, then 150 down at 10 —
  /// smooth at 5 alone.
  final a = centre;
  final b = CanvasPoint(x: centre.x + 200, y: centre.y);
  final c = CanvasPoint(x: centre.x + 200, y: centre.y + 150);

  /// The row in a folder standing at [folderPose].
  EditorSessionManager sessionIn(TransformPose folderPose) {
    final project = Project(
      id: const ProjectId('lp-project'),
      name: 'Path',
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('lp-track'),
          name: 'Video Track',
          cuts: [
            Cut(
              id: const CutId('lp-cut'),
              name: 'lp-cut',
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
                  timeline: const {
                    0: TimelineExposure.drawing(cel, length: 12),
                  },
                  transformTrack: TransformTrack.empty().copyWith(
                    position: PropertyTrack<CanvasPoint>()
                        .withKey(0, a)
                        .withKey(5, b, path: KeyPath.auto)
                        .withKey(10, c),
                  ),
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
    final s = EditorSessionManager(initialProject: project);
    s.selectLayer(row);
    s.selectFrameIndex(0);
    s.standOnRow(const LaneRowAddress(row, 'position'));
    return s;
  }

  Future<void> pumpArea(WidgetTester tester, EditorSessionManager s) async {
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(true);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(cameraView.dispose);
    addTearDown(cameraDim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: s,
            brushToolState: brushTool,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The warmer's debounced timers cannot be cancelled by a dispose.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Finder path() => find.byType(CameraPathOverlay);

  CameraPathOverlay overlay(WidgetTester tester) =>
      tester.widget<CameraPathOverlay>(path());

  RowTransformBox box(WidgetTester tester) =>
      tester.widget<RowTransformBox>(find.byType(RowTransformBox));

  /// Where the keys' crosses stand on the screen: the middle of each arm a
  /// key's cross reaches with, two a key.
  List<Offset> keyCrosses(WidgetTester tester) => [
    for (final mark in overlay(tester).marks)
      if (mark is SheetStroke &&
          !mark.closed &&
          mark.points.length == 2 &&
          ((mark.points[1] - mark.points[0]).distance -
                      2 * CameraPathOverlay.sizes.crossArm)
                  .abs() <
              1e-6)
        (mark.points[0] + mark.points[1]) / 2,
  ];

  void expectNear(CanvasPoint actual, CanvasPoint expected, String what) {
    expect(actual.x, closeTo(expected.x, 1e-6), reason: '$what x');
    expect(actual.y, closeTo(expected.y, 1e-6), reason: '$what y');
  }

  KeyPath pathAt5(EditorSessionManager s) => s.requireActiveCut.layers
      .byId(row)!
      .transformTrack
      .position
      .keyAt(5)!
      .path;

  testWidgets('standing on a layer\'s position lane the canvas draws the '
      'path its position walks, a point at each key — standing anywhere '
      'else, and with the path off, none', (tester) async {
    final s = sessionIn(TransformPose(center: centre));
    addTearDown(s.dispose);
    await pumpArea(tester, s);

    expect(path(), findsOneWidget);
    expect(overlay(tester).standing, isTrue, reason: 'drawn in time');
    expect([for (final key in overlay(tester).path.keys) key.corners], [
      [Offset(a.x, a.y)],
      [Offset(b.x, b.y)],
      [Offset(c.x, c.y)],
    ]);
    expect(box(tester).tangents, hasLength(1), reason: 'the key at 5\'s');
    expect(
      overlay(tester).centreTrail,
      isEmpty,
      reason: 'a point\'s one trail is its middle\'s — the camera\'s line '
          'is not drawn twice',
    );
    // 🗣️F-368 (유저 2026-10-16): 「공간이든 공간+시간이든 공간이라는
    // 정보로서」 — its handles in space as in space and time.
    CameraPathSettings.settings.value = const CameraPathSettings(
      show: CameraPathShow.space,
    );
    await tester.pump();
    expect(box(tester).tangents, hasLength(1), reason: 'in space too');
    reset();
    await tester.pump();

    for (final elsewhere in [
      const LaneRowAddress(row, 'scale'),
      const LayerRowAddress(row),
      const LayerRowAddress(folder),
    ]) {
      s.standOnRow(elsewhere);
      await tester.pump();
      expect(path(), findsNothing, reason: '$elsewhere');
    }
    s.standOnRow(const LaneRowAddress(row, 'scale'));
    await tester.pump();
    expect(
      box(tester).tangents,
      isEmpty,
      reason: 'the scale\'s box wears no handle of the path',
    );

    s.standOnRow(const LaneRowAddress(row, 'position'));
    await tester.pump();
    expect(path(), findsOneWidget, reason: '⛔전제');
    CameraPathSettings.settings.value = const CameraPathSettings(
      show: CameraPathShow.off,
    );
    await tester.pump();
    expect(path(), findsNothing);

    await drain(tester);
  });

  testWidgets('in a folder it stands where the folder shows the layer\'s '
      'position, and a curved key\'s handle carried there bends the key '
      'through the folder — one undo', (tester) async {
    // Twice as large about the canvas's centre.
    final s = sessionIn(TransformPose.uniform(center: centre, zoom: 2));
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    CanvasPoint shown(double dx, double dy) =>
        CanvasPoint(x: centre.x + 2 * dx, y: centre.y + 2 * dy);

    final view = overlay(tester).viewport;
    final crosses = keyCrosses(tester);
    expect(crosses, hasLength(6), reason: '⛔전제: two arms a key');
    for (final (index, (dx, dy)) in [(0.0, 0.0), (200.0, 0.0), (200.0, 150.0)]
        .indexed) {
      final at = view.canvasToViewportOffset(shown(dx, dy));
      for (final arm in [crosses[2 * index], crosses[2 * index + 1]]) {
        expect(arm.dx, closeTo(at.dx, 1e-6), reason: 'key $index');
        expect(arm.dy, closeTo(at.dy, 1e-6), reason: 'key $index');
      }
    }

    // Smooth at 5 through its neighbours, (200, 150) apart: its handle a
    // third of the way to 10 ahead, of the way to 0 behind.
    final handle = box(tester).tangents.single;
    expectNear(handle.at, shown(200 + 40, 30), 'ahead');
    expectNear(handle.behind, shown(200 - 160 / 3, -40), 'behind');

    final trailBefore = overlay(tester).path.cornerTrailsBetween(0, 10);
    handle.landing.committed(shown(250, 50));
    await tester.pump();
    expect(
      overlay(tester).path.cornerTrailsBetween(0, 10),
      isNot(trailBefore),
      reason: 'the path follows the bend',
    );
    final bent = pathAt5(s);
    expect(bent, isA<HandledPath>());
    expectNear(
      (bent as HandledPath).tangent,
      CanvasPoint(x: 50, y: 50),
      'the tangent, in the folder',
    );

    s.undo();
    await tester.pump();
    expect(pathAt5(s), KeyPath.auto, reason: 'one undo');

    await drain(tester);
  });

  testWidgets('an SE row\'s stands where its shot lies on the canvas, its '
      'keys on the cut\'s frames though the row keys the track\'s', (
    tester,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.cutVerbs.createCut();
    expect(s.activeCutGlobalStartFrame, greaterThan(0), reason: '⛔전제');
    final se = s.activeTrack.seLayers.first.id;
    s.selectLayer(se);
    for (final (frame, (dx, dy)) in [
      (0, (0, 0)),
      (5, (200, 0)),
      (10, (200, 150)),
    ]) {
      s.laneVerbs.setLaneValueAt(
        se,
        'position',
        frame,
        '${100 + dx}, ${100 + dy}',
        frameIsGlobal: false,
        scaleLinked: false,
        description: 'Set Position',
      );
    }
    final cut = s.requireActiveCut;
    final panned = CameraPose(
      center: CanvasPoint(
        x: cut.canvasSize.width / 2 + 300,
        y: cut.canvasSize.height / 2,
      ),
    );
    s.cutCommandCoordinator.setCutCameraKeyframe(
      cutId: cut.id,
      frameIndex: 0,
      pose: panned,
    );
    s.selectFrameIndex(0);
    s.standOnRow(LaneRowAddress(se, 'position'));
    await pumpArea(tester, s);

    expect(path(), findsOneWidget);
    expect([for (final key in overlay(tester).path.keys) key.frameIndex], [
      0,
      5,
      10,
    ]);
    final shot = shotPlacement(panned, s.camera.cameraFrameSize);
    final view = overlay(tester).viewport;
    final at = view.canvasToViewportOffset(
      shot.apply(CanvasPoint(x: 300, y: 100)),
    );
    final crosses = keyCrosses(tester);
    expect(crosses[2].dx, closeTo(at.dx, 1e-6), reason: 'the key at 5');
    expect(crosses[2].dy, closeTo(at.dy, 1e-6));

    // Kept to six frames either side of the playhead — the cut's frames,
    // where the keys at 0 and 5 stand.
    CameraPathSettings.settings.value = const CameraPathSettings(
      range: CameraPathRange.aroundPlayhead,
      around: 6,
    );
    await tester.pump();
    expect(box(tester).tangents, hasLength(2));
    // And back from it: four either side of 10 keep the key at 10 alone,
    // the cut's 0 and 5 before its 6.
    s.selectFrameIndex(10);
    CameraPathSettings.settings.value = const CameraPathSettings(
      range: CameraPathRange.aroundPlayhead,
      around: 4,
    );
    await tester.pump();
    expect(box(tester).tangents, hasLength(1));
    s.selectFrameIndex(0);
    reset();
    await tester.pump();

    // Every key smooth as it was typed (I-89-Q10 B): the end keys' handles
    // stand on them, the one at 5 a third of the way to 10 ahead.
    final handles = box(tester).tangents;
    expect(handles, hasLength(3), reason: '⛔전제');
    expectNear(
      handles[1].at,
      shot.apply(CanvasPoint(x: 300 + 40, y: 100 + 30)),
      'in the shot',
    );
    handles[1].landing.committed(
      shot.apply(CanvasPoint(x: 300 + 50, y: 100 + 50)),
    );
    await tester.pump();
    final written = s.activeTrack.seLayers.first.transformTrack.position
        .keyAt(s.activeCutGlobalStartFrame + 5)!
        .path;
    expect(written, isA<HandledPath>(), reason: 'on the track\'s frame');
    expectNear(
      (written as HandledPath).tangent,
      CanvasPoint(x: 50, y: 50),
      'back through the shot',
    );

    await drain(tester);
  });
}
