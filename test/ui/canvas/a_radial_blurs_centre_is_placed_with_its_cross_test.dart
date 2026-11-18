// A RADIAL BLUR'S CENTRE IS PLACED WITH ITS CROSS — Amount or none
// (a-radial-blur-centre-lane-veils-the-canvas). 🔎I-136 on the Surface: a
// radial blur freshly added, standing on its Center lane or its header, the
// canvas went under a light grey veil and the cross under it took no drag.
//
// The box asked where the centre stands of the chain's answer, which drops
// an effect that changes no pixel — and an Amount of 0, the radial blur's
// rest, changes none. Its `.single` threw in the build, and a release build
// draws a build that threw as a grey box. Where an effect stands is asked
// of its sample, every lane, whatever it changes (sampleLayerEffectAt).
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_offset.dart';
import 'package:anicel/src/ui/canvas/row_transform_box.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';

void main() {
  /// The editing canvas over the default 2340×1654 canvas, its drawing row
  /// active and wearing a radial blur just added — its Amount at rest, 0,
  /// and its centre unkeyed: the paper's middle (1170, 827).
  Future<(EditorSessionManager, Layer, EffectId)> onTheCanvas(
    WidgetTester tester,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.playbackRig.prerenderScheduler.beginInputHold();
    final row = s.requireActiveCut.layers.firstWhere(layerAcceptsBrushInput);
    s.selectLayer(row.id);
    s.effectsAndFx.addEffectToActiveLayer(EffectKind.radialBlur);
    final blur = s.layerById(row.id)!.effects.single;
    expect(blur.kind, EffectKind.radialBlur, reason: 'the premise');
    final tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(false);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(tool.dispose);
    addTearDown(cameraView.dispose);
    addTearDown(cameraDim.dispose);
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: s,
            brushToolState: tool,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
    await tester.pump();
    return (s, row, blur.id);
  }

  RowTransformBox boxOf(WidgetTester tester) =>
      tester.widget<RowTransformBox>(find.byType(RowTransformBox));

  /// Where [point] on the canvas shows on the screen, through the box's view.
  Offset onScreen(WidgetTester tester, CanvasPoint point) =>
      tester.getTopLeft(find.byType(RowTransformBox)) +
      boxOf(tester).viewport.canvasToViewportOffset(point);

  TransformTrack? centreOf(EditorSessionManager s, Layer row) =>
      s.layerById(row.id)!.effects.single.points['center'];

  /// The test's own epilogue: the edit's timers run out.
  Future<void> wrapUp(WidgetTester tester) async {
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('🎯at no Amount, its Center lane and its header still show the '
      'cross where the centre stands — and nothing over the canvas', (
    tester,
  ) async {
    final (s, row, id) = await onTheCanvas(tester);
    final blur = s.layerById(row.id)!.effects.single;
    expect(
      sampleLayerEffectAt(blur, frameIndex: 0, blocks: null, worn: null)
          .isNoOp,
      isTrue,
      reason: '⛔전제: the blur as added changes no pixel',
    );

    for (final lane in [effectLaneId(id, 'center'), effectGroupLaneId(id)]) {
      s.standOnRow(LaneRowAddress(row.id, lane));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: lane);
      expect(find.byType(ErrorWidget), findsNothing, reason: lane);
      final box = boxOf(tester);
      expect(box.corners, isEmpty, reason: lane);
      expect(box.cross?.at, CanvasPoint(x: 1170, y: 827), reason: lane);
    }
    await wrapUp(tester);
  });

  testWidgets('a drag of the cross keys the centre where it lets go — one '
      'key at the playhead, one undo', (tester) async {
    final (s, row, id) = await onTheCanvas(tester);
    s.standOnRow(LaneRowAddress(row.id, effectLaneId(id, 'center')));
    await tester.pump();
    final zoom = boxOf(tester).viewport.zoom;
    expect(centreOf(s, row)?.position.isEmpty ?? true, isTrue);

    final gesture = await tester.startGesture(
      onScreen(tester, CanvasPoint(x: 1170, y: 827)),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(const Offset(25, 10));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    final keys = centreOf(s, row)!.position;
    expect(keys.keys.keys, {0}, reason: 'one key, at the playhead');
    final at = keys.keyAt(0)!.value;
    expect(at.x - 1170, inInclusiveRange(100 / zoom - 1, 100 / zoom + 1));
    expect(at.y - 827, inInclusiveRange(40 / zoom - 1, 40 / zoom + 1));
    expect(boxOf(tester).cross?.at, at, reason: 'the cross stands there');

    s.undo();
    expect(centreOf(s, row)?.position.isEmpty ?? true, isTrue);
    await wrapUp(tester);
  });
}
