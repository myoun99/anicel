import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer_effect.dart';

/// An fx plugin's description (anicel_fx_plugin.h) read as the app's own
/// parameters — each of the seven kinds the app's effects have — and kept
/// in a project as it was given; and every description that leaves out
/// what its kind says refused, never made whole.
void main() {
  Map<String, Object?> plugin(List<Map<String, Object?>> params) => {
    'spec': 1,
    'id': 'com.example.every-kind',
    'name': 'Every Kind',
    'vendor': 'Example',
    'version': '2.1.0',
    'can': ['cpu', 'gpu'],
    'params': params,
  };

  final everyKind = plugin([
    {
      'id': 'amount',
      'kind': 'number',
      'label': 'Amount',
      'default': 25,
      'min': 0,
      'max': 100,
    },
    {
      'id': 'turn',
      'kind': 'angle',
      'label': 'Turn',
      'default': -30,
      'min': -180,
      'max': 180,
    },
    {
      'id': 'tint',
      'kind': 'color',
      'label': 'Tint',
      'default': [1, 0.2, 0, 1],
    },
    {'id': 'centre', 'kind': 'point', 'label': 'Centre'},
    {'id': 'soft', 'kind': 'checkbox', 'label': 'Soft', 'default': true},
    {
      'id': 'shape',
      'kind': 'menu',
      'label': 'Shape',
      'choices': [
        {'id': 'round', 'label': 'Round'},
        {'id': 'square', 'label': 'Square'},
      ],
      'default': 1,
    },
    {'id': 'map', 'kind': 'layer', 'label': 'Map'},
    {'id': 'hard', 'kind': 'checkbox', 'label': 'Hard', 'default': false},
  ]);

  test('each kind is the app parameter of its kind', () {
    final description = FxPluginDescription.read(jsonEncode(everyKind))!;
    expect(description.id, 'com.example.every-kind');
    expect(description.version, '2.1.0');
    expect(description.can, ['cpu', 'gpu']);
    final specs = description.parameters;
    expect([for (final spec in specs) spec.unit], [
      EffectParameterUnit.number,
      EffectParameterUnit.degrees,
      EffectParameterUnit.color,
      EffectParameterUnit.point,
      EffectParameterUnit.flag,
      EffectParameterUnit.choice,
      EffectParameterUnit.layer,
      EffectParameterUnit.flag,
    ]);
    expect([specs[0].defaultValue, specs[0].minimum, specs[0].maximum], [
      25,
      0,
      100,
    ]);
    expect([specs[1].defaultValue, specs[1].minimum, specs[1].maximum], [
      -30,
      -180,
      180,
    ]);
    expect(specs[2].defaultValue.toInt(), 0xFFFF3300);
    expect(effectFlagIsOn(specs[4].defaultValue), isTrue);
    expect([for (final choice in specs[5].choices) choice.id], [
      'round',
      'square',
    ]);
    expect(specs[5].defaultValue, 1);
    expect(effectFlagIsOn(specs[7].defaultValue), isFalse);
  });

  test('what a project keeps reads back as the same description', () {
    final first = FxPluginDescription.read(jsonEncode(everyKind))!;
    final again = FxPluginDescription.fromJson(
      jsonDecode(jsonEncode(first.toJson())),
    )!;
    // What it keeps is what the plugin said — a colour of whole bytes
    // reads back to the very fractions.
    expect(first.toJson(), everyKind);
    expect(jsonEncode(again.toJson()), jsonEncode(first.toJson()));
    expect(
      [for (final spec in again.parameters) (spec.id, spec.unit, spec.label)],
      [for (final spec in first.parameters) (spec.id, spec.unit, spec.label)],
    );
    expect(again.parameters[2].defaultValue, first.parameters[2].defaultValue);
  });

  group('a description that is not whole is no plugin', () {
    Map<String, Object?> amount(Map<String, Object?> change) => {
      'id': 'amount',
      'kind': 'number',
      'label': 'Amount',
      'default': 0,
      'min': 0,
      'max': 100,
      ...change,
    }..removeWhere((_, value) => value == null);

    final refused = <String, Object?>{
      'not JSON': '{"spec":',
      'another spec': {...plugin([]), 'spec': 2},
      'no cpu among what it can do': {
        ...plugin([]),
        'can': ['gpu'],
      },
      'what it can do not said in words': {
        ...plugin([]),
        'can': ['cpu', 3],
      },
      'an id a lane would misread': {...plugin([]), 'id': 'com:example'},
      'a parameter of an id a lane would misread': plugin([
        amount({'id': 'glow:amount'}),
      ]),
      'a number with no range': plugin([amount({'max': null})]),
      'a default past its range': plugin([amount({'default': 101})]),
      'a kind the app has not': plugin([amount({'kind': 'curve'})]),
      'two parameters of one id': plugin([amount({}), amount({})]),
      'a colour past 1': plugin([
        {
          'id': 'tint',
          'kind': 'color',
          'label': 'Tint',
          'default': [1.5, 0, 0, 1],
        },
      ]),
      'a checkbox with no default': plugin([
        {'id': 'soft', 'kind': 'checkbox', 'label': 'Soft'},
      ]),
      'a menu past its words': plugin([
        {
          'id': 'shape',
          'kind': 'menu',
          'label': 'Shape',
          'choices': [
            {'id': 'round', 'label': 'Round'},
          ],
          'default': 1,
        },
      ]),
      'a menu before its words': plugin([
        {
          'id': 'shape',
          'kind': 'menu',
          'label': 'Shape',
          'choices': [
            {'id': 'round', 'label': 'Round'},
          ],
          'default': -1,
        },
      ]),
      'a word of an id a lane would misread': plugin([
        {
          'id': 'shape',
          'kind': 'menu',
          'label': 'Shape',
          'choices': [
            {'id': 'round edge', 'label': 'Round'},
          ],
          'default': 0,
        },
      ]),
      'a menu with no words': plugin([
        {
          'id': 'shape',
          'kind': 'menu',
          'label': 'Shape',
          'choices': <Object?>[],
          'default': 0,
        },
      ]),
    };
    for (final MapEntry(key: why, value: json) in refused.entries) {
      test(why, () {
        final text = json is String ? json : jsonEncode(json);
        expect(FxPluginDescription.read(text), isNull);
      });
    }
  });
}
