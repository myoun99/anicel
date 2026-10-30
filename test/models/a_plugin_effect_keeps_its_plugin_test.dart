import 'dart:convert';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/ui/text/model_vocabulary.dart';
import 'package:flutter_test/flutter_test.dart';

/// I-132: a plugin's effect is ONE kind ([EffectKind.plugin]) that keeps
/// its plugin's description — its parameters are the plugin's, read by the
/// code that reads the app's own (Q29), and the project keeps the
/// description so a machine without the plugin still shows its lanes
/// (Q28).
void main() {
  Map<String, Object?> describing({String version = '1.0'}) => {
    'spec': 1,
    'id': 'com.example.glow',
    'name': 'Glow',
    'vendor': 'Example',
    'version': version,
    'can': ['cpu'],
    'params': [
      // An id the app's brightness & contrast goes by too.
      {
        'id': 'brightness',
        'kind': 'number',
        'label': 'Glow Amount',
        'default': 25,
        'min': 0,
        'max': 100,
      },
      {
        'id': 'tint',
        'kind': 'color',
        'label': 'Tint',
        'default': [1, 0, 0, 1],
      },
      {'id': 'origin', 'kind': 'point', 'label': 'Origin'},
      {'id': 'mask', 'kind': 'layer', 'label': 'Mask'},
      {
        'id': 'mode',
        'kind': 'menu',
        'label': 'Mode',
        'choices': [
          {'id': 'keyColors', 'label': 'Soft'},
          {'id': 'hard', 'label': 'Hard'},
        ],
        'default': 1,
      },
    ],
  };
  FxPluginDescription glow({String version = '1.0'}) =>
      FxPluginDescription.fromJson(describing(version: version))!;
  LayerEffect effectOf(FxPluginDescription plugin) => LayerEffect.defaults(
    id: const EffectId('fx-glow'),
    kind: EffectKind.plugin,
    plugin: plugin,
  );

  test('its parameters are its plugin\'s, each kept where its unit is', () {
    final effect = effectOf(glow());

    expect(effect.specs, same(effect.plugin!.parameters));
    expect(effect.lanes, ['brightness', 'tint', 'origin', 'mask', 'mode']);
    expect(effect.parameters.keys, ['brightness', 'mode']);
    expect(effect.parameterOf('brightness').value, 25);
    expect(effect.parameterOf('mode').value, 1);
    expect(effect.colors.keys, ['tint']);
    expect(effect.points.keys, ['origin']);
    expect(effect.layers, {'mask': null});
    expect(effect.specOf('tint')!.unit, EffectParameterUnit.color);
    expect(effect.specOf('contrast'), isNull);
  });

  test('a plugin is added as one of the plugins, never as the kind alone — '
      'and only a plugin\'s effect keeps one', () {
    expect(effectKindsAddedAlone, isNot(contains(EffectKind.plugin)));
    expect(effectKindsAddedAlone, [
      for (final kind in EffectKind.values)
        if (kind != EffectKind.plugin) kind,
    ]);
    expect(
      () => LayerEffect(id: const EffectId('e'), kind: EffectKind.plugin),
      throwsArgumentError,
    );
    expect(
      LayerEffect(
        id: const EffectId('e'),
        kind: EffectKind.blur,
        plugin: glow(),
      ).plugin,
      isNull,
    );
  });

  test('a fresh one is drawn — its defaults are its plugin\'s to mean — and '
      'its sample carries its plugin and its plugin\'s values', () {
    final effect = effectOf(glow());
    final resolved = resolveLayerEffectsAt(effects: [effect], frameIndex: 0);

    expect(resolved, hasLength(1));
    final sample = resolved.single;
    expect(sample.isNoOp, isFalse);
    expect(sample.plugin, effect.plugin);
    expect(sample.specs, same(effect.plugin!.parameters));
    expect(sample.parameter('brightness'), 25);
    expect(sample.color('tint'), 0xFFFF0000);
    expect(sample.parameter('mode'), 1);
    expect(sample.layers, {'mask': null});

    final naming = resolveLayerEffectsAt(
      effects: [effect.withLayer('mask', const LayerId('matte'))],
      frameIndex: 0,
    ).single;
    expect(naming.layers, {'mask': const LayerId('matte')});
    expect(naming.namingNoRow.layers, {'mask': null});
    expect(naming.namingNoRow.plugin, effect.plugin);
  });

  test('its values are read as an app kind\'s are — held, and keyed', () {
    final held = effectOf(
      glow(),
    ).withParameter('brightness', EffectParameter(value: 60));
    final keyed = held.withParameter(
      'brightness',
      EffectParameter(
        value: 60,
        track: PropertyTrack<double>(
          keys: {0: const PropertyKey<double>(0), 8: const PropertyKey(80)},
        ),
      ),
    );
    double at(LayerEffect effect, int frame) => resolveLayerEffectsAt(
      effects: [effect],
      frameIndex: frame,
    ).single.parameter('brightness');

    expect(at(held, 3), 60);
    expect(at(keyed, 4), 40);
  });

  test('the project keeps it whole: written and read back it is the same '
      'effect, its plugin the same plugin', () {
    final keyed = effectOf(glow())
        .withParameter(
          'brightness',
          EffectParameter(
            value: 60,
            track: PropertyTrack<double>(
              keys: {4: const PropertyKey<double>(80)},
            ),
          ),
        )
        .withLayer('mask', const LayerId('matte'));

    final json = jsonDecode(jsonEncode(keyed.toJson())) as Map<String, dynamic>;
    expect(json['plugin'], describing());
    expect(
      effectOf(glow()).toJson()['parameters'],
      isEmpty,
      reason: 'a parameter at its plugin\'s default says nothing',
    );
    final read = LayerEffect.fromJson(json);

    expect(read, keyed);
    expect(read.hashCode, keyed.hashCode);
    expect(identical(read.plugin, keyed.plugin), isFalse);
    expect(read.plugin, keyed.plugin);
  });

  test('an effect of no plugin writes none and reads none', () {
    final blur = LayerEffect.defaults(
      id: const EffectId('b'),
      kind: EffectKind.blur,
    );
    expect(blur.toJson().containsKey('plugin'), isFalse);
    expect(
      LayerEffect.fromJson({...blur.toJson(), 'plugin': describing()}).plugin,
      isNull,
    );
  });

  test('a plugin\'s effect whose description is not whole is refused, as an '
      'effect of a kind this app has not is', () {
    final json = effectOf(glow()).toJson();
    expect(
      () => LayerEffect.fromJson({...json}..remove('plugin')),
      throwsArgumentError,
    );
    expect(
      () => LayerEffect.fromJson({
        ...json,
        'plugin': {...describing()}..remove('vendor'),
      }),
      throwsArgumentError,
    );
  });

  test('two plugins are two effects — another version is another plugin', () {
    final one = effectOf(glow());
    final two = effectOf(glow(version: '2.0'));

    expect(one.plugin, glow());
    expect(one, isNot(two));
    expect(
      resolveLayerEffectsAt(effects: [one], frameIndex: 0),
      isNot(resolveLayerEffectsAt(effects: [two], frameIndex: 0)),
    );
    expect(one.copyWith(enabled: false).plugin, one.plugin);
  });

  test('it goes by its plugin\'s name, and its lanes and words by the '
      'plugin\'s own — an id the app has too reads the plugin\'s', () {
    final effect = effectOf(glow());

    expect(effect.label, 'Glow');
    expect(LayerEffect.labelOf(EffectKind.plugin, glow()), 'Glow');
    expect(LayerEffect.labelOf(EffectKind.blur, null), EffectKind.blur.label);
    for (final language in AppLanguage.values) {
      expect(effect.labelFor(language), 'Glow');
      expect(effect.specOf('brightness')!.labelFor(language), 'Glow Amount');
      expect(
        [
          for (final choice in effect.specOf('mode')!.choices)
            choice.labelFor(language),
        ],
        ['Soft', 'Hard'],
      );
    }
    final blur = LayerEffect.defaults(
      id: const EffectId('b'),
      kind: EffectKind.blur,
    );
    expect(
      blur.labelFor(AppLanguage.ja),
      EffectKind.blur.labelFor(AppLanguage.ja),
    );
  });
}
