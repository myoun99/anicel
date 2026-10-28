// A CEL NUMBER'S BOX MOVES ITS LETTERS (F-477). 🗣️유저 2026-10-26: 「fx헤더에
// 서있으면 트랜스폼처럼 조작할수있는거 캔버스에 뜨고 조작가능하고, 키에 서도
// 해당 키 조작가능한거면 가능할수 있게 해야하는데 … 기존에 있는거 확인하고
// 공용화할거 적용해서 만들라고」.
//
// Standing on the number's header, or on where it stands, the canvas draws
// the row's box — the same box a transform's header brings — over the
// letters, and each grab keys where the number stands at the playhead: the
// inside its Position, a corner its Scale. ↩️Only a transform's lanes
// declared a box, so the number's drew nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/row_transform_box.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart'
    show PlaybackScope;
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

void main() {
  /// The editing canvas over the default 2340×1654 canvas, its drawing row
  /// active and wearing a cel number — unkeyed, its letters stand in the
  /// paper's middle (1170, 827), at their size.
  Future<(EditorSessionManager, Layer, EffectId)> onTheCanvas(
    WidgetTester tester,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.playbackRig.prerenderScheduler.beginInputHold();
    final row = s.requireActiveCut.layers.firstWhere(layerAcceptsBrushInput);
    s.selectLayer(row.id);
    s.effectsAndFx.addEffectToActiveLayer(EffectKind.celNumber);
    final number = s.layerById(row.id)!.effects.single;
    expect(number.kind, EffectKind.celNumber, reason: 'the premise');
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
    return (s, row, number.id);
  }

  RowTransformBox? boxOf(WidgetTester tester) {
    final found = find.byType(RowTransformBox);
    return found.evaluate().isEmpty
        ? null
        : tester.widget<RowTransformBox>(found);
  }

  LayerEffect numberOf(EditorSessionManager s, Layer row) =>
      s.layerById(row.id)!.effects.single;

  /// The middle of [box]'s corners.
  CanvasPoint middleOf(RowTransformBox box) {
    final corners = box.corners;
    return CanvasPoint(
      x: (corners[0].x + corners[2].x) / 2,
      y: (corners[0].y + corners[2].y) / 2,
    );
  }

  void expectPoint(CanvasPoint actual, CanvasPoint expected) {
    expect(actual.x, closeTo(expected.x, 1e-6));
    expect(actual.y, closeTo(expected.y, 1e-6));
  }

  /// The test's own epilogue: the edit's timers run out, the warmer they
  /// woke stopped after them.
  Future<void> wrapUp(WidgetTester tester, EditorSessionManager s) async {
    await tester.pump(const Duration(minutes: 1));
    s.playbackRig.prerenderScheduler.cancel();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('🎯standing on the number\'s header, the box frames its '
      'letters where they stand — and on where it stands too, never on its '
      'colour', (tester) async {
    final (s, row, id) = await onTheCanvas(tester);
    expect(boxOf(tester), isNull, reason: 'standing on nothing that asks');

    for (final lane in [
      effectGroupLaneId(id),
      effectLaneId(id, 'position'),
      effectLaneId(id, 'scale'),
    ]) {
      s.standOnRow(LaneRowAddress(row.id, lane));
      await tester.pump();
      final box = boxOf(tester);
      expect(box, isNotNull, reason: lane);
      expectPoint(box!.pose.center, CanvasPoint(x: 1170, y: 827));
      expectPoint(middleOf(box), CanvasPoint(x: 1170, y: 827));
      expect(box.corners[2].x - box.corners[0].x, greaterThan(0));
      expect(box.move, isNotNull, reason: lane);
      expect(box.scale, isNotNull, reason: lane);
      expect(box.turn, isNull, reason: '「위치/비율 두개 키」 — no rotation');
      expect(box.cross, isNull, reason: 'no anchor point');
    }

    s.standOnRow(LaneRowAddress(row.id, effectLaneId(id, 'ink')));
    await tester.pump();
    expect(boxOf(tester), isNull, reason: 'a colour is not grabbed on canvas');
    await wrapUp(tester, s);
  });

  testWidgets('switched off, the number draws nothing — and its box with it', (
    tester,
  ) async {
    final (s, row, id) = await onTheCanvas(tester);
    s.laneVerbs.toggleLaneEffectEnabled(row.id, id, description: 'Off');
    s.standOnRow(LaneRowAddress(row.id, effectGroupLaneId(id)));
    await tester.pump();
    expect(numberOf(s, row).enabled, isFalse, reason: 'the premise');
    expect(boxOf(tester), isNull);
    await wrapUp(tester, s);
  });

  testWidgets('the inside KEYS where the number stands at the playhead — '
      'the row\'s own transform left alone — shown while the hand moves, '
      'ONE undo', (tester) async {
    final (s, row, id) = await onTheCanvas(tester);
    s.standOnRow(LaneRowAddress(row.id, effectGroupLaneId(id)));
    await tester.pump();
    final before = s.layerById(row.id)!;

    boxOf(tester)!.move!.changed(CanvasPoint(x: 1250, y: 900));
    final shown = laneEditInFlight(s.dragPreview.value)?.row;
    expect(
      shown?.effects.single.stand.position.keyAt(0)?.value,
      CanvasPoint(x: 1250, y: 900),
      reason: 'shown while the hand moves',
    );
    expect(s.layerById(row.id), before, reason: 'a drag writes nothing');

    boxOf(tester)!.move!.committed(CanvasPoint(x: 1250, y: 900));
    expect(
      numberOf(s, row).stand.position.keys.keys,
      {0},
      reason: 'one key, at the playhead',
    );
    expect(
      numberOf(s, row).stand.position.keyAt(0)!.value,
      CanvasPoint(x: 1250, y: 900),
    );
    expect(
      s.layerById(row.id)!.transformTrack,
      before.transformTrack,
      reason: 'where the number stands is its own, not the row\'s',
    );
    await tester.pump();
    expectPoint(middleOf(boxOf(tester)!), CanvasPoint(x: 1250, y: 900));

    s.undo();
    expect(s.layerById(row.id), before);
    await wrapUp(tester, s);
  });

  testWidgets('a corner keys its scale, both of them', (tester) async {
    final (s, row, id) = await onTheCanvas(tester);
    s.standOnRow(LaneRowAddress(row.id, effectLaneId(id, 'scale')));
    await tester.pump();
    final width = boxOf(tester)!.corners[2].x - boxOf(tester)!.corners[0].x;

    (boxOf(tester)!.scale! as RowBoxTwoScales).landing.committed(
      CanvasPoint(x: 2, y: 3),
    );
    expect(
      numberOf(s, row).stand.scale.keyAt(0)!.value,
      CanvasPoint(x: 2, y: 3),
    );
    await tester.pump();
    final box = boxOf(tester)!;
    expect(box.corners[2].x - box.corners[0].x, closeTo(width * 2, 1e-6));
    expectPoint(middleOf(box), CanvasPoint(x: 1170, y: 827));
    await wrapUp(tester, s);
  });

  testWidgets('on a row laid elsewhere, the box frames the letters where the '
      'row shows them, and a drop keys where they stand on the row\'s own '
      'paper', (tester) async {
    final (s, row, id) = await onTheCanvas(tester);
    // The row's picture laid 130 to the right of where it rests.
    s.standOnRow(LaneRowAddress(row.id, transformGroupHeaderLane.laneId));
    await tester.pump();
    boxOf(tester)!.move!.committed(CanvasPoint(x: 1300, y: 827));
    s.standOnRow(LaneRowAddress(row.id, effectGroupLaneId(id)));
    await tester.pump();

    final box = boxOf(tester)!;
    expectPoint(box.pose.center, CanvasPoint(x: 1300, y: 827));
    expectPoint(middleOf(box), CanvasPoint(x: 1300, y: 827));

    box.move!.committed(CanvasPoint(x: 1400, y: 900));
    expectPoint(
      numberOf(s, row).stand.position.keyAt(0)!.value,
      CanvasPoint(x: 1270, y: 900),
    );
    await wrapUp(tester, s);
  });

  test('only an effect that draws its own picture brings a box', () {
    const blur = EffectId('blur');
    final effects = [LayerEffect.defaults(id: blur, kind: EffectKind.blur)];
    expect(effectBoxedOn(effects, effectGroupLaneId(blur)), isNull);
    expect(effectBoxedOn(effects, effectLaneId(blur, 'blurriness')), isNull);
  });

  testWidgets('a run shows the film: no box while it plays', (tester) async {
    final (s, row, id) = await onTheCanvas(tester);
    s.standOnRow(LaneRowAddress(row.id, effectGroupLaneId(id)));
    await tester.pump();
    expect(boxOf(tester), isNotNull, reason: '⛔전제');

    s.playbackRig.playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    expect(boxOf(tester), isNull);

    s.playbackRig.playback.stop();
    await wrapUp(tester, s);
  });

  testWidgets('standing on the row\'s transform, the box is the row\'s', (
    tester,
  ) async {
    final (s, row, _) = await onTheCanvas(tester);
    s.standOnRow(LaneRowAddress(row.id, transformGroupHeaderLane.laneId));
    await tester.pump();
    boxOf(tester)!.move!.committed(CanvasPoint(x: 1300, y: 827));
    expect(s.layerById(row.id)!.transformTrack.position.isEmpty, isFalse);
    expect(numberOf(s, row).stand.isEmpty, isTrue);
    await wrapUp(tester, s);
  });
}
