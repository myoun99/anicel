import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/camera/camera_view_toggle_button.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/timeline/frame_panel_sill_controls.dart';

/// R28 #1 (relocated 2026-08-10): camera view is a VIEW MODE, so the toggle
/// sits beside the transport on every panel that has one. The transport
/// moved to the 문턱, and the toggle went with it — both panels' sill
/// controls mount the SAME button against the workspace's ONE notifier,
/// which is the part that matters: a second button owning its own state
/// would let the panels disagree about what the canvas is showing.
void main() {
  Future<ValueNotifier<bool>> pumpSill(
    WidgetTester tester, {
    required String keyValue,
    required PlaybackScope scope,
    bool withCameraState = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final manager = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(manager.dispose);

    // The workspace owns this; both panels are handed the same object.
    final cameraView = ValueNotifier<bool>(false);
    addTearDown(cameraView.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: FramePanelSillControls(
              session: manager,
              scope: scope,
              cameraViewKeyValue: keyValue,
              cameraViewEnabled: withCameraState ? cameraView : null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cameraView;
  }

  testWidgets('the storyboard sill carries the camera-view toggle, and it '
      'drives the shared notifier', (tester) async {
    final cameraView = await pumpSill(
      tester,
      keyValue: 'storyboard-camera-view-button',
      scope: PlaybackScope.allCuts,
    );

    final button = find.byKey(
      const ValueKey<String>('storyboard-camera-view-button'),
    );
    expect(button, findsOneWidget);
    expect(
      find.byType(CameraViewToggleButton),
      findsOneWidget,
      reason: 'the storyboard mounts the SHARED button, not a copy',
    );

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
      cameraView.value,
      isTrue,
      reason: 'the storyboard toggle writes the workspace notifier',
    );

    // External change (the timeline button or the camera row) reflects here.
    cameraView.value = false;
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(cameraView.value, isTrue);
  });

  testWidgets('the timeline sill carries the same button under its own key', (
    tester,
  ) async {
    final cameraView = await pumpSill(
      tester,
      keyValue: 'timeline-camera-view-button',
      scope: PlaybackScope.activeCut,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-camera-view-button')),
    );
    await tester.pumpAndSettle();
    expect(cameraView.value, isTrue);
  });

  testWidgets('no camera context, no button', (tester) async {
    await pumpSill(
      tester,
      keyValue: 'storyboard-camera-view-button',
      scope: PlaybackScope.allCuts,
      withCameraState: false,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-camera-view-button')),
      findsNothing,
    );
  });

  testWidgets('the settings pill rides the sill beside the transport', (
    tester,
  ) async {
    // 유저 확정: fps · 오디오 Hz · 재생 품질 all fold into ⚙, and ⚙ lives
    // where the transport does — not in the command bar between the frame
    // verbs, where a rough pass had to read past them.
    await pumpSill(
      tester,
      keyValue: 'timeline-camera-view-button',
      scope: PlaybackScope.activeCut,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('project-settings-button')),
    );
    await tester.pumpAndSettle();

    // 유저 2026-08-27: the menu is VALUE ROWS, one per setting — the
    // choices themselves moved into each row's change window.
    expect(
      find.byKey(const ValueKey<String>('project-settings-fps')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('project-settings-audio-rate')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('project-settings-camera-size')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('project-settings-quality')),
      findsOneWidget,
    );

    // One level deeper: the FPS row opens the window that still carries
    // the preset keys the toolbar era minted.
    await tester.tap(
      find.byKey(const ValueKey<String>('project-settings-fps')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('timeline-fps-24')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('project-fps-field')),
      findsOneWidget,
    );
  });

  testWidgets('the camera row opens the size window, and applying writes '
      'one undoable project frame', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Disposed at the BODY's end, not in a tearDown: the edit below arms
    // the session's debounce timers, and the pending-timer invariant runs
    // before tearDowns do.
    final manager = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    final before = manager.cameraFrameSize;

    final cameraView = ValueNotifier<bool>(false);
    addTearDown(cameraView.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: FramePanelSillControls(
              session: manager,
              scope: PlaybackScope.activeCut,
              cameraViewKeyValue: 'timeline-camera-view-button',
              cameraViewEnabled: cameraView,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('project-settings-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('project-settings-camera-size')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('camera-size-width-field')),
      '960',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('camera-size-height-field')),
      '430',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('camera-size-apply-button')),
    );
    await tester.pumpAndSettle();

    expect(
      manager.cameraFrameSize,
      const CanvasSize(width: 960, height: 430),
    );

    manager.undo();
    expect(manager.cameraFrameSize, before);

    await tester.pumpWidget(const SizedBox.shrink());
    manager.dispose();
  });
}
