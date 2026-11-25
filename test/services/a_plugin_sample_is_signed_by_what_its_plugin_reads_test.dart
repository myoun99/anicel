import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/fx_plugins/device_fx_plugin_binding.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/a_plugin_that_shifts.dart';

/// card the-first-stroke-on-a-frame-come-to-runs-its-plugins-once ③: a
/// plugin's sample as the chain carries it — sampled at its frame and
/// bound there, as every route that runs it does — is the same at every
/// frame of a cut where its plugin reads no moment (`ResolvedLayerEffect.
/// frame`): what a frame made ahead and the pen's frame compare
/// (`FxPluginStages`), and what two frames' keys do.
void main() {
  final effect = LayerEffect.defaults(
    id: const EffectId('fx'),
    kind: EffectKind.plugin,
    plugin: shiftingFxPluginDescription,
  );
  final row = Layer(
    id: const LayerId('a'),
    name: 'a',
    kind: LayerKind.animation,
    frames: const [],
    effects: [effect],
  );
  final cut = Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 12,
    canvasSize: const CanvasSize(width: 64, height: 64),
    layers: [row],
  );

  /// [effect] sampled at [frame] and bound there to [runner] — unbound
  /// where there is none.
  ResolvedLayerEffect sampledAt(int frame, ShiftingFxPlugin? runner) =>
      deviceFxPluginBinding(
        runnerFor: (_) => runner,
        frameRate: ProjectFrameRate.fps24,
        surfaceOf: (_, _) => null,
      )(
        resolveLayerEffectsAt(
          effects: [effect],
          frameIndex: frame,
          blocks: null,
          worn: (owner: row.id, wearer: row.id),
        ),
        cut: cut,
        frameIndex: frame,
      ).single;

  test('bound to a plugin that reads no moment, it is one sample at every '
      'frame', () {
    final runner = ShiftingFxPlugin(by: 1, readsTheMoment: false);
    final (two, seven) = (sampledAt(2, runner), sampledAt(7, runner));
    expect(two.frame, isNot(seven.frame), reason: '⛔premise: two frames');
    expect(two.run, isNotNull, reason: '⛔premise: bound');

    expect(two, seven);
    expect(two.hashCode, seven.hashCode);
  });

  test('bound to one that reads it, it is its frame\'s', () {
    final runner = ShiftingFxPlugin(by: 1);
    expect(sampledAt(2, runner), sampledAt(2, runner), reason: '⛔CONTROL');
    expect(sampledAt(2, runner), isNot(sampledAt(7, runner)));
  });

  test('unbound, it is its frame\'s: what it would be told is all that '
      'says what it draws', () {
    expect(sampledAt(2, null).run, isNull, reason: '⛔premise: unbound');
    expect(sampledAt(2, null), sampledAt(2, null), reason: '⛔CONTROL');
    expect(sampledAt(2, null), isNot(sampledAt(7, null)));
  });
}
