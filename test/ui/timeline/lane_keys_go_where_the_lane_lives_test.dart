// A LANE VERB SETTLES WHOSE LANES IT IS TOUCHING BEFORE IT TOUCHES THEM:
// an EFFECT lane keys the effect chain, and an ATTACH row stands down.
//
// Two survivors of the mutation campaign (2026-09-04, the lane-verb
// prelude unification): the scope reporting `effectLanes: false` for every
// selection — an effect-lane press would then key the layer's TRANSFORM
// track instead — and the attach-row stand-down dropped, which lets a
// synced mirror author timing that belongs to its base. Both mutants
// survived because every existing lane test drove a plain drawing row's
// transform lane, where the two answers coincide.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';

void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
  });

  Layer layerOf(LayerId id) =>
      session.layers.firstWhere((layer) => layer.id == id);

  /// Selects [laneId] on [layerId] over frames [from, to] and asks the
  /// session to create keys there — the verb the ◇ press runs.
  void keyLaneRange(LayerId layerId, String laneId, int from, int to) {
    session.updateLaneRangeSelectionDrag(
      layerId: layerId,
      laneId: laneId,
      anchorIndex: from,
      headIndex: to,
      spanLaneIds: [laneId],
    );
    expect(
      session.createInstancesForSelection(),
      isTrue,
      reason: 'the lane selection is what the verb acts on',
    );
  }

  test('an EFFECT lane selection keys the effect chain, and leaves the '
      'transform track alone', () {
    final layerId = session.activeLayer!.id;
    session.addEffectToActiveLayer(EffectKind.blur);
    final effectId = layerOf(layerId).effects.single.id;
    final laneId = effectLaneId(effectId, 'blurX');

    keyLaneRange(layerId, laneId, 1, 3);

    final after = layerOf(layerId);
    expect(
      after.effects.single.parameterOf('blurX').track.keys.keys,
      containsAll(<int>[1, 2, 3]),
      reason:
          'an effect lane keys the EFFECT chain — a scope that calls '
          'every lane a transform lane keys the wrong track entirely',
    );
    expect(
      after.transformTrack.isEmpty,
      isTrue,
      reason: 'the layer\'s transform track was never the target',
    );
  });

  test('a SYNCED attach row stands down: its lane selection creates '
      'nothing', () {
    final base = session.activeLayer!;
    session.folders.addAttachedLayer(AttachedPlacement.above);
    final attach = session.layers.firstWhere(
      (layer) => layer.attachedToLayerId == base.id,
    );
    expect(attach.transformTrack.isEmpty, isTrue, reason: 'nothing yet');

    session.selectLayer(attach.id);
    keyLaneRangeExpectingNothing(session, attach.id);

    expect(
      layerOf(attach.id).transformTrack.isEmpty,
      isTrue,
      reason:
          'a synced mirror follows its base — a lane verb that does not '
          'stand down lets the mirror author timing of its own',
    );
    expect(
      layerOf(attach.id).effects,
      isEmpty,
      reason: 'and it authored nothing on an effect chain either',
    );
  });
}

/// The same lane press on a row the verb must refuse: the session may
/// answer either way about "did something happen", but the row must come
/// back untouched — which the caller asserts.
void keyLaneRangeExpectingNothing(
  EditorSessionManager session,
  LayerId layerId,
) {
  session.updateLaneRangeSelectionDrag(
    layerId: layerId,
    laneId: 'position',
    anchorIndex: 1,
    headIndex: 3,
    spanLaneIds: const ['position'],
  );
  session.createInstancesForSelection();
}
