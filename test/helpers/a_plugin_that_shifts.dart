import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';

/// A run of [runner] at [frame], reading [rows].
FxPluginRun fxPluginRunOf(
  FxPluginRunner runner, {
  Map<LayerId, BitmapSurface?> rows = const {},
  int frame = 0,
}) => FxPluginRun(
  runner: runner,
  moment: (frameIndex: frame, time: frame / 24, frameRate: 24, scale: 1),
  rows: rows,
);

/// A plugin with no parameters that moves every pixel [by] to the right —
/// across a tile's edge, so no tile of what it makes is a tile's own.
ResolvedLayerEffect shiftingFxPluginEffect({int by = 1}) => ResolvedLayerEffect(
  kind: EffectKind.plugin,
  plugin: FxPluginDescription.fromJson({
    'spec': 1,
    'id': 'test.shift',
    'name': 'Shift',
    'vendor': 'Test',
    'version': '1',
    'can': ['cpu'],
    'params': <Object?>[],
  }),
  values: const [],
  run: fxPluginRunOf(ShiftingFxPlugin(by: by)),
);

/// Moves every pixel right by its first value — reaching that far — or by
/// [by] where it is told one.
final class ShiftingFxPlugin implements FxPluginRunner {
  ShiftingFxPlugin({this.by, this.fails = false, this.reachFails = false});

  final int? by;
  final bool fails;
  final bool reachFails;
  int renders = 0;
  final List<({int left, int top, int width, int height})> inputs = [];
  late Uint8List lastInput;
  late Float64List lastValues;
  late List<FxPluginPicture> lastLayers;

  @override
  int? reach(Float64List values, FxPluginMoment moment) =>
      reachFails ? null : by ?? values[0].toInt();

  @override
  Uint8List? render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) {
    renders += 1;
    inputs.add((
      left: input.left,
      top: input.top,
      width: input.width,
      height: input.height,
    ));
    lastInput = input.pixels;
    lastValues = values;
    lastLayers = layers;
    if (fails) {
      return null;
    }
    final shift = by ?? values[0].toInt();
    final out = Uint8List(input.pixels.length);
    for (var y = 0; y < input.height; y += 1) {
      for (var x = shift; x < input.width; x += 1) {
        final to = (y * input.width + x) * 4;
        final from = to - shift * 4;
        out.setRange(to, to + 4, input.pixels, from);
      }
    }
    return out;
  }

  @override
  void close() {}
}
