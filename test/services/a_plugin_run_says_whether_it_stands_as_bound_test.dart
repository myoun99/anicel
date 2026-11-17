import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/fx_plugins/device_fx_plugin_binding.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/a_plugin_that_shifts.dart';

/// H57: a frame's key kept over a plug-in's step is handed out again while
/// its run is still the one its binding would make now
/// (`FxPluginRun.standsAsBound`) — equal to the run bound again, which a
/// frame stacked anew would sign.
void main() {
  const paper = CanvasSize(width: 8, height: 8);
  final reading = FxPluginDescription.fromJson({
    ...shiftingFxPluginDescription.toJson(),
    'params': [
      {'id': 'map', 'kind': 'layer', 'label': 'Map'},
    ],
  })!;
  final m = Layer(
    id: const LayerId('m'),
    name: 'm',
    frames: [Frame(id: const FrameId('m0'), duration: 1, strokes: const [])],
    timeline: const {0: TimelineExposure.drawing(FrameId('m0'), length: 4)},
  );
  final cut = Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 4,
    canvasSize: paper,
    layers: [m],
  );
  final effect = LayerEffect.defaults(
    id: const EffectId('p'),
    kind: EffectKind.plugin,
    plugin: reading,
  ).withLayer('map', const LayerId('m'));

  late BitmapSurface held;
  late FxPluginRunner runner;
  FxPluginRun bound() =>
      deviceFxPluginBinding(
        runnerFor: (_) => runner,
        frameRate: ProjectFrameRate.fps24,
        surfaceOf: (_, _) => held,
      )(
        resolveLayerEffectsAt(
          effects: [effect],
          frameIndex: 1,
          blocks: null,
          worn: null,
        ),
        cut: cut,
        frameIndex: 1,
      ).single.run!;

  setUp(() {
    held = BitmapSurface(canvasSize: paper);
    runner = ShiftingFxPlugin(readsTheMoment: false);
  });

  test('a run stands while what bound it would bind it so again', () {
    final run = bound();

    expect(run.standsAsBound, isTrue);
    expect(bound(), run, reason: 'the run bound again is equal');
  });

  test('🚨a row it reads holding another picture — it stands no more, and '
      'the run bound again is another', () {
    final run = bound();

    held = BitmapSurface(canvasSize: paper);

    expect(run.standsAsBound, isFalse);
    expect(bound(), isNot(run));
  });

  test('its runner let go — it stands no more', () {
    final run = bound();

    runner.close();

    expect(run.standsAsBound, isFalse);
  });

  test('its runner\'s word on the moment changing — a build opening — it '
      'stands no more, and the run bound again is another', () {
    final opening = _Opening();
    runner = opening;
    final run = bound();

    opening.readsTheMoment = false;

    expect(run.standsAsBound, isFalse);
    expect(bound(), isNot(run));
  });

  test('a run that reads rows with no word on them from what made it cannot '
      'say it stands', () {
    final run = FxPluginRun(
      runner: runner,
      moment: (frameIndex: 0, time: 0, frameRate: 24, scale: 1),
      rows: {const LayerId('m'): held},
    );

    expect(run.standsAsBound, isFalse);
  });

  test('a run that reads no rows stands on its runner and its moment', () {
    final run = FxPluginRun(
      runner: runner,
      moment: (frameIndex: 0, time: 0, frameRate: 24, scale: 1),
      rows: const {},
    );

    expect(run.standsAsBound, isTrue);
  });
}

/// A build whose word on the moment changes as it opens
/// ([FxPluginRunner.readsTheMoment]): one still to come signs with all of
/// it.
final class _Opening implements FxPluginRunner {
  final ShiftingFxPlugin _build = ShiftingFxPlugin();

  @override
  bool readsTheMoment = true;

  @override
  Future<void>? get toCome => null;

  @override
  int? reach(Float64List values, FxPluginMoment moment) =>
      _build.reach(values, moment);

  @override
  Future<FxPluginTiles?> render({
    required FxPluginInput input,
    required Float64List values,
    required FxPluginMoment moment,
  }) => _build.render(input: input, values: values, moment: moment);

  @override
  void close() => _build.close();

  @override
  bool get closed => _build.closed;
}
