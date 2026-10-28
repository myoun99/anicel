import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/ui/camera/camera_view_toggle_button.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/timeline/frame_panel_transport.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

/// R28 #1: camera view is a VIEW MODE, so the toggle sits beside the
/// transport on every panel that has one, and goes where it goes — the 문턱
/// from 2026-08-10, the head of each frame panel's bar since F-111. Both
/// panels' transports mount the SAME button against the ONE switch, which is
/// the part that matters: a second button owning its own state would let the
/// panels disagree about what the canvas is showing.
///
/// 🗣️F-363 (유저 2026-10-15): that switch is the project's camera row's eye
/// (「카메라 불투명도는 레이어랑 통일」) — ↩️a notifier the window held, which
/// no file kept.
void main() {
  Future<EditorSessionManager> pumpTransport(
    WidgetTester tester,
    WorkingPanel panel,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) =>
                  FramePanelTransport(session: session, panel: panel),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  bool cameraEye(EditorSessionManager session) =>
      session.activeCutOrNull!.layers.cameraLayer!.isVisible;

  bool lit(WidgetTester tester) => tester
      .widget<AppIconButton>(
        find.descendant(
          of: find.byType(CameraViewToggleButton),
          matching: find.byType(AppIconButton),
        ),
      )
      .isSelected;

  testWidgets('the storyboard\'s transport carries the camera-view toggle, '
      'and it presses the camera row\'s eye', (tester) async {
    const keyValue = 'storyboard-camera-view-button';
    final session = await pumpTransport(tester, WorkingPanel.storyboard);
    final was = cameraEye(session);

    final button = find.byKey(const ValueKey<String>(keyValue));
    expect(button, findsOneWidget);
    expect(
      find.byType(CameraViewToggleButton),
      findsOneWidget,
      reason: 'the storyboard mounts the SHARED button, not a copy',
    );
    expect(lit(tester), was);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(cameraEye(session), !was, reason: 'the toggle is the layer\'s eye');
    expect(lit(tester), !was);

    // The eye pressed elsewhere (the camera row, an undo) shows here.
    session.undo();
    await tester.pumpAndSettle();
    expect(cameraEye(session), was);
    expect(lit(tester), was);
  });

  testWidgets('the timeline\'s transport carries the same button under its '
      'own key', (tester) async {
    final session = await pumpTransport(tester, WorkingPanel.timeline);
    final was = cameraEye(session);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-camera-view-button')),
    );
    await tester.pumpAndSettle();
    expect(cameraEye(session), !was);
  });

  testWidgets('the transport carries no settings ⚙ — the project\'s settings '
      'are the top strip\'s now', (tester) async {
    // 답 playback-quality-home-Q1 「프로젝트 설정으로 같이」: FPS · 오디오 ·
    // 카메라 프레임 · 재생 품질 went to the top strip's ⚙, beside the work's.
    await pumpTransport(tester, WorkingPanel.timeline);

    expect(
      find.byKey(const ValueKey<String>('timeline-camera-view-button')),
      findsOneWidget,
      reason: 'fixture: the transport is there',
    );
    expect(
      find.byKey(const ValueKey<String>('project-settings-button')),
      findsNothing,
    );
  });
}
