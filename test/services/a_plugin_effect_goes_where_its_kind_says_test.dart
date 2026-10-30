import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_spec.dart' show ExportLayerFx;
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart'
    show chainWornBy;
import 'package:anicel/src/services/layer_as_output.dart' show chainAsOutput;
import 'package:flutter_test/flutter_test.dart';

/// I-132: a plugin's effect goes where a chain's links go, by the answers
/// its kind gives ([EffectKind.plugin]) — the code that reads an app
/// kind's reads it, nothing asked of it alone.
void main() {
  final glow = FxPluginDescription.fromJson({
    'spec': 1,
    'id': 'com.example.glow',
    'name': 'Glow',
    'vendor': 'Example',
    'version': '1',
    'can': ['cpu'],
    'params': [
      {
        'id': 'amount',
        'kind': 'number',
        'label': 'Amount',
        'default': 5,
        'min': 0,
        'max': 10,
      },
    ],
  })!;
  final effect = LayerEffect.defaults(
    id: const EffectId('fx-glow'),
    kind: EffectKind.plugin,
    plugin: glow,
  );

  test('an output written with the basic fx leaves it, as every link that '
      'is not basic — with all of them, it goes', () {
    expect(chainAsOutput([effect], ExportLayerFx.basic).single.enabled, isFalse);
    expect(chainAsOutput([effect], ExportLayerFx.on).single, effect);
  });

  test('a row attached to its row wears it, as it wears its base\'s blur', () {
    final base = Layer(
      id: const LayerId('a'),
      name: 'A',
      frames: const [],
      effects: [effect],
    );
    final attach = Layer(
      id: const LayerId('b'),
      name: 'A影',
      frames: const [],
      attachedToLayerId: base.id,
      attachedMode: AttachedMode.free,
    );
    final cut = Cut(
      id: const CutId('c'),
      name: 'c',
      duration: 1,
      canvasSize: const CanvasSize(width: 8, height: 6),
      layers: [base, attach],
    );

    expect(chainWornBy(cut, attach), [effect]);
  });

  test('a chain makes room for what it draws past its input, as for a blur',
      () {
    expect(
      resolvedEffectsSpreadPixels(
        resolveLayerEffectsAt(effects: [effect], frameIndex: 0),
      ),
      isTrue,
    );
  });
}
