import '../models/layer_effect.dart'
    show LayerEffect, ResolvedLayerEffect, resolveLayerEffectsAt;

/// The V row's EFFECT chain, for every route that draws a cut.
///
/// This file was `storyboard_cut_fade_policy.dart` and held the V row's whole
/// transform: the canonical fade shape the block-edge handles wrote, the pose
/// resolution, the cut-window projection and the camera↔canvas pose remap. All
/// of it went with the transform teardown — a track's pose was AE precomp for
/// stacking one track on the stage, and its fade is F.I/F.O spans on the
/// transition row now, where the span's length IS the ramp.
///
/// What survived is the effect chain, so the file says that instead.

/// The V track's chain SAMPLED at GLOBAL [frameIndex] — the effects that land
/// on the whole composited cut, resolved the one way for every route that
/// draws one (the editing track stack, playback, export).
///
/// 🚨★★★A CHAIN, NOT A PAINT — and that was the bug this replaced.
///
/// This used to hand back a `CompositeEffectPaint`, resolved here. A colour
/// key has no paint form (it is a threshold, and a threshold has no colour
/// matrix), so the resolver REFUSES one — by assert. A track chain with a
/// colour key in it therefore threw, exactly as the live layer's did until
/// #1314. It was unreachable only because the fx menu adds to the active
/// layer and nothing calls `addEffectToTrack`; "no caller" is not a design.
///
/// ⛔SO THE HALVES ARE TAKEN AT THE DRAW, like every other row. A layer row
/// hands `List<ResolvedLayerEffect>` to `drawPosedLayerImage`, which builds
/// the plan where it knows the raster it is drawing into. A track row now
/// does the same thing, which is also why `rasterScale` left this file: it
/// was never this function's to know.
///
/// [enabled] is the V row's fx master ([Track.fxEnabled]): off bypasses the
/// chain. It has nothing else left to bypass.
List<ResolvedLayerEffect> trackEffectsAt(
  List<LayerEffect> effects,
  int frameIndex, {
  bool enabled = true,
}) {
  if (!enabled || effects.isEmpty) {
    return const <ResolvedLayerEffect>[];
  }
  return resolveLayerEffectsAt(effects: effects, frameIndex: frameIndex);
}
