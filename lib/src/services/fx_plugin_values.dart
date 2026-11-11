/// What a frame hands a plugin besides its picture: its values, a parameter
/// four doubles, and the rows its layer parameters read — wherever the
/// plugin stands in a chain (`FxPluginStages`, `PluginEffect`).
///
/// ↩️🗣️I-132-Q32 (유저 2026-10-30): 「b 로 첫 판, 이어서 a」 — b: a plugin at
/// the head of a cel row's chain, with nothing before it but colour keys,
/// ran here on the CPU over the keyed cel, at the seam every route showed a
/// cel through; its cost, named with the answer: 「무거운 플러그인은 그 행이
/// 바뀔 때마다 캔버스가 그만큼 멈춘다(같은 프레임 · 같은 값은 보관해서 한 번만
/// 돈다)」. a is float-warp-resamples-in-the-c-engine (2) (관제 2026-11-11):
/// it runs as a step of the row's chain, as a plugin anywhere else does —
/// the frame stays on the picture it showed till the step has run
/// (🗣️I-132-Q34 a), and the step is kept on the cel it ran over.
///
/// ⛔A WHOLE PICTURE, NEVER A TILE. A plugin may move a pixel anywhere in
/// its reach — or read the whole picture for one pixel — so it is handed
/// its picture in one piece and gives back one; nothing asks it of a tile.
library;

import 'dart:typed_data';

import '../models/canvas_size.dart';
import '../models/fx_plugin_description.dart';
import '../models/fx_plugin_run.dart';
import '../models/layer_effect.dart';
import '../models/layer_id.dart';

/// The rows [effect]'s layer parameters name that its run holds, each once,
/// in the order the parameters name them — the order of `frame->layers`.
List<LayerId> fxPluginRowsOf(ResolvedLayerEffect effect, FxPluginRun run) => [
  ...{
    for (final row in effect.layers.values)
      if (row != null && run.rows.containsKey(row)) row,
  },
];

/// [effect]'s values as a frame hands them (anicel_fx_value: four doubles a
/// parameter, in its parameters' order) — a point where [paper] puts it, a
/// layer the place of its row in [rows], or -1 where it names none.
Float64List fxPluginValuesOf(
  ResolvedLayerEffect effect, {
  required CanvasSize paper,
  required List<LayerId> rows,
}) {
  final specs = effect.specs;
  final values = Float64List(specs.length * 4);
  for (final (index, spec) in specs.indexed) {
    final at = index * 4;
    final value = effect.parameter(spec.id);
    switch (spec.unit) {
      case EffectParameterUnit.color:
        values.setAll(at, FxPluginDescription.channelsOf(value.toInt()));
      case EffectParameterUnit.point:
        final point = effectPointOnPaper(effect.points[spec.id], paper);
        values
          ..[at] = point.x
          ..[at + 1] = point.y;
      case EffectParameterUnit.flag:
        values[at] = effectFlagIsOn(value) ? 1 : 0;
      case EffectParameterUnit.layer:
        final row = effect.layers[spec.id];
        values[at] = row == null ? -1 : rows.indexOf(row).toDouble();
      case EffectParameterUnit.number ||
          EffectParameterUnit.degrees ||
          EffectParameterUnit.pixels ||
          EffectParameterUnit.choice:
        values[at] = value;
    }
  }
  return values;
}
