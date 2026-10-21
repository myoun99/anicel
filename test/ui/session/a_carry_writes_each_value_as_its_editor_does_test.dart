import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/lane_edit_subject.dart';
import 'package:anicel/src/ui/session/lane_verbs.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectLaneId;

/// I-3 ② at the session: the values a header graph's key carries are
/// written as each lane's value editor writes them — key after key, each
/// on what the one before it left — into ONE edit
/// ([LaneVerbs.laneValuesWritten]). The widget half — a key dragged on the
/// graph — is `a_graph_key_is_picked_and_carried_test`.
///
/// The collaborator the law lives in — named so `tool/mutation_run.dart`
/// runs this file for it.
LaneVerbs laneVerbsOf(EditorSessionManager session) => session.laneVerbs;

void main() {
  EditorSessionManager open() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    return session;
  }

  final blurLane = effectLaneId(const EffectId('e1'), 'blurX');

  LaneEditSubject subjectOf({List<LayerEffect> effects = const []}) =>
      LaneEditSubject(
        transformTrack: TransformTrack.empty().copyWith(
          rotation: PropertyTrack<double>().withKey(0, 0).withKey(8, 45),
        ),
        effects: effects,
        commit: (_, _) {},
        preview: (_) => null,
      );

  test('every key named is written, each on what the one before it left, '
      'into one edit', () {
    final session = open();

    final edit = laneVerbsOf(session).laneValuesWritten(
      session.activeLayer!,
      subjectOf(),
      (
        inputs: {
          'rotation': {0: '10', 8: '55'},
        },
        scaleLinked: false,
      ),
    )!;

    final keys = edit.transform.own!.rotation.keys;
    expect(
      {for (final MapEntry(:key, :value) in keys.entries) key: value.value},
      {0: 10, 8: 55},
    );
  });

  test('lanes of two homes — the transform and the effect chain — are '
      'written into the one edit', () {
    final session = open();
    final blur = LayerEffect(
      id: const EffectId('e1'),
      kind: EffectKind.blur,
      parameters: {
        'blurX': EffectParameter(
          track: PropertyTrack<double>().withKey(0, 1).withKey(8, 2),
        ),
      },
    );

    final edit = laneVerbsOf(session).laneValuesWritten(
      session.activeLayer!,
      subjectOf(effects: [blur]),
      (
        inputs: {
          'rotation': {8: '55'},
          blurLane: {8: '7'},
        },
        scaleLinked: false,
      ),
    )!;

    expect(edit.transform.own!.rotation.keys[8]!.value, 55);
    expect(edit.effects!.single.parameters['blurX']!.track.keys[8]!.value, 7);
  });

  test('a value its editor cannot read writes nothing', () {
    final session = open();

    expect(
      laneVerbsOf(session).laneValuesWritten(
        session.activeLayer!,
        subjectOf(),
        (
          inputs: {
            'rotation': {8: 'up'},
          },
          scaleLinked: false,
        ),
      ),
      isNull,
    );
  });
}
