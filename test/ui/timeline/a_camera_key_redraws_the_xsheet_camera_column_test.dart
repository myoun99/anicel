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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

/// ㉘ (user, 2026-08-12): 「카메라 행에 프레임을 추가하면 즉시 갱신이 안 된다
/// — 다른 레이어로 이동해야 보인다」 — ON THE X-SHEET TOO.
///
/// The camera row's cells mirror the cut's camera, not the camera LAYER: a
/// key lands and the layer, the resolver and the cels are all what they
/// were, so only the camera track's identity can say the row must be drawn
/// again. The fix reached the timeline's rows (`camera_row_coverage_refresh_
/// test` pins them) and not the x-sheet's columns, which built the same row
/// without it (F-244 found it — the x-sheet was handed no camera track at
/// all). Both build the row through one function now.
void main() {
  const camera = LayerId('camera');

  Project project() => Project(
    id: const ProjectId('camera-key'),
    name: 'Camera key',
    createdAt: DateTime.utc(2026, 9, 30),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('cut-0'),
            name: 'cut-0',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            camera: CutCamera.empty(),
            layers: [
              Layer(
                id: const LayerId('drawing'),
                name: 'Drawing',
                frames: const [],
              ),
              Layer(
                id: camera,
                name: 'Camera',
                kind: LayerKind.camera,
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  TimelineRowCellsPainter cameraColumn(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<TimelineRowCellsPainter>()
      .singleWhere((painter) => painter.layer.id == camera);

  testWidgets('a camera key redraws the camera column of the x-sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(XSheetTimelineGrid),
      findsOneWidget,
      reason: 'premise: the x-sheet is up',
    );
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final before = cameraColumn(tester);

    session.selectFrameIndex(6);
    session.camera.setCameraKeyframeAtCurrentFrame(
      CameraPose(center: CanvasPoint(x: 10, y: 10), zoom: 1.5),
    );
    await tester.pumpAndSettle();

    final after = cameraColumn(tester);
    expect(
      identical(after.layer, before.layer),
      isTrue,
      reason: 'premise: the key went to the cut, not to the layer',
    );
    expect(
      after.shouldRepaint(before),
      isTrue,
      reason: 'the camera track is the only thing that says the column has '
          'to be drawn again',
    );
  });
}
