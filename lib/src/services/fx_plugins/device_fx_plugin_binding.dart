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
/// [surfaceOf] holds its cel — where [runningPluginIndex] says one runs.
FxPluginBinding deviceFxPluginBinding({
  required FxPluginRunner? Function(FxPluginDescription plugin) runnerFor,
  required ProjectFrameRate frameRate,
  required LayerFrameSurfaceResolver surfaceOf,
}) => (effects, {required cut, required row, required frameIndex}) {
  final at = runningPluginIndex(effects, row.kind);
  if (at == null) {
    return effects;
  }
  final plugin = effects[at];
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

/// Where in [effects] — the chain of a row of [kind], resolved at a frame —
/// a plugin runs: the index of the one that does, null where none does.
///
/// 🗣️I-132-Q32 b: a plugin runs on a cel row, at the head of its chain or
/// after nothing but colour keys ([splitSourceEffects]); 「폴더 · 조정 ·
/// 이미지 행에 걸면 그 플러그인은 걸리지 않은 채」. A folder's and an
/// adjustment's chains never reach the binding, which asks this of the rows
/// the plan reads cels of; they are named here because the header that
/// warns of a plugin standing where none runs asks this same rule
/// ([pluginStandsIdle]).
int? runningPluginIndex(List<ResolvedLayerEffect> effects, LayerKind kind) {
  if (kind == LayerKind.image || kind.groupsLayers || kind.filtersBelow) {
    return null;
  }
  final at = splitSourceEffects(effects).source.length - 1;
  return at >= 0 && effects[at].kind == EffectKind.plugin ? at : null;
}

/// Whether [chain]'s effect [effectId] — a plugin's, switched on — stands
/// where no plugin runs at [frameIndex]: 🗣️I-132-Q33 c 「머리 이름 뒤에 경고
/// 글자를 늘 둔다」.
///
/// Asked of the chain up to it, resolved as the plan resolves a row's
/// ([resolveLayerEffectsAt]), by the rule the binding runs plugins by
/// ([runningPluginIndex]): whether a plugin runs is settled by what stands
/// before it. A plugin is never dropped as changing nothing, so one that is
/// on is the last of what that resolves to. [kind] is the kind of the row
/// whose chain it is — null for a chain that is no row's (a track's), which
/// no plugin runs on.
bool pluginStandsIdle(
  List<LayerEffect> chain,
  EffectId effectId, {
  required LayerKind? kind,
  required int frameIndex,
}) {
  final at = chain.indexWhere((effect) => effect.id == effectId);
  if (at < 0 || chain[at].kind != EffectKind.plugin || !chain[at].enabled) {
    return false;
  }
  if (kind == null) {
    return true;
  }
  final resolved = resolveLayerEffectsAt(
    effects: chain.sublist(0, at + 1),
    frameIndex: frameIndex,
  );
  return runningPluginIndex(resolved, kind) != resolved.length - 1;
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
