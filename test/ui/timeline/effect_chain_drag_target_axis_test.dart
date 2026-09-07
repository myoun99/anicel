import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart' show EffectId;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
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

  Widget? targetFor(Axis axis, PropertyLaneRow lane) =>
      effectChainRowDragTarget(
        (row: rowFor(lane), lane: lane),
        hooks,
        (
          axis: axis,
          rowExtent: 28,
          dragRows: () => rows,
          onSelectCrossed: (_) {},
          onGripTaken: null,
          onGripReleased: null,
        ),
        child: const SizedBox(),
      );

  test('a chain header gets a target down either axis, and only the axis '
      'differs', () {
    final across = targetFor(Axis.horizontal, header(effectB));
    final down = targetFor(Axis.vertical, header(effectB));
    expect(across, isA<LayerRowDragTarget>());
    expect(down, isA<LayerRowDragTarget>());

    final a = across! as LayerRowDragTarget;
    final b = down! as LayerRowDragTarget;
    expect(a.axis, Axis.horizontal);
    expect(b.axis, Axis.vertical);
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
      final target = targetFor(axis, header(effectA))! as LayerRowDragTarget;
      expect(
        target.onSelectCrossed,
        isNotNull,
        reason:
            'a chain header that cannot grow a selection is exactly the bug '
            'the user reported ($axis)',
      );
    }
  });

  test('a lane that heads no chain declines on both axes, so the caller '
      'falls through to the select-only target', () {
    for (final axis in Axis.values) {
      expect(targetFor(axis, member(effectA)), isNull, reason: '$axis member');
      expect(targetFor(axis, plainGroup()), isNull, reason: '$axis transform');
    }
  });

  test('a header whose effect has left the chain declines on both axes', () {
    rows = [rowFor(header(effectA))];
    for (final axis in Axis.values) {
      expect(targetFor(axis, header(effectB)), isNull, reason: '$axis');
    }
  });

  test('the A5 grip is the CALLER\'s, not the axis\'s', () {
    var taken = 0;
    final pinned =
        effectChainRowDragTarget(
              (row: rowFor(header(effectA)), lane: header(effectA)),
              hooks,
              (
                axis: Axis.horizontal,
                rowExtent: 28,
                dragRows: () => rows,
                onSelectCrossed: (_) {},
                onGripTaken: () => taken += 1,
                onGripReleased: null,
              ),
              child: const SizedBox(),
            )!
            as LayerRowDragTarget;
    expect(pinned.onGripTaken, isNotNull);
    pinned.onGripTaken!();
    expect(taken, 1);

    final unpinned =
        targetFor(Axis.vertical, header(effectA))! as LayerRowDragTarget;
    expect(
      unpinned.onGripTaken,
      isNull,
      reason:
          'the sheet pins nothing — its rail window is a paint clip, so no '
          'held column can be unmounted mid-drag',
    );
  });
}
