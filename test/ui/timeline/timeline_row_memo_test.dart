import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// UI-R20 #4 (the "selecting a layer got slow" regression): the sparse
/// rows (camera, SE) must reuse their cached row INSTANCES across
/// unrelated session notifies — their display identities are cached
/// upstream and their external inputs ride the memo token now.
void main() {
  Future<EditorSessionManager> pumpHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manager = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(manager.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: manager,
            builder: (context, _) => TimelineTabHost(
              session: manager,
              orientation: TimelineOrientation.horizontal,
              onOrientationChanged: (_) {},
              pixelsPerFrame: 24,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return manager;
  }

  testWidgets('camera and SE rows keep their widget INSTANCES across an '
      'unrelated layer selection (memo hit)', (tester) async {
    final manager = await pumpHost(tester);
    final cameraLayer = manager.layers.firstWhere(
      (layer) => layer.kind == LayerKind.camera,
    );
    final seLayer = manager.trackSeDisplayLayers.first;

    // Sparse rows (camera/SE) render through the widget path — their
    // stable key is the frame-row area.
    final cameraRow = find.byKey(
      ValueKey<String>('timeline-frame-row-area-${cameraLayer.id.value}'),
    );
    final seRow = find.byKey(
      ValueKey<String>('timeline-frame-row-area-${seLayer.id.value}'),
    );
    expect(cameraRow, findsOneWidget);
    expect(seRow, findsOneWidget);
    final cameraBefore = tester.widget(cameraRow);
    final seBefore = tester.widget(seRow);

    // An unrelated notify: select the (already?) first drawing layer —
    // force a real notify by toggling to another anim layer if present,
    // else re-selecting still notifies through selectLayer.
    final animLayer = manager.layers.firstWhere(
      (layer) => layer.kind == LayerKind.animation,
    );
    manager.selectLayer(animLayer.id);
    await tester.pump();

    expect(
      identical(tester.widget(cameraRow), cameraBefore),
      isTrue,
      reason: 'the camera row must ride its memo across notifies',
    );
    expect(
      identical(tester.widget(seRow), seBefore),
      isTrue,
      reason:
          'the SE row must ride its memo across notifies '
          '(display-clone identity is cached now)',
    );
  });

  testWidgets('a camera KEY edit does invalidate the camera row', (
    tester,
  ) async {
    final manager = await pumpHost(tester);
    final cameraLayer = manager.layers.firstWhere(
      (layer) => layer.kind == LayerKind.camera,
    );
    final cameraRow = find.byKey(
      ValueKey<String>('timeline-frame-row-area-${cameraLayer.id.value}'),
    );
    final before = tester.widget(cameraRow);

    manager.setCameraKeyframeAtCurrentFrame(manager.cameraPoseAtCurrentFrame);
    await tester.pump();

    expect(
      identical(tester.widget(cameraRow), before),
      isFalse,
      reason: 'the camera-track identity joined the memo token',
    );
    // Drain the edit's prerender warm-up before teardown.
    await tester.pumpAndSettle();
  });
}
