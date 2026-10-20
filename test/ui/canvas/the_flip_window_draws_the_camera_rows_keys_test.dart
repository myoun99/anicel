import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_camera_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/home_page_probes.dart';

/// **The flip window's camera row draws the keys its panel draws there.**
///
/// A camera layer holds no drawings: its keys are its cut's camera
/// track's, and both rails draw their union on the camera row (B4). The
/// window, which says where you are in the words of the panel you work in
/// (유저 2026-09-24), drew that row an empty band.
void main() {
  const trackId = TrackId('t');

  CameraPose at(double x) => CameraPose(center: CanvasPoint(x: x, y: 0));

  Layer camera(String id) => Layer(
    id: LayerId(id),
    name: 'Camera',
    kind: LayerKind.camera,
    frames: const [],
  );

  Cut cut(String id, int duration, Set<int> keys, {bool withCamera = true}) =>
      Cut(
        id: CutId(id),
        name: id,
        duration: duration,
        canvasSize: const CanvasSize(width: 1280, height: 720),
        camera: CutCamera(
          keyframes: {for (final key in keys) key: at(key * 10.0)},
        ),
        layers: [
          Layer(id: LayerId('$id-drawing'), name: 'Drawing', frames: const []),
          if (withCamera) camera('$id-camera'),
        ],
      );

  Project project() => Project(
    id: const ProjectId('flip-camera-keys'),
    name: 'Flip camera keys',
    createdAt: DateTime.utc(2026, 10, 21),
    tracks: [
      Track(
        id: trackId,
        name: 'Video',
        cuts: [
          cut('cut-0', 24, {2, 8, 14}),
          // Its key on 12 lies past its own ten frames.
          cut('cut-1', 10, {1, 5, 12}),
          // No camera row of its own to draw its key on.
          cut('cut-2', 6, {3}, withCamera: false),
        ],
      ),
    ],
  );

  Future<(EditorSessionManager, FlipHudController)> pump(
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    final workspace = tester.widget<EditorWorkspace>(
      find.byType(EditorWorkspace),
    );
    return (workspace.session, workspace.flipHud!);
  }

  /// The row the window stands on, by its keys: where each stands, and
  /// whether it wears a mark.
  (String, bool, List<(int, bool)>) keysOf(FlipHudController hud) {
    final row = hud.debugSnapshotFor(FlipHudAxis.frame)!.currentRow!;
    return (
      row.name,
      row.isGroupHeader,
      [for (final run in row.runs) (run.startIndex, run.keyMark != null)],
    );
  }

  testWidgets('in the timeline, the camera row draws its cut\'s keys, at a '
      'union\'s size', (tester) async {
    final (session, hud) = await pump(tester);
    expect(session.activeCutOrNull?.id, const CutId('cut-0'), reason: '전제');

    session.standOnRow(const LayerRowAddress(LayerId('cut-0-camera')));

    final (name, header, keys) = keysOf(hud);
    expect((name, header), ('Camera', true));
    expect(keys, [(2, true), (8, true), (14, true)]);
  });

  testWidgets('in the storyboard, the camera row draws each cut\'s keys '
      'where the rail lays them on the track: only where the cut reaches, '
      'and only a cut with a camera row', (tester) async {
    final (session, hud) = await pump(tester);
    await showStoryboardPanel(tester);

    session.standOnRow(
      LayerRowAddress(trackCameraRowId(trackId)),
      panel: WorkingPanel.storyboard,
    );

    expect(
      keysOf(hud).$3,
      [(2, true), (8, true), (14, true), (25, true), (29, true)],
      reason: 'cut-1 opens on 24; its key on 12 and cut-2\'s are not drawn',
    );
    expect(keysOf(hud).$2, isTrue);
  });
}
