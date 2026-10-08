import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/camera/camera_frame_overlay.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/canvas_adjust.dart';

/// I-80: while the camera's frame is adjusted on the canvas, the frame the
/// camera view draws — the dim outside it and its hairline — is the size
/// being dragged, so the dim and the box stand on one frame; closed, it is
/// the project camera's again.
void main() {
  testWidgets('🚨the camera view frames the size the canvas shows while it '
      'is adjusted, and the project camera\'s once it closes', (
    tester,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
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
            session: session,
            brushToolState: brushTool,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    CanvasSize framed() => tester
        .widget<CameraFrameOverlay>(find.byType(CameraFrameOverlay))
        .cameraFrameSize;
    final project = session.camera.cameraFrameSize;
    expect(framed(), project, reason: '⛔전제: nothing adjusted');

    const grabbed = CameraSizeDraft(size: CanvasSize(width: 640, height: 360));
    session.canvasAdjust
      ..begin(grabbed)
      ..show(grabbed.scaled(2, 2));
    await tester.pump();
    expect(framed(), const CanvasSize(width: 1280, height: 720));

    session.canvasAdjust.end();
    await tester.pump();
    expect(framed(), project);

    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });
}
