import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// 🗣️F-363 (유저 2026-10-15): 「카메라 불투명도는 레이어랑 통일. 레이어가
/// 눈이랑 불투명도 바꾸면 언두 저장되니까. 기본적으로 레이어 버튼은 그게
/// 기준」 — the camera row's slider is its layer's opacity, previewed and
/// committed as every row's is, and the camera view's dim reads it.
///
/// ↩️R27 #4/#9 routed the slider by ROW KIND: the camera row's wrote a dim
/// notifier the window held, never the layer — so no file kept it, and a
/// project opened in the window came up at the last one's dim.
void main() {
  Future<EditorSessionManager> pumpRail(WidgetTester tester) =>
      pumpTimelineHost(
        tester,
        createDefaultProject(),
        surface: const Size(800, 600),
        pixelsPerFrame: 24,
      );

  FieldSlider sliderFor(WidgetTester tester, LayerId layerId) =>
      tester.widget<FieldSlider>(
        find.named('timeline-layer-opacity-$layerId'),
      );

  double opacityOf(EditorSessionManager session, LayerId layerId) =>
      session.layers.firstWhere((layer) => layer.id == layerId).opacity;

  LayerId cameraOf(EditorSessionManager session) =>
      session.layers.firstWhere((layer) => layer.kind == LayerKind.camera).id;

  testWidgets('the CAMERA row previews like every row, and the camera view\'s '
      'dim follows the drag', (tester) async {
    final session = await pumpRail(tester);
    final camera = cameraOf(session);
    final before = opacityOf(session, camera);

    sliderFor(tester, camera).onChanged!(0.4);

    expect(session.opacityVerbs.dragPreview.value?.layerIds, {camera});
    expect(session.cameraViewMode.dim.value, closeTo(0.4, 1e-9));
    expect(opacityOf(session, camera), before, reason: 'a drag writes nothing');
  });

  testWidgets('🚨its release writes the LAYER — one undo — and the dim reads '
      'it', (tester) async {
    final session = await pumpRail(tester);
    final camera = cameraOf(session);
    final before = opacityOf(session, camera);
    expect(before, isNot(0.25), reason: '⛔전제');

    sliderFor(tester, camera).onChanged!(0.4);
    sliderFor(tester, camera).onChangeEnd!(0.25);
    await tester.pumpAndSettle();

    expect(session.opacityVerbs.dragPreview.value, isNull);
    expect(opacityOf(session, camera), closeTo(0.25, 1e-9));
    expect(session.cameraViewMode.dim.value, closeTo(0.25, 1e-9));
    expect(sliderFor(tester, camera).value, closeTo(0.25, 1e-9));

    session.undo();
    await tester.pumpAndSettle();
    expect(opacityOf(session, camera), before);
    expect(session.cameraViewMode.dim.value, before);
  });

  testWidgets('every OTHER row previews and commits the same way, and leaves '
      'the dim alone', (tester) async {
    final session = await pumpRail(tester);
    final camera = cameraOf(session);
    final dim = session.cameraViewMode.dim.value;
    final drawing = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;

    sliderFor(tester, drawing).onChanged!(0.4);
    expect(session.opacityVerbs.dragPreview.value?.layerIds, {drawing});
    expect(session.cameraViewMode.dim.value, dim);

    sliderFor(tester, drawing).onChangeEnd!(0.25);
    expect(opacityOf(session, drawing), closeTo(0.25, 1e-9));
    expect(opacityOf(session, camera), dim);
    expect(session.cameraViewMode.dim.value, dim);
  });
}
