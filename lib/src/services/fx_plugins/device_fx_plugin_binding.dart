import '../../models/bitmap_surface.dart';
import '../../models/cut.dart';
import '../../models/fx_plugin_binding.dart';
import '../../models/fx_plugin_description.dart';
import '../../models/fx_plugin_run.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_kind.dart';
import '../../models/project_frame_rate.dart';
import '../cel_source_effect_pass.dart' show splitSourceEffects;
import '../cut_frame_composite_plan.dart'
    show LayerFrameSurfaceResolver, layerDrawingAt;

/// The binding a route that knows the device and the project runs plugins
/// by: each plugin through [runnerFor] — this device's build of it, null
/// where it has none — at [frameRate], each row a plugin reads as
/// [surfaceOf] holds its cel.
///
/// 🗣️I-132-Q32 b: a plugin runs on a cel row, at the head of its chain or
/// after nothing but colour keys ([splitSourceEffects]); 「폴더 · 조정 ·
/// 이미지 행에 걸면 그 플러그인은 걸리지 않은 채」 — a folder's and an
/// adjustment's chains never reach a cel's seam, and an image row's is
/// refused here.
FxPluginBinding deviceFxPluginBinding({
  required FxPluginRunner? Function(FxPluginDescription plugin) runnerFor,
  required ProjectFrameRate frameRate,
  required LayerFrameSurfaceResolver surfaceOf,
}) => (effects, {required cut, required row, required frameIndex}) {
  if (row.kind == LayerKind.image) {
    return effects;
  }
  final at = splitSourceEffects(effects).source.length - 1;
  final plugin = at < 0 ? null : effects[at];
  if (plugin == null || plugin.kind != EffectKind.plugin) {
    return effects;
  }
  final runner = runnerFor(plugin.plugin!);
  if (runner == null) {
    return effects;
  }
  final run = FxPluginRun(
    runner: runner,
    moment: (
      frameIndex: frameIndex,
      time: frameRate.frameStartSeconds(frameIndex),
      frameRate: frameRate.approximateFps,
      // A cel's own pixels: b runs on them before anything is drawn.
      scale: 1,
    ),
    rows: {
      for (final named in plugin.layers.values.nonNulls)
        if (cut.layers.byId(named) case final read?)
          named: _ownPictureAt(cut, read, frameIndex, surfaceOf),
    },
  );
  return List.unmodifiable([
    ...effects.take(at),
    plugin.withRun(run),
    ...effects.skip(at + 1),
  ]);
};

/// [row]'s own picture at [frameIndex] of [cut] — the cel exposed there as
/// its store holds it, with no pose and no chain (🗣️I-132-Q32 b 「그 행의
/// 변형 · fx 없이」); null where no cel is.
BitmapSurface? _ownPictureAt(
  Cut cut,
  Layer row,
  int frameIndex,
  LayerFrameSurfaceResolver surfaceOf,
) => switch (layerDrawingAt(cut: cut, layer: row, frameIndex: frameIndex)) {
  (frame: final frame?, render: _) => surfaceOf(row, frame),
  _ => null,
};
