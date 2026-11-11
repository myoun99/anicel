import '../../models/bitmap_surface.dart';
import '../../models/cut.dart';
import '../../models/fx_plugin_binding.dart';
import '../../models/fx_plugin_description.dart';
import '../../models/fx_plugin_run.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/project_frame_rate.dart';
import '../cut_frame_composite_plan.dart'
    show LayerFrameSurfaceResolver, layerDrawingAt;
import 'fx_plugin_outcomes.dart';

/// The binding a route that knows the device and the project runs plugins
/// by: each plugin of a chain through [runnerFor] — this device's build of
/// it, null where it has none — at [frameRate], each row a plugin reads as
/// [surfaceOf] holds its cel.
///
/// 🗣️I-132-Q34 a (유저 2026-10-30): 「어디에 걸어도 돌고」 — every plugin of
/// the chain, not the head's alone, and every chain: a row's, a folder's,
/// an adjustment's and the V row's. Each runs over what its chain made
/// before it (`PluginEffect`) — the head's of a cel over the cel, its keys
/// run. ↩️The head's of a cel ran over the cel's own pixels on the CPU
/// until it was a step of the chain
/// (float-warp-resamples-in-the-c-engine (2), 2026-11-11).
///
/// A plugin is told the frame its sample is of ([ResolvedLayerEffect.frame])
/// — the V row's chain is sampled on the track's axis — and reads the rows
/// it names at the cut's [FxPluginBinding] frame.
///
/// Each run tells [outcomes] how it went at that same frame, the one its
/// header reads its lanes at, where it is worn ([FxPluginRun.told],
/// [ResolvedLayerEffect.worn]) — and is told as it is bound how its sample
/// went there before ([FxPluginOutcomes.toldFor]); null tells nobody.
FxPluginBinding deviceFxPluginBinding({
  required FxPluginRunner? Function(FxPluginDescription plugin) runnerFor,
  required ProjectFrameRate frameRate,
  required LayerFrameSurfaceResolver surfaceOf,
  FxPluginOutcomes? outcomes,
}) => (effects, {required cut, required frameIndex}) {
  if (!effects.any((effect) => effect.kind == EffectKind.plugin)) {
    return effects;
  }
  ResolvedLayerEffect bound(ResolvedLayerEffect plugin) {
    final runner = runnerFor(plugin.plugin!);
    if (runner == null) {
      return plugin;
    }
    final told = plugin.frame ?? frameIndex;
    final worn = plugin.worn;
    return plugin.withRun(
      FxPluginRun(
        told: outcomes == null || worn == null
            ? null
            : outcomes.toldFor(worn, plugin, cut: cut.id, frame: told),
        runner: runner,
        moment: (
          frameIndex: told,
          time: frameRate.frameStartSeconds(told),
          frameRate: frameRate.approximateFps,
          // A cel's own pixels; a step past them runs at its raster's.
          scale: 1,
        ),
        rows: {
          for (final named in plugin.layers.values.nonNulls)
            if (cut.layers.byId(named) case final read?)
              named: _ownPictureAt(cut, read, frameIndex, surfaceOf),
        },
      ),
    );
  }

  return List.unmodifiable([
    for (final effect in effects)
      if (effect.kind == EffectKind.plugin) bound(effect) else effect,
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
