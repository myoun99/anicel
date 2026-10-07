import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

import '../../helpers/app_faces.dart';

/// 🚨A ROW TURNED OFF THE SHEET LEAVES IT AT ONCE (F-269).
///
/// 유저 2026-10-03: 「타임시트 on off버튼이 카메라레이어에서 적용하면
/// 타임시트용지에 바로 반영안됨. 다른탭갓다가 돌아오면 반영되있음. 그리고
/// 애니메이션레이어쪽도 문제있는데 텍스트 두번칠해지는느낌? off해서 껐는데
/// 글자가 남아있고, 글자가 연하게 됬을뿐임. 다른탭 갓다 돌아오면 정상적으로
/// 사라져있음」.
///
/// What the user found after switching tabs is a FRESH panel — so the
/// panel, left open while the switch is pressed, has to show exactly what a
/// fresh one shows. The ink's bake re-records for the ink alone, and it
/// held a copy of every value (the cells pass printed them into every
/// stratum that was not the form): that copy is what stayed.
void main() {
  setUpAll(loadTheAppFaces);
  const cutId = CutId('c');

  Project project() => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 10, 7),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          Cut(
            id: cutId,
            name: '12',
            duration: 24,
            canvasSize: const CanvasSize(width: 640, height: 360),
            camera: CutCamera(
              keyframes: {
                0: CameraPose(center: CanvasPoint(x: 320, y: 180)),
                12: CameraPose(center: CanvasPoint(x: 300, y: 180)),
              },
            ),
            layers: [
              Layer(
                id: const LayerId('a'),
                name: 'A',
                kind: LayerKind.animation,
                frames: [
                  Frame(
                    id: const FrameId('a-1'),
                    duration: 1,
                    strokes: const [],
                  ),
                  Frame(
                    id: const FrameId('a-2'),
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                timeline: const {
                  0: TimelineExposure.drawing(FrameId('a-1'), length: 6),
                  6: TimelineExposure.drawing(FrameId('a-2'), length: 6),
                },
              ),
              createCameraLayer(cutId: cutId),
            ],
          ),
        ],
      ),
    ],
  );

  final rows = {
    'an animation row': const LayerId('a'),
    'the camera row': cameraLayerIdForCut(cutId),
  };

  for (final MapEntry(key: row, value: id) in rows.entries) {
    testWidgets('🎯$row turned off the sheet leaves it at once — the open '
        'panel shows what a fresh one does', (tester) async {
      final session = EditorSessionManager(initialProject: project());
      addTearDown(session.dispose);
      final ink = TimesheetInkController();
      addTearDown(ink.dispose);
      final brushTool = ValueNotifier(BrushToolState.defaults);
      addTearDown(brushTool.dispose);
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const sheet = Key('sheet');

      Widget panel() => MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: sheet,
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) => TimesheetTabHost(
                session: session,
                inkController: ink,
                brushToolState: brushTool,
                brushAllowed: false,
              ),
            ),
          ),
        ),
      );

      Future<Uint8List> shown() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(sheet),
        );
        return (await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List();
        }))!;
      }

      await tester.pumpWidget(panel());
      await tester.pumpAndSettle();
      final on = await shown();

      session.layerSwitches.toggleLayerTimesheet(id);
      await tester.pumpAndSettle();
      final off = await shown();
      expect(off, isNot(on), reason: 'LIVENESS: the row printed something');

      // Another tab and back: a fresh panel over the same project.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(panel());
      await tester.pumpAndSettle();
      expect(off, await shown());
    });
  }
}
