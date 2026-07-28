import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/camera/camera_view_toggle_button.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

/// R28 #1: camera view is a VIEW MODE, so the toggle sits beside the
/// transport on every panel that has one — the storyboard included. Both
/// entrances drive the workspace's ONE notifier, which is the part that
/// matters: a second button that owned its own state would let the panels
/// disagree about what the canvas is showing.
void main() {
  testWidgets('R28 #1: the storyboard command bar carries the camera-view '
      'toggle, and it drives the shared notifier', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 600));
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
          body: ListenableBuilder(
            listenable: Listenable.merge([manager, manager.frameSeekCommitted]),
            builder: (context, _) => StoryboardTabHost(
              session: manager,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnailFor: null,
              cameraViewEnabled: cameraView,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

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

  testWidgets('R28 #1: a host without camera context shows no button', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final manager = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([manager, manager.frameSeekCommitted]),
            builder: (context, _) => StoryboardTabHost(
              session: manager,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnailFor: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('storyboard-camera-view-button')),
      findsNothing,
    );
  });
}
