import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart' show EffectId;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
import 'package:anicel/src/ui/timeline/held_row_pin.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨AN FX CHAIN HEADER'S DRAG TARGET IS ONE FUNCTION, AND THE AXIS IS ITS
/// ONLY TURN.
///
/// The rail and the sheet each spelled the whole target — the same four
/// gates, the same subject, the same `effectChainAfterCrossing` tail — one
/// with `Axis.horizontal` and one with `Axis.vertical` (the audit's clone
/// scan, round 8). B4-3 is the bug that shape produced once already: one of
/// the two copies had `onCrossed` and no `onSelectCrossed`, so a span
/// anchored on a lane never grew.
///
/// So this asks both axes the same questions and demands the same answers,
/// and pins the one difference that is real — the A5 grip, which the rail
/// supplies and the sheet has nothing to pin for.
///
/// ⚠️It asks them of [layerRowDragWrapper], the ONE entrance both grids
/// call: which target a lane row gets is a question about the ROW, decided
/// inside the wrapper, so a test that reached past it into the branch could
/// not see a grid routing itself wrongly again.
void main() {
  const layerId = LayerId('layer-1');
  const effectA = EffectId('fx-a');
  const effectB = EffectId('fx-b');
  final layer = Layer(id: layerId, name: 'A', frames: const []);

  PropertyLaneRow header(EffectId effectId) => PropertyLaneRow(
    laneId: effectGroupLaneId(effectId),
    label: effectId.value,
    keyedFrames: const {},
    isGroupHeader: true,
  );

  PropertyLaneRow member(EffectId effectId) => PropertyLaneRow(
    laneId: effectLaneId(effectId, 'amount'),
    label: 'amount',
    keyedFrames: const {},
  );

  PropertyLaneRow plainGroup() => const PropertyLaneRow(
    laneId: 'transform',
    label: 'Transform',
    keyedFrames: {},
    isGroupHeader: true,
  );

  TimelineDisplayRow rowFor(PropertyLaneRow lane) =>
      TimelineDisplayRow.lane(layer, lane, layerIndex: 0);

  late ValueNotifier<LayerRowDragState?> drag;
  late TimelineRowDragHooks hooks;
  late List<TimelineDisplayRow> rows;

  setUp(() {
    drag = ValueNotifier<LayerRowDragState?>(null);
    rows = [rowFor(header(effectA)), rowFor(header(effectB))];
    hooks = TimelineRowDragHooks(
      drag: drag,
      onBegin: (_) {},
      onUpdate: (_, _, {pointerInRow}) {},
      onRowTarget: (_, _, _) {},
      onEffectUpdate: (_, _, _) {},
      onEnd: () {},
      onCancel: () {},
      onSelectBegin: (_) {},
    );
  });

  tearDown(() => drag.dispose());

  LayerRowDragTarget targetFor(
    Axis axis,
    PropertyLaneRow lane, {
    HeldRowPin? pin,
  }) =>
      layerRowDragWrapper(
            row: rowFor(lane),
            dragRows: () => rows,
            rowExtent: 28,
            axis: axis,
            hooks: hooks,
            onRowSelectionSpan: (_, _) {},
            pin: pin,
            child: const SizedBox(),
          )
          as LayerRowDragTarget;

  test('a chain header gets a target down either axis, and only the axis '
      'differs', () {
    final a = targetFor(Axis.horizontal, header(effectB));
    final b = targetFor(Axis.vertical, header(effectB));
    expect(a.axis, Axis.horizontal);
    expect(b.axis, Axis.vertical);
    expect(
      a.subject,
      isA<EffectRowSubject>(),
      reason: 'a chain header re-orders the chain',
    );
    expect(b.subject, isA<EffectRowSubject>());
    expect(b.slotBefore, a.slotBefore, reason: 'slot 1 of the chain, twice');
    expect(b.isLastRow, a.isLastRow);
    expect(b.rowExtent, a.rowExtent);
    expect(
      (b.subject as EffectRowSubject).effectId,
      (a.subject as EffectRowSubject).effectId,
    );
  });

  test('⛔and BOTH get the select half — the omission B4-3 named', () {
    for (final axis in Axis.values) {
      final target = targetFor(axis, header(effectA));
      expect(
        target.onSelectCrossed,
        isNotNull,
        reason:
            'a chain header that cannot grow a selection is exactly the bug '
            'the user reported ($axis)',
      );
    }
  });

  test('a lane that heads no chain still gets the SELECT-ONLY target on '
      'both axes — never a bare child', () {
    for (final lane in [member(effectA), plainGroup()]) {
      for (final axis in Axis.values) {
        final target = targetFor(axis, lane);
        expect(
          target.subject,
          isA<LaneRowSubject>(),
          reason:
              '$axis ${lane.laneId}: members do not move — the lane anchors '
              'where it is drawn',
        );
        expect(
          target.onSelectCrossed,
          isNotNull,
          reason: '$axis ${lane.laneId}: every row joins a selection',
        );
      }
    }
  });

  test('a header whose effect has left the chain falls to select-only on '
      'both axes', () {
    rows = [rowFor(header(effectA))];
    for (final axis in Axis.values) {
      final target = targetFor(axis, header(effectB));
      expect(target.subject, isA<LaneRowSubject>(), reason: '$axis');
    }
  });

  test('the A5 grip is the CALLER\'s, not the axis\'s', () {
    final pin = HeldRowPin();
    final row = rowFor(header(effectA));
    final pinned = targetFor(Axis.horizontal, header(effectA), pin: pin);
    expect(pinned.onGripTaken, isNotNull);
    pinned.onGripTaken!();
    expect(pin.held, row.address, reason: 'the rail pins the held row');
    pinned.onGripReleased!();
    expect(pin.held, isNull);

    final unpinned = targetFor(Axis.vertical, header(effectA));
    expect(
      unpinned.onGripTaken,
      isNull,
      reason:
          'the sheet pins nothing — its rail window is a paint clip, so no '
          'held column can be unmounted mid-drag',
    );
  });
}
