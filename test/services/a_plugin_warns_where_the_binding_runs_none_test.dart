import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/services/fx_plugins/device_fx_plugin_binding.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/a_plugin_that_shifts.dart';

/// 🗣️I-132-Q33 c 「머리 이름 뒤에 경고 글자를 늘 둔다」: a plugin's header
/// warns where it stands idle ([pluginStandsIdle]) — where the binding is
/// handed no chain to run it in, as 🗣️I-132-Q34 a left it.
/// So every row kind × chain × frame here is asked of the header and of
/// the binding, by whether it ran the plugin; and where it runs is held to
/// 🗣️I-132-Q34 a on its own, so the two cannot agree on a wrong answer.
void main() {
  final other = FxPluginDescription.fromJson({
    'spec': 1,
    'id': 'test.other',
    'name': 'Other',
    'vendor': 'Test',
    'version': '1',
    'can': ['cpu'],
    'params': <Object?>[],
  })!;
  const p = EffectId('p');
  final plugin = LayerEffect.defaults(
    id: p,
    kind: EffectKind.plugin,
    plugin: shiftingFxPluginDescription,
  );
  final first = LayerEffect.defaults(
    id: const EffectId('q'),
    kind: EffectKind.plugin,
    plugin: other,
  );
  LayerEffect blur(EffectParameter amount, {bool enabled = true}) =>
      LayerEffect.defaults(id: const EffectId('b'), kind: EffectKind.blur)
          .withParameter('blurriness', amount)
          .copyWith(enabled: enabled);
  final key = LayerEffect.defaults(
    id: const EffectId('k'),
    kind: EffectKind.colorKey,
  );
  final chains = <String, List<LayerEffect>>{
    'alone': [plugin],
    'after a key': [key, plugin],
    'after a blur': [blur(EffectParameter(value: 3)), plugin],
    'after a blur switched off': [
      blur(EffectParameter(value: 3), enabled: false),
      plugin,
    ],
    'after a blur of nothing': [blur(EffectParameter()), plugin],
    // Nothing at frame 0, a blur from frame 1.
    'after a blur keyed up from nothing': [
      blur(
        EffectParameter(
          track: PropertyTrack<double>().withKey(0, 0).withKey(1, 10),
        ),
      ),
      plugin,
    ],
    'after another plugin': [first, plugin],
    'switched off': [plugin.copyWith(enabled: false)],
  };

  final binding = deviceFxPluginBinding(
    runnerFor: (_) => ShiftingFxPlugin(by: 1),
    frameRate: ProjectFrameRate.fps24,
    surfaceOf: (_, _) => null,
  );
  bool ran(List<LayerEffect> chain, LayerKind kind, int frame) {
    final row = Layer(
      id: const LayerId('a'),
      name: 'a',
      kind: kind,
      frames: const [],
      effects: chain,
    );
    return binding(
      resolveLayerEffectsAt(effects: chain, frameIndex: frame),
      cut: Cut(
        id: const CutId('c'),
        name: 'c',
        duration: 4,
        canvasSize: const CanvasSize(width: 8, height: 8),
        layers: [row],
      ),
      row: row,
      frameIndex: frame,
    ).any(
      (effect) =>
          effect.run != null && effect.plugin == shiftingFxPluginDescription,
    );
  }

  /// The rows whose chains the plan hands the binding: the ones it reads
  /// cels or images of. ⏳A folder's and an adjustment's are not yet.
  bool bound(LayerKind kind) => !kind.groupsLayers && !kind.filtersBelow;

  test('🎯the header warns exactly where no plugin runs — every row kind that '
      'wears a chain, every chain, at two frames', () {
    var asked = 0;
    for (final kind in LayerKind.values.where((kind) => kind.hasLayerEffects)) {
      for (final MapEntry(key: name, value: chain) in chains.entries) {
        final on = chain.singleWhere((effect) => effect.id == p).enabled;
        for (final frame in [0, 1]) {
          expect(
            pluginStandsIdle(chain, p, kind: kind),
            on && !(bound(kind) && ran(chain, kind, frame)),
            reason: '$kind · $name · frame $frame',
          );
          asked += 1;
        }
      }
    }
    expect(asked, greaterThan(chains.length * 2 * 5), reason: '⛔premise');
  });

  test('where it runs (🗣️I-132-Q34 a 「어디에 걸어도 돌고」): wherever it stands '
      'in a cel row\'s chain or an image row\'s, switched on', () {
    for (final kind in [LayerKind.animation, LayerKind.image]) {
      for (final MapEntry(key: name, value: chain) in chains.entries) {
        final on = chain.singleWhere((effect) => effect.id == p).enabled;
        for (final frame in [0, 1]) {
          expect(ran(chain, kind, frame), on, reason: '$kind · $name');
        }
      }
    }
  });

  test('⏳a folder\'s, an adjustment\'s and a track\'s chain runs none yet — '
      'one switched off warns nowhere', () {
    for (final kind in [LayerKind.folder, LayerKind.adjustment]) {
      expect(
        pluginStandsIdle([plugin], p, kind: kind),
        isTrue,
        reason: '$kind',
      );
    }
    expect(
      pluginStandsIdle([plugin], p, kind: null),
      isTrue,
      reason: 'a track\'s chain',
    );
    expect(
      pluginStandsIdle([plugin.copyWith(enabled: false)], p, kind: null),
      isFalse,
    );
  });

  test('only a plugin\'s effect of the chain is asked', () {
    final chain = chains['after a blur']!;
    for (final id in [const EffectId('b'), const EffectId('gone')]) {
      expect(
        pluginStandsIdle(chain, id, kind: LayerKind.folder),
        isFalse,
        reason: '$id',
      );
      expect(
        pluginStandsIdle(chain, id, kind: null),
        isFalse,
        reason: '$id on a track',
      );
    }
  });
}
