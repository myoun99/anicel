import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// R27 #4/#9: a rail row's opacity slider routes by ROW KIND — the camera
/// row's slider IS the camera-view dim notifier, every other row's is the
/// session's layer opacity. Preview (per move) and commit (on release) take
/// the SAME routing decision; only the session verb behind it differs.
///
/// Pinned before the two hooks were folded into one router (the audit's
/// clone scan, round 8): with two copies of the decision, one of them can
/// start answering differently.
void main() {
  Future<EditorSessionManager> pumpRail(
    WidgetTester tester, {
    required ValueNotifier<double> dim,
  }) async {
    final session = EditorSessionManager(initialProject: createDefaultProject());
    session.layerStack.addLayerOfKind(LayerKind.camera);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => TimelineTabHost(
              session: session,
              orientation: TimelineOrientation.horizontal,
              onOrientationChanged: (_) {},
              pixelsPerFrame: 24,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              cameraDimOpacity: dim,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  FieldSlider sliderFor(WidgetTester tester, LayerId layerId) =>
      tester.widget<FieldSlider>(
        find.byKey(ValueKey<String>('timeline-layer-opacity-$layerId')),
      );

  double opacityOf(EditorSessionManager session, LayerId layerId) =>
      session.layers.firstWhere((layer) => layer.id == layerId).opacity;

  testWidgets('the CAMERA row writes the dim on both hooks, and never the '
      'layer', (tester) async {
    final dim = ValueNotifier<double>(1);
    addTearDown(dim.dispose);
    final session = await pumpRail(tester, dim: dim);
    final camera = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.camera)
        .id;
    final before = opacityOf(session, camera);

    sliderFor(tester, camera).onChanged!(0.4);
    expect(dim.value, closeTo(0.4, 1e-9), reason: 'preview lands on the dim');
    expect(session.opacityVerbs.dragPreview.value, isNull);
    expect(opacityOf(session, camera), before);

    sliderFor(tester, camera).onChangeEnd!(0.25);
    expect(dim.value, closeTo(0.25, 1e-9), reason: 'commit lands there too');
    expect(opacityOf(session, camera), before);
  });

  testWidgets('every OTHER row previews on the session and commits to the '
      'layer, leaving the dim alone', (tester) async {
    final dim = ValueNotifier<double>(1);
    addTearDown(dim.dispose);
    final session = await pumpRail(tester, dim: dim);
    final drawing = session.layers
        .firstWhere((layer) => layer.kind != LayerKind.camera)
        .id;

    sliderFor(tester, drawing).onChanged!(0.4);
    expect(dim.value, 1, reason: 'a drawing row never touches the dim');
    expect(session.opacityVerbs.dragPreview.value?.opacity, closeTo(0.4, 1e-9));
    expect(session.opacityVerbs.dragPreview.value?.layerIds, {drawing});
    expect(opacityOf(session, drawing), 1, reason: 'preview does not write');

    sliderFor(tester, drawing).onChangeEnd!(0.25);
    expect(dim.value, 1);
    expect(session.opacityVerbs.dragPreview.value, isNull);
    expect(opacityOf(session, drawing), closeTo(0.25, 1e-9));
  });
}
