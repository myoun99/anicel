import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectPropertyLanes;

/// UI-R5 — the V track's own lane rows are a place the lane VERBS work.
///
/// They resolve a Layer, and a V row's lanes hang off a synthetic carrier
/// id that is not one. The lookup found nothing and the verbs reported
/// "no keys here", so Delete fell through to the CEL path: standing on a
/// V lane and pressing Delete removed the active layer's drawing instead
/// of the keys under the cursor — or did nothing at all, depending on
/// whether that layer had a cel there. Both answers are wrong.
void main() {
  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(manager.dispose);
    return manager;
  }

  /// A keyed brightness effect on the V row — the only lanes a track row has
  /// since its Transform group was torn down
  /// ([timelineRowOwnsTransform] answers no for a track).
  LayerEffect brightness({Map<int, double>? keys}) => LayerEffect(
    id: const EffectId('fx-1'),
    kind: EffectKind.brightnessContrast,
    parameters: {
      'brightness': EffectParameter(
        value: 0.5,
        track: keys == null
            ? null
            : PropertyTrack<double>(
                keys: {
                  for (final entry in keys.entries)
                    entry.key: PropertyKey<double>(entry.value),
                },
              ),
      ),
    },
  );

  /// The lane id of that effect's `brightness` parameter, as the rail builds it.
  String brightnessLaneId(LayerEffect effect) =>
      effectPropertyLanes([effect], isExpanded: (_) => true)
          .firstWhere((lane) => !lane.isGroupHeader)
          .laneId;

  test('Delete on a V EFFECT lane removes THAT lane\'s key, and leaves the '
      'active layer\'s cel alone', () {
    final manager = session();
    final trackId = manager.activeTrack.id;
    final effect = brightness(keys: {0: 0.5});
    manager.updateTrackEffects(trackId, [effect]);
    final celsBefore = manager.activeLayer!.timeline.length;

    manager.selectRow(
      LaneRowAddress(
        trackTransformLaneCarrierId(trackId),
        brightnessLaneId(effect),
      ),
    );
    expect(
      manager.canDeleteCellAtCurrentFrame,
      isTrue,
      reason: 'the key under the cursor is what Delete is offered for',
    );

    manager.deleteCellAtCurrentFrame();

    expect(
      manager.activeTrack.effects.single.parameters['brightness']!.track,
      anyOf(isNull, predicate<PropertyTrack<double>>((t) => t.isEmpty)),
      reason: 'the lane key is gone',
    );
    expect(
      manager.activeLayer!.timeline.length,
      celsBefore,
      reason: 'and the drawing the user was NOT pointing at survived',
    );
  });

  test('Add Key on a V EFFECT lane keys the TRACK behind the carrier', () {
    final manager = session();
    final trackId = manager.activeTrack.id;
    final effect = brightness();
    manager.updateTrackEffects(trackId, [effect]);
    expect(
      manager.activeTrack.effects.single.parameters['brightness']!.track,
      anyOf(isNull, predicate<PropertyTrack<double>>((t) => t.isEmpty)),
    );

    manager.selectRow(
      LaneRowAddress(
        trackTransformLaneCarrierId(trackId),
        brightnessLaneId(effect),
      ),
    );
    manager.createInstancesForSelection();

    expect(
      manager.activeTrack.effects.single.parameters['brightness']!.track
          .isNotEmpty,
      isTrue,
      reason: 'the verb reached the TRACK behind the carrier',
    );
  });
}
