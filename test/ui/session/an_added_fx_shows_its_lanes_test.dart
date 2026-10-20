import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/services/project_lookup.dart' show rowTwirlsOf;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// 🗣️F-396 (유저 2026-10-18): 「레이어 fx펼침 접은상태에서 fx추가하면 펼치고
/// 해당 fx헤더도 펼치도록. 그래야 처음 사용하는 입장에서 알기쉬움」 — an
/// added effect is shown where it lands: its row's lanes twirled down and
/// its own header open, in the add's one undo step.
void main() {
  late EditorSessionManager s;

  setUp(() {
    s = EditorSessionManager(initialProject: createDefaultProject());
  });
  tearDown(() => s.dispose());

  ({bool lanesExpanded, Set<String> expandedLaneGroups}) twirlsOf(
    LayerId row,
  ) => rowTwirlsOf(s.repository.requireProject(), row)!;

  // A record compares its Set by identity, so each half is matched alone.
  void expectTwirls(LayerId row, {required bool lanes, Set<String>? groups}) {
    final twirls = twirlsOf(row);
    expect(twirls.lanesExpanded, lanes);
    expect(twirls.expandedLaneGroups, groups ?? <String>{});
  }

  test('a layer shut to its lanes opens them, and the new effect\'s header '
      'with them — one undo shuts both and takes the effect', () {
    final row = s.requireActiveCut.layers.first.id;
    s.selectLayer(row);
    expect(twirlsOf(row).lanesExpanded, isFalse, reason: '⛔전제');

    s.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);

    final blur = s.commitLayerById(row)!.effects.single.id;
    expectTwirls(row, lanes: true, groups: {effectGroupLaneId(blur)});
    expect(s.railView.expandedLaneLayerIds.value, contains(row));

    s.undo();
    expect(s.commitLayerById(row)!.effects, isEmpty);
    expectTwirls(row, lanes: false);

    s.redo();
    expect(s.commitLayerById(row)!.effects.single.id, blur);
    expect(twirlsOf(row).expandedLaneGroups, {effectGroupLaneId(blur)});
  });

  test('a row already open keeps what it had open, and adds the header', () {
    final row = s.requireActiveCut.layers.first.id;
    s.selectLayer(row);
    s.layerSwitches.toggleLayerLanes(row);
    s.layerSwitches.setLayerLaneGroupExpanded(
      row,
      transformGroupHeaderLane.laneId,
      expanded: true,
    );

    s.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);

    final blur = s.commitLayerById(row)!.effects.single.id;
    expectTwirls(
      row,
      lanes: true,
      groups: {transformGroupHeaderLane.laneId, effectGroupLaneId(blur)},
    );
  });

  test('an S row is shown on its track, where its twirls live', () {
    final se = s.layers.firstWhere((layer) => layer.kind == LayerKind.se).id;
    s.selectLayer(se);
    expect(s.effectsAndFx.canAddEffectToActiveLayer, isTrue, reason: '⛔전제');

    s.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);

    final blur = s.commitLayerById(se)!.effects.single.id;
    expectTwirls(se, lanes: true, groups: {effectGroupLaneId(blur)});
    s.undo();
    expectTwirls(se, lanes: false);
  });

  test('the V row is shown as a layer is — by its lane carrier', () {
    final track = s.repository.requireProject().tracks.first;
    final carrier = trackTransformLaneCarrierId(track.id);

    s.effectsAndFx.addEffectToTrack(track.id, EffectKind.blur);

    final blur = s.repository.requireProject().tracks.first.effects.single.id;
    expectTwirls(carrier, lanes: true, groups: {effectGroupLaneId(blur)});
    s.undo();
    expect(s.repository.requireProject().tracks.first.effects, isEmpty);
    expectTwirls(carrier, lanes: false);
  });
}
