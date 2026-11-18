import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/a_plugin_that_shifts.dart';

/// card a-plugin-step-is-keyed-by-a-moment-it-may-not-read: a run of a
/// plugin is signed by the part of its moment the plugin reads — the frame
/// and the time where it reads them, the rate and the scale always.
void main() {
  FxPluginRun at(
    FxPluginRunner runner,
    int frame, {
    double rate = 24,
    double scale = 1,
  }) => FxPluginRun(
    runner: runner,
    moment: (
      frameIndex: frame,
      time: frame / rate,
      frameRate: rate,
      scale: scale,
    ),
    rows: const {},
  );

  test('a run of a plugin that reads no moment is one at every frame', () {
    final runner = ShiftingFxPlugin(by: 1, readsTheMoment: false);
    expect(at(runner, 2), at(runner, 7));
    expect(at(runner, 2).hashCode, at(runner, 7).hashCode);
  });

  test('it is another at another rate or scale: the cut\'s and the '
      'canvas\'s, which it may read', () {
    final runner = ShiftingFxPlugin(by: 1, readsTheMoment: false);
    expect(at(runner, 2, rate: 30), isNot(at(runner, 2)));
    expect(at(runner, 2, scale: 0.5), isNot(at(runner, 2)));
  });

  test('a run of a plugin that reads the moment is its frame\'s', () {
    final runner = ShiftingFxPlugin(by: 1);
    expect(at(runner, 2), at(runner, 2), reason: '⛔CONTROL: equal at one');
    expect(at(runner, 2), isNot(at(runner, 7)));
  });
}
