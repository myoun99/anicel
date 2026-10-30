import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// I-132-Q29 (「플러그인 파라미터는 앱의 것을 읽는 코드가 읽는다」): a plugin's
/// effect stands in the lanes under its plugin's name, each row named as
/// the plugin names it, and its lanes are edited by the verbs the app's
/// are — a number held to the plugin's range, a colour, a reset to the
/// plugin's defaults. An id the app's kinds go by too is the plugin's own.
void main() {
  final glow = FxPluginDescription.fromJson({
    'spec': 1,
    'id': 'com.example.glow',
    'name': 'Glow',
    'vendor': 'Example',
    'version': '1',
    'can': ['cpu'],
    'params': [
      // The app's blur goes by this id, with another range.
      {
        'id': 'blurriness',
        'kind': 'number',
        'label': 'Glow Amount',
        'default': 25,
        'min': 0,
        'max': 40,
      },
      {
        'id': 'tint',
        'kind': 'color',
        'label': 'Tint',
        'default': [1, 0, 0, 1],
      },
    ],
  })!;
  const id = EffectId('fx-glow');
  final effect = LayerEffect.defaults(
    id: id,
    kind: EffectKind.plugin,
    plugin: glow,
  );
  final amount = effectLaneId(id, 'blurriness');
  final tint = effectLaneId(id, 'tint');

  test('its header is its plugin\'s name, its rows its plugin\'s lanes in '
      'its plugin\'s words', () {
    final rows = effectPropertyLanes([effect], isExpanded: (_) => true);

    expect(rows.first.isGroupHeader, isTrue);
    expect(rows.first.label, 'Glow');
    expect(rows.skip(1).map((row) => row.laneId), [amount, tint]);
    expect(rows.skip(1).map((row) => row.label), ['Glow Amount', 'Tint']);
  });

  test('a typed number is held to the plugin\'s range, not the app\'s', () {
    final typed = effectsWithLaneValueEdited(
      [effect],
      laneId: amount,
      frameIndex: 3,
      input: '90',
      scaleLinked: false,
    )!;

    expect(typed.single.parameterOf('blurriness').track.keyAt(3)!.value, 40);
    expect(typed.single.plugin, glow);
  });

  test('a typed colour keys its colour', () {
    final typed = effectsWithLaneValueEdited(
      [effect],
      laneId: tint,
      frameIndex: 2,
      input: '#00FF00',
      scaleLinked: false,
    )!;

    expect(typed.single.colors['tint']!.keyAt(2)!.value, 0xFF00FF00);
  });

  test('the group reset puts a keyed number back at the plugin\'s default',
      () {
    final keyed = effectsWithLaneValueEdited(
      [effect],
      laneId: amount,
      frameIndex: 3,
      input: '10',
      scaleLinked: false,
    )!;

    final reset = effectsWithGroupReset(
      keyed,
      laneId: effectGroupLaneId(id),
      frameIndexes: const [3],
    )!;

    expect(reset.single.parameterOf('blurriness').track.keyAt(3)!.value, 25);
  });
}
