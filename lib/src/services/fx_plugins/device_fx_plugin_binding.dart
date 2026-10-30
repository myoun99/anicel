import '../../models/bitmap_surface.dart';
import '../../models/cut.dart';
import '../../models/fx_plugin_binding.dart';
import '../../models/fx_plugin_description.dart';
import '../../models/fx_plugin_run.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_kind.dart';
import '../../models/project_frame_rate.dart';
import '../cut_frame_composite_plan.dart'
    show LayerFrameSurfaceResolver, layerDrawingAt;

/// The binding a route that knows the device and the project runs plugins
/// by: each plugin of a row's chain through [runnerFor] — this device's
/// build of it, null where it has none — at [frameRate], each row a plugin
/// reads as [surfaceOf] holds its cel.
///
/// 🗣️I-132-Q34 a (유저 2026-10-30): 「어디에 걸어도 돌고」 — every plugin of
/// the chain, not the head's alone: that one runs over the cel's own pixels
/// (`splitSourceEffects`), the rest over what the chain made before them
/// (`PluginEffect`).
FxPluginBinding deviceFxPluginBinding({
  required FxPluginRunner? Function(FxPluginDescription plugin) runnerFor,
  required ProjectFrameRate frameRate,
  required LayerFrameSurfaceResolver surfaceOf,
}) => (effects, {required cut, required row, required frameIndex}) {
  if (!effects.any((effect) => effect.kind == EffectKind.plugin)) {
    return effects;
  }
  ResolvedLayerEffect bound(ResolvedLayerEffect plugin) {
    final runner = runnerFor(plugin.plugin!);
    if (runner == null) {
      return plugin;
    }
    return plugin.withRun(
      FxPluginRun(
        runner: runner,
        moment: (
          frameIndex: frameIndex,
          time: frameRate.frameStartSeconds(frameIndex),
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

/// Whether [chain]'s effect [effectId] — a plugin's, switched on — stands
/// where no plugin runs: 🗣️I-132-Q33 c 「머리 이름 뒤에 경고 글자를 늘
/// 둔다」.
///
/// 🗣️I-132-Q34 a ran every plugin of a chain the binding is handed — a
/// row's that the plan reads cels or images of. ⏳A folder's, an
/// adjustment's and a track's never reach it yet, so one there stands
/// idle: [kind] is the kind of the row whose chain it is, null for a chain
/// that is no row's (a track's).
bool pluginStandsIdle(
  List<LayerEffect> chain,
  EffectId effectId, {
  required LayerKind? kind,
}) {
  final at = chain.indexWhere((effect) => effect.id == effectId);
  if (at < 0 || chain[at].kind != EffectKind.plugin || !chain[at].enabled) {
    return false;
  }
  return kind == null || kind.groupsLayers || kind.filtersBelow;
}

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
